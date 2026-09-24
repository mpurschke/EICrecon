#include <JANA/JApplicationFwd.h>
#include <JANA/JEventSourceGeneratorT.h>

#include "JEventSourceRCDAQ.h"
#include "RCDAQRawCalorimeterHit_factory.h"
#include "extensions/jana/JOmniFactoryGeneratorT.h"

// Make this a JANA plugin
extern "C" {
void InitPlugin(JApplication* app) {
  InitJANAPlugin(app);
  app->Add(new JEventSourceGeneratorT<JEventSourceRCDAQ>());

  using namespace eicrecon;

  // rcdaq test stream (dpipe -sT): 1001/1002 carry channel n = value n
  // (20 x 32-bit, 64 x 16-bit), 1003 has 4 reproducible random ADC channels
  app->Add(new JOmniFactoryGeneratorT<RCDAQRawCalorimeterHit_factory>(
      "RCDAQTest1001Hits", {"RCDAQEvent"}, {"RCDAQTest1001Hits"}, {.packet_id = 1001, .nchannels = 20}, app));
  app->Add(new JOmniFactoryGeneratorT<RCDAQRawCalorimeterHit_factory>(
      "RCDAQTest1002Hits", {"RCDAQEvent"}, {"RCDAQTest1002Hits"}, {.packet_id = 1002, .nchannels = 64}, app));
  app->Add(new JOmniFactoryGeneratorT<RCDAQRawCalorimeterHit_factory>(
      "RCDAQTestRawHits", {"RCDAQEvent"}, {"RCDAQTestRawHits"}, {.packet_id = 1003, .nchannels = 4}, app));
}
}
