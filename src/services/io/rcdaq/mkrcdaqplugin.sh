#!/bin/bash
#
# mkrcdaqplugin.sh - create a user plugin project for rcdaq data in EICrecon
# (the equivalent of pmonitor's writePmonproject.pl)
#
#   mkrcdaqplugin.sh <name> [parent directory]
#
# creates <parent directory>/<name>/ (default: ./<name>) with
#
#   <name>.cc            InitPlugin() - registers factory and processor (~ pinit())
#   <name>_factory.h     packet -> edm4hep::RawCalorimeterHits      (~ process_event())
#   <name>_processor.h   hits -> histograms, written to a ROOT file
#   CMakeLists.txt       builds <name>.so against the installed EICrecon
#   build.sh             build it
#   run.sh               run an rcdaq file through it
#
# The project lives outside the EICrecon source tree and never modifies it.
# build.sh and run.sh start the EIC container themselves when they are not
# already running inside it.
#
# The locations below can be overridden from the environment.

RCDAQ_SRC_DIR=${RCDAQ_SRC_DIR:-$(cd "$(dirname "$0")" && pwd)}
RCDAQ_PLUGIN_DIR=${RCDAQ_PLUGIN_DIR:-/home/purschke/Claude/build-eic/EICrecon/src/services/io/rcdaq}
EVENTLIB_PREFIX=${EVENTLIB_PREFIX:-/home/purschke/Claude/install-eic}
EIC_IMAGE=${EIC_IMAGE:-eicweb/eic_xl:nightly}

NAME=$1
PARENT=${2:-.}

if [ -z "$NAME" ]; then
  sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi
if ! [[ "$NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "name must be a valid C++ identifier (letters, digits, _; not starting with a digit)"
  exit 1
fi

DIR="$PARENT/$NAME"
if [ -e "$DIR" ]; then
  echo "$DIR already exists - not touching it"
  exit 1
fi
mkdir -p "$DIR" || exit 1

# write stdin to a file, filling in the placeholders
emit()
{
  sed -e "s|@NAME@|$NAME|g" \
      -e "s|@RCDAQ_SRC_DIR@|$RCDAQ_SRC_DIR|g" \
      -e "s|@RCDAQ_PLUGIN_DIR@|$RCDAQ_PLUGIN_DIR|g" \
      -e "s|@EVENTLIB_PREFIX@|$EVENTLIB_PREFIX|g" \
      -e "s|@EIC_IMAGE@|$EIC_IMAGE|g" > "$DIR/$1"
}

# ---------------------------------------------------------------------------
emit CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.24)
project(@NAME@ CXX)

set(CMAKE_CXX_STANDARD 20)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

# where RCDAQEventHolder.h lives (the rcdaq plugin sources in EICrecon)
set(RCDAQ_SRC_DIR "@RCDAQ_SRC_DIR@" CACHE PATH "rcdaq plugin source directory")

find_package(EICrecon REQUIRED)
find_package(JANA REQUIRED)
find_package(podio REQUIRED)
find_package(EDM4HEP REQUIRED)
find_package(ROOT REQUIRED COMPONENTS Hist RIO)

# online_distribution eventlibraries
find_library(NOROOTEVENT_LIBRARY NoRootEvent REQUIRED)
find_path(NOROOTEVENT_INCLUDE_DIR Event/Event.h REQUIRED)

add_library(@NAME@ SHARED @NAME@.cc)
set_target_properties(@NAME@ PROPERTIES PREFIX "" SUFFIX ".so")   # JANA looks for @NAME@.so

target_include_directories(@NAME@ PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR} ${RCDAQ_SRC_DIR} ${NOROOTEVENT_INCLUDE_DIR})

target_link_libraries(@NAME@ PRIVATE
  EICrecon::log_library JANA::jana2_shared_lib EDM4HEP::edm4hep podio::podio
  ROOT::Hist ROOT::RIO ${NOROOTEVENT_LIBRARY})
EOF

# ---------------------------------------------------------------------------
# common head of build.sh and run.sh: re-run inside the container if needed
CONTAINER_PREAMBLE='HERE=$(cd "$(dirname "$0")" && pwd)

# not inside the EIC container (no jana)? then start it and run this script there
if ! command -v jana > /dev/null
then
  MOUNTS=(-v "$HOME:$HOME")
  [ -d /data ] && MOUNTS+=(-v /data:/data:ro)
  exec docker run --rm -u "$(id -u):$(id -g)" "${MOUNTS[@]}" -e EXTRA_PLUGINS -w "$HERE" \
       @EIC_IMAGE@ "$HERE/$(basename "$0")" "$@"
