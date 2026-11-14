## rcdaq JEventSource Overview

This plugin reads data files written by [RCDAQ](https://www.phenix.bnl.gov/~purschke/rcdaq/),
the data acquisition system used at ePIC test beams and test stands, into
EICrecon/JANA2: files in the RCDAQ format (usually `.evt`), including
compressed files. The legacy PHENIX format (PRDF, `.prdf`) is no longer
supported by the event libraries.

The raw data are not converted into a new data model. The plugin uses RCDAQ's
own event libraries (`Event`/`Packet` from
[online_distribution](https://github.com/sPHENIX-Collaboration/online_distribution)),
so every detector format that RCDAQ already decodes - digitizers such as the
CAEN V1742, DRS4, H2GCROC3 or CALOROC - can be read without writing a new
decoder. Detector-specific code (which packets to read, how to turn waveforms
into hits) lives in small user plugins that produce ordinary EDM4hep
collections, so everything downstream of them works as it does for simulated
data.

The plugin is meant for offline analysis of RCDAQ files; it does not read
from a running RCDAQ.

### Requirements

The rcdaq event libraries (`libNoRootEvent` and the headers under `Event/`)
from the `ePIC` branch of online_distribution. They are found through
`$ONLINE_MAIN` (their usual installation prefix) or `CMAKE_PREFIX_PATH`. If
they are not found, the plugin is skipped when EICrecon is configured:

~~~
-- rcdaq eventlibraries (libNoRootEvent) not found. Skipping rcdaq plugin...
~~~

To build and install the event libraries yourself, for example inside
`eic-shell` into its personal install area:

~~~
export ONLINE_MAIN=$EIC_SHELL_PREFIX
git clone -b ePIC https://github.com/sPHENIX-Collaboration/online_distribution.git
cmake -S online_distribution/eventlibraries -B build-eventlibraries -DCMAKE_INSTALL_PREFIX=$ONLINE_MAIN
cmake --build build-eventlibraries -j8
cmake --install build-eventlibraries
~~~

### Running

Load the plugin, plus a user plugin that does something with the data (see
below; `-Pjana:plugin_path` points to where `MyPlugin.so` was built), and give
the file on the command line:

~~~
jana -Pplugins=log,rcdaq,MyPlugin -Pjana:plugin_path=MyPlugin/build file.evt
~~~

or with `eicrecon`, which also loads the geometry. Name the output
collections; otherwise `eicrecon` asks for its default (simulation) collections:

~~~
eicrecon -Pplugins=rcdaq,MyPlugin -Pjana:plugin_path=MyPlugin/build \
         -Ppodio:output_file=out.root \
         -Ppodio:output_collections=EventHeader,MyPluginHits file.evt
~~~

Files ending in `.evt` are recognized automatically. For other
names, select the source explicitly with `-Pevent_source_type=JEventSourceRCDAQ`.

### What the source provides

For each event, the source inserts into the `JEvent`:

| name          | type                    | content |
|---------------|-------------------------|---------|
| `EventHeader` | `edm4hep::EventHeader`  | run number, event number, and the event's time (Unix time) in `timeStamp` |
| `RCDAQEvent`  | `RCDAQEventHolder`      | the rcdaq `Event`, from which factories get their packets |

The run and event numbers of the `JEvent` are set as well.

The `Event` is owned by the holder and deleted by JANA2 when the `JEvent` is
recycled. A factory gets packets from it with `getPacket(id)` and owns those
`Packet`s: it must delete them before its `Process()` returns (a
`std::unique_ptr` does this) and must not keep pointers to them. Packets are
decoded only when their data are first accessed, so asking for one packet
does not decode the others.

### Writing a user plugin

`mkrcdaqplugin.sh` (installed into `bin/`) creates a project for a user
plugin outside the EICrecon source tree, similar to pmonitor's
`writePmonProject.sh`:

~~~
mkrcdaqplugin.sh MyPlugin
cd MyPlugin
bash build.sh
bash run.sh file.evt [nevents] [-P options...]
~~~

It contains:

- `MyPlugin.cc` - `InitPlugin()`, which registers the factory and the processor
- `MyPlugin_factory.h` - packets to `edm4hep` hits; the detector-specific part
- `MyPlugin_processor.h` - histograms of the hits, written to `MyPlugin.root`
- `CMakeLists.txt`, `build.sh`, `run.sh`, `README`

A new project does nothing until code is added. The tutorial in it (the same
as in the pmonitor manual) is enabled by un-commenting the marked lines, and
runs on a file of RCDAQ's built-in test stream:

~~~
dpipe -sT -df -o -n 1000 none test.evt
~~~

The project finds the rcdaq plugin through `$EIC_MAIN` (default:
`$EIC_SHELL_PREFIX`, the personal install area of `eic-shell`) and the
event libraries through `$ONLINE_MAIN` (default: `$EIC_MAIN`). When
`build.sh` and `run.sh` are started outside the EIC container, they start
it themselves with Docker (image `eicweb/eic_xl:nightly`, or `$EIC_IMAGE`).

Factory parameters can be set on the command line, as usual in EICrecon,
e.g. `-PMyPlugin:MyPluginHits:packetId=1003`.

### Current limitations

- Files only; live data from a running RCDAQ are not supported.
- Files are recognized by their name (`.evt`), not by their content.
- There is no channel map to DD4hep cell IDs yet. The generated user plugin
  uses a placeholder `cellID` (packet id in the upper, channel in the lower
  32 bits), which has to be replaced by the detector's readout cell ID.
- Reading and decompressing the file happens in the source, which JANA2 runs
  on one thread at a time; only very light analyses on many threads will
  notice.

### More information

- RCDAQ home page (manuals, example data files):
  https://www.phenix.bnl.gov/~purschke/rcdaq/
- online_distribution, branch `ePIC`:
  https://github.com/sPHENIX-Collaboration/online_distribution
