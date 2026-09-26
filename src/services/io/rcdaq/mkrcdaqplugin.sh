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
# The project finds everything through two environment variables:
#   EIC_MAIN     where the rcdaq plugin is installed, laid out like EICrecon's
#                own installation: lib/EICrecon/plugins/rcdaq.so,
#                include/EICrecon/services/io/rcdaq/
#   ONLINE_MAIN  the online_distribution eventlibraries (defaults to EIC_MAIN
#                inside the container)
# The container image can be overridden with EIC_IMAGE.

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

# the rcdaq plugin's headers are installed like EICrecon's own, under
# $EIC_MAIN/include/EICrecon (#include "services/io/rcdaq/RCDAQEventHolder.h")
if(NOT DEFINED ENV{EIC_MAIN})
  message(FATAL_ERROR "EIC_MAIN is not set - it should point to the rcdaq plugin installation")
endif()

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
  ${CMAKE_CURRENT_SOURCE_DIR} $ENV{EIC_MAIN}/include/EICrecon ${NOROOTEVENT_INCLUDE_DIR})

target_link_libraries(@NAME@ PRIVATE
  EICrecon::log_library JANA::jana2_shared_lib EDM4HEP::edm4hep podio::podio
  ROOT::Hist ROOT::RIO ${NOROOTEVENT_LIBRARY})
EOF

# ---------------------------------------------------------------------------
# common head of build.sh and run.sh: re-run inside the container if needed
CONTAINER_PREAMBLE='HERE=$(cd "$(dirname "$0")" && pwd)

if [ -z "$EIC_MAIN" ]
then
  echo "EIC_MAIN is not set - it should point to the rcdaq plugin installation"
  exit 1
fi

# not inside the EIC container (no jana)? then start it and run this script there
if ! command -v jana > /dev/null
then
  MOUNTS=(-v "$HOME:$HOME")
  [ -d /data ] && MOUNTS+=(-v /data:/data:ro)
  exec docker run --rm -u "$(id -u):$(id -g)" "${MOUNTS[@]}" -e EIC_MAIN -e EXTRA_PLUGINS -w "$HERE" \
       @EIC_IMAGE@ bash "$HERE/$(basename "$0")" "$@"
fi

# the eventlibraries: inside the container, where they live with the plugin
ONLINE_MAIN=${ONLINE_MAIN:-$EIC_MAIN}
export LD_LIBRARY_PATH=$ONLINE_MAIN/lib:$LD_LIBRARY_PATH
cd "$HERE"'

emit build.sh <<EOF
#!/bin/bash
# build @NAME@.so (in ./build)

$CONTAINER_PREAMBLE

cmake -S . -B build -DCMAKE_PREFIX_PATH="\$ONLINE_MAIN;\$EIC_MAIN" || exit 1
cmake --build build -j8
EOF

emit run.sh <<EOF
#!/bin/bash
# run an rcdaq file through @NAME@
#
#   bash run.sh <file.evt> [nevents] [more jana -P options...]
#
# nevents 0 (default) means all events. To also write the hits to a PODIO
# file, add the podio plugin and name the collections:
#
#   EXTRA_PLUGINS=podio bash run.sh file.evt 100 \\
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
     -Pjana:plugin_path=\$EIC_MAIN/lib/EICrecon/plugins:\$HERE/build \\
     -Pjana:nevents=\$NEVENTS \\
     "\$@" "\$FILE"
EOF

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

    // the factory. Arguments: instance name, input (the rcdaq event), output
    // collection name, configuration. Here: packet 1003 of the rcdaq test
    // stream, which has 4 channels (it does not report "CHANNELS" itself).
    // Parameters of an instance can be changed on the command line,
    // -P@NAME@:<instance name>:<parameter>=..., e.g. -P@NAME@:@NAME@Hits:packetId=1003
    app->Add(new JOmniFactoryGeneratorT<@NAME@_factory>(
        "@NAME@Hits", {"RCDAQEvent"}, {"@NAME@Hits"}, {.packet_id = 1003, .nchannels = 4}, app));

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

#include "services/io/rcdaq/RCDAQEventHolder.h"

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

// Tutorial - the same as in the pmonitor manual, with packet 1003 of the
// rcdaq test stream: un-comment the three lines marked "tutorial" (the
// declaration of h1, its creation in Init(), and the Fill in
// ProcessSequential()), then "bash build.sh" and "bash run.sh <file>".
// h1 ends up in @NAME@.root. A test stream file: dpipe -sT -df -o -n 1000 none test.evt

#include <JANA/JApplication.h>
#include <JANA/JEvent.h>
#include <JANA/JEventProcessor.h>
#include <edm4hep/RawCalorimeterHitCollection.h>

#include <TFile.h>
#include <TH1.h>
#include <TH2.h>

#include <string>

/// hits -> histograms.
///   Init()              opens the output file and creates the histograms (~ pinit())
///   ProcessSequential() fills them, one event at a time
///   Finish()            writes them to the file
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
    GetApplication()->SetDefaultParameter("@NAME@:output_file", m_output_file,
                                          "ROOT file for the histograms");

    // histograms created after this line end up in this file
    m_file = new TFile(m_output_file.c_str(), "RECREATE");

    // h1 = new TH1F ( "h1","test histogram", 400, -50, 50);    // tutorial
  }

  void ProcessSequential(const JEvent& event) override
  {
    const auto* hits = event.GetCollection<edm4hep::RawCalorimeterHit>(m_collection);
    for (const auto& hit : *hits)
      {
        [[maybe_unused]] const int ch = hit.getCellID() & 0xffffffff;   // placeholder cellID, see the factory

        // if ( ch == 3 ) h1->Fill ( hit.getAmplitude()/1000. );    // tutorial
      }
  }

  void Finish() override
  {
    m_file->Write();
    m_file->Close();
    delete m_file;
  }

private:
  std::string m_collection;
  std::string m_output_file = "@NAME@.root";
  TFile* m_file = nullptr;

  // TH1F *h1;    // tutorial
};
EOF

# ---------------------------------------------------------------------------
emit README <<'EOF'
@NAME@ - rcdaq user plugin for EICrecon/JANA

  bash build.sh                      build @NAME@.so
  bash run.sh <file.evt> [nevents]   run a file; histograms go to @NAME@.root

Files:
  @NAME@.cc            InitPlugin(): which packets, which collection names
  @NAME@_factory.h     packet -> hits    (the USER CODE part)
  @NAME@_processor.h   hits -> histograms

Tutorial (as in the pmonitor manual): un-comment the three lines marked
"tutorial" in @NAME@_processor.h, rebuild, and run a test stream file:

  dpipe -sT -df -o -n 1000 none test.evt
  bash build.sh
  bash run.sh test.evt

Example data files: https://www.phenix.bnl.gov/~purschke/rcdaq/

Any parameter can be set on the run.sh command line, e.g.
  bash run.sh file.evt 100 -P@NAME@:@NAME@Hits:packetId=1003 -P@NAME@:output_file=other.root
EOF

echo "created $DIR - next: cd $DIR && bash build.sh"