fi

export LD_LIBRARY_PATH=@EVENTLIB_PREFIX@/lib:$LD_LIBRARY_PATH
cd "$HERE"'

emit build.sh <<EOF
#!/bin/bash
# build @NAME@.so (in ./build)

$CONTAINER_PREAMBLE

cmake -S . -B build -DCMAKE_PREFIX_PATH=@EVENTLIB_PREFIX@ || exit 1
cmake --build build -j8
EOF

emit run.sh <<EOF
#!/bin/bash
# run an rcdaq file through @NAME@
#
#   ./run.sh <file.evt> [nevents] [more jana -P options...]
#
# nevents 0 (default) means all events. To also write the hits to a PODIO
# file, add the podio plugin and name the collections:
#
#   EXTRA_PLUGINS=podio ./run.sh file.evt 100 \\
#       -Ppodio:output_file=hits.root -Ppodio:output_collections=@NAME@Hits

$CONTAINER_PREAMBLE

FILE=\$1
NEVENTS=\${2:-0}
if [ -z "\$FILE" ]
then
  sed -n '2,11p' "\$0" | sed 's/^# \\{0,1\\}//'
  exit 1
fi
shift; shift

PLUGINS=log,rcdaq,@NAME@
[ -n "\$EXTRA_PLUGINS" ] && PLUGINS=\$PLUGINS,\$EXTRA_PLUGINS

jana -Pplugins=\$PLUGINS \\
     -Pjana:plugin_path=@RCDAQ_PLUGIN_DIR@:\$HERE/build \\
     -Pjana:nevents=\$NEVENTS \\
     "\$@" "\$FILE"
EOF
chmod +x "$DIR/build.sh" "$DIR/run.sh"

# ---------------------------------------------------------------------------
emit "${NAME}.cc" <<'EOF'
// @NAME@ - rcdaq user plugin
//
// InitPlugin() is the equivalent of pmonitor's pinit(): JANA calls it once
// when it loads @NAME@.so. It registers
//   - the factory   (packet -> hits, see @NAME@_factory.h)
//   - the processor (hits -> histograms, see @NAME@_processor.h)

#include <JANA/JApplication.h>
#include <extensions/jana/JOmniFactoryGeneratorT.h>

#include "@NAME@_factory.h"
#include "@NAME@_processor.h"

extern "C"
{
  void InitPlugin(JApplication* app)
  {
    InitJANAPlugin(app);

    // one factory instance per packet. Arguments: instance name, input
    // (the rcdaq event), output collection name, configuration.
    // Parameters of this instance: -P@NAME@:@NAME@Hits:packetId=... etc.
    app->Add(new JOmniFactoryGeneratorT<@NAME@_factory>(
        "@NAME@Hits", {"RCDAQEvent"}, {"@NAME@Hits"}, {.packet_id = 1003}, app));

    // histograms of the hits in collection "@NAME@Hits"
    app->Add(new @NAME@_processor("@NAME@Hits"));
  }
}
EOF

# ---------------------------------------------------------------------------
emit "${NAME}_factory.h" <<'EOF'
#pragma once

#include <edm4hep/RawCalorimeterHitCollection.h>
#include <extensions/jana/JOmniFactory.h>

#include <Event/Event.h>
#include <Event/packet.h>

#include <cstdint>
#include <memory>

#include "RCDAQEventHolder.h"

struct @NAME@Config
{
  int packet_id = 1003;   // rcdaq packet to read
  int nchannels = 0;      // <= 0: ask the packet, iValue(0,"CHANNELS")
};

/// packet -> edm4hep::RawCalorimeterHits, one hit per channel.
/// Process() is the equivalent of pmonitor's process_event(); the part
/// marked USER CODE decides what the "hit" value of a channel is.
class @NAME@_factory : public JOmniFactory<@NAME@_factory, @NAME@Config>
{
private:
  Input<RCDAQEventHolder> m_in_event{this};
  PodioOutput<edm4hep::RawCalorimeterHit> m_out_hits{this};

  // each ParameterRef makes a config field settable on the command line,
  // -P@NAME@:<instance name>:<parameter>=<value>
  ParameterRef<int> m_packet_id{this, "packetId", config().packet_id, "rcdaq packet id to read"};
  ParameterRef<int> m_nchannels{this, "nChannels", config().nchannels,
                                "number of channels; <= 0: ask the packet"};

public:
  void Configure() {}

