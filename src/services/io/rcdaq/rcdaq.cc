// Copyright 2026, Martin L. Purschke
// Subject to the terms in the LICENSE file found in the top-level directory.

#include <JANA/JApplicationFwd.h>
#include <JANA/JEventSourceGeneratorT.h>

#include "JEventSourceRCDAQ.h"

// Make this a JANA plugin
extern "C" {
void InitPlugin(JApplication* app) {
  InitJANAPlugin(app);
  app->Add(new JEventSourceGeneratorT<JEventSourceRCDAQ>());
}
}
