// Copyright 2026, Martin L. Purschke
// Subject to the terms in the LICENSE file found in the top-level directory.

#pragma once

#include <edm4hep/RawCalorimeterHitCollection.h>

#include <Event/Event.h>
#include <Event/packet.h>

#include <cstdint>
#include <memory>

#include "RCDAQEventHolder.h"
#include "extensions/jana/JOmniFactory.h"

namespace eicrecon {

struct RCDAQRawCalorimeterHitConfig {
  int packet_id = 1003; // which rcdaq packet to read
  int nchannels = 4;    // iValue(0..nchannels-1) are the ADC channels
};

/// Translates one rcdaq packet's ADC channels into edm4hep::RawCalorimeterHits.
/// Only the requested packet is instantiated (Event::getPacket(id)); its
/// decode() runs lazily on the first iValue() call. cellID is a placeholder
/// (packet id << 32 | channel) until a real channel map to DD4hep cell IDs
/// exists.
class RCDAQRawCalorimeterHit_factory
    : public JOmniFactory<RCDAQRawCalorimeterHit_factory, RCDAQRawCalorimeterHitConfig> {

private:
  Input<RCDAQEventHolder> m_in_event{this};

  PodioOutput<edm4hep::RawCalorimeterHit> m_out_hits{this};

  ParameterRef<int> m_packet_id{this, "packetId", config().packet_id, "rcdaq packet id to read"};
  ParameterRef<int> m_nchannels{this, "nChannels", config().nchannels,
                                "number of ADC channels (iValue indices) in the packet"};

public:
  void Configure() {}

  void Process(int32_t /* run_number */, uint64_t /* event_number */) {
    // the source inserts exactly one holder per event
    Event* evt = m_in_event().at(0)->evt;

    // getPacket() allocates; we own the Packet. A missing packet (e.g. in
    // begin/end-run events) just yields an empty collection.
    std::unique_ptr<Packet> p(evt->getPacket(config().packet_id));
    if (!p) {
      return;
    }

    for (int ch = 0; ch < config().nchannels; ch++) {
      auto hit = m_out_hits()->create();
      hit.setCellID((static_cast<std::uint64_t>(config().packet_id) << 32) | ch);
      hit.setAmplitude(p->iValue(ch));
      hit.setTimeStamp(0);
    }
  }
};

} // namespace eicrecon