  void Process(int32_t /* run_number */, uint64_t /* event_number */)
  {
    Event* evt = m_in_event().at(0)->evt;

    // we own the Packet; the unique_ptr deletes it before Process() returns
    std::unique_ptr<Packet> p(evt->getPacket(config().packet_id));
    if (!p)
      {
        return;   // packet not in this event (e.g. begin-run) -> no hits
      }

    const int nchannels = config().nchannels > 0 ? config().nchannels : p->iValue(0, "CHANNELS");
    for (int ch = 0; ch < nchannels; ch++)
      {
        // ------------------ USER CODE: this channel's value ------------------
        const int amplitude = p->iValue(ch);
        // ----------------------------------------------------------------------

        auto hit = m_out_hits()->create();
        // placeholder cellID: packet id in the upper, channel in the lower 32 bits
        hit.setCellID((static_cast<std::uint64_t>(config().packet_id) << 32) | ch);
        hit.setAmplitude(amplitude);
        hit.setTimeStamp(0);
      }
  }
};
EOF

# ---------------------------------------------------------------------------
emit "${NAME}_processor.h" <<'EOF'
#pragma once

#include <JANA/JApplication.h>
#include <JANA/JEvent.h>
#include <JANA/JEventProcessor.h>
#include <edm4hep/RawCalorimeterHitCollection.h>

#include <TFile.h>
#include <TH1F.h>
#include <TString.h>

#include <memory>
#include <string>
#include <vector>

/// hits -> per-channel histograms of the hit amplitude.
///   Init()              books the histograms (runs once, before the first event)
///   ProcessSequential() fills them, one event at a time
///   Finish()            writes them to @NAME@:output_file
class @NAME@_processor : public JEventProcessor
{
public:
  explicit @NAME@_processor(std::string collection)
    : m_collection(std::move(collection))
  {
    SetTypeName(NAME_OF_THIS);
    SetCallbackStyle(CallbackStyle::ExpertMode);
  }

  void Init() override
  {
    auto* app = GetApplication();
    app->SetDefaultParameter("@NAME@:output_file", m_output_file, "ROOT file for the histograms");
    app->SetDefaultParameter("@NAME@:nchannels", m_nchannels, "number of channel histograms to book");
    app->SetDefaultParameter("@NAME@:nbins", m_nbins, "bins per histogram");
    app->SetDefaultParameter("@NAME@:xmin", m_xmin, "lower edge; xmin >= xmax: ROOT picks the range");
    app->SetDefaultParameter("@NAME@:xmax", m_xmax, "upper edge");

    for (int ch = 0; ch < m_nchannels; ch++)
      {
        auto h = std::make_unique<TH1F>(Form("h_%02d", ch), Form("%s channel %d", m_collection.c_str(), ch),
                                        m_nbins, m_xmin, m_xmax);
        h->SetDirectory(nullptr);   // we own it, not ROOT's current directory
        m_hists.push_back(std::move(h));
      }
  }

  void ProcessSequential(const JEvent& event) override
  {
    const auto* hits = event.GetCollection<edm4hep::RawCalorimeterHit>(m_collection);
    for (const auto& hit : *hits)
      {
        const int ch = hit.getCellID() & 0xffffffff;   // placeholder cellID, see the factory
        if (ch < static_cast<int>(m_hists.size()))
          {
            m_hists[ch]->Fill(hit.getAmplitude());
          }
      }
  }

  void Finish() override
  {
    TFile f(m_output_file.c_str(), "RECREATE");
    for (auto& h : m_hists)
      {
        h->Write();
      }
    f.Close();
  }

private:
  std::string m_collection;
  std::string m_output_file = "@NAME@.root";
  int m_nchannels = 32;
  int m_nbins     = 128;
  double m_xmin   = 0;
  double m_xmax   = 0;   // xmin >= xmax: automatic range

  std::vector<std::unique_ptr<TH1F>> m_hists;
};
EOF

# ---------------------------------------------------------------------------
emit README <<'EOF'
@NAME@ - rcdaq user plugin for EICrecon/JANA

  ./build.sh                      build @NAME@.so
  ./run.sh <file.evt> [nevents]   run a file; histograms go to @NAME@.root

Files:
  @NAME@.cc            InitPlugin(): which packets, which collection names
  @NAME@_factory.h     packet -> hits    (the USER CODE part)
  @NAME@_processor.h   hits -> histograms

Any parameter can be set on the run.sh command line, e.g.
  ./run.sh file.evt 100 -P@NAME@:@NAME@Hits:packetId=2071 -P@NAME@:xmax=50000
EOF

echo "created $DIR - next: cd $DIR && ./build.sh"
