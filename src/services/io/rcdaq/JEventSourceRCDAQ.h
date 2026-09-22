// Copyright 2026, Martin L. Purschke
// Subject to the terms in the LICENSE file found in the top-level directory.

#pragma once

#include <JANA/JApplicationFwd.h>
#include <JANA/JEventSource.h>
#include <JANA/JEventSourceGeneratorT.h>
#include <memory>
#include <string>

class Eventiterator;

/// Reads rcdaq event files (.evt/.prdf) via the online_distribution
/// eventlibraries Eventiterator API (file replay only for now - see
/// Open()). Emit() wraps each Event* in an RCDAQEventHolder and inserts
/// that into the JEvent; per-detector JFactory<Packet> implementations
/// pull the Event* back out and extract the packets they want from it.
class JEventSourceRCDAQ : public JEventSource {

public:
  JEventSourceRCDAQ(std::string resource_name, JApplication* app);

  virtual ~JEventSourceRCDAQ();

  void Open() override;

  void Close() override;

  Result Emit(JEvent& event) override;

  static std::string GetDescription();

private:
  std::unique_ptr<Eventiterator> m_iterator;
};

template <> double JEventSourceGeneratorT<JEventSourceRCDAQ>::CheckOpenable(std::string);
