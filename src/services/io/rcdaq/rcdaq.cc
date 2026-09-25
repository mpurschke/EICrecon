#include <JANA/JApplicationFwd.h>
#include <JANA/JEventSourceGeneratorT.h>

#include "JEventSourceRCDAQ.h"

// Make this a JANA plugin. It only provides the rcdaq event source; what to
// do with the packets lives in user plugins (see mkrcdaqplugin.sh).
extern "C" {
void InitPlugin(JApplication* app) {
  InitJANAPlugin(app);
  app->Add(new JEventSourceGeneratorT<JEventSourceRCDAQ>());
}
}
