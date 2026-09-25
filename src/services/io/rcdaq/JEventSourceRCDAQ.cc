// JEventSource that reads rcdaq event files through the online_distribution
// eventlibraries Event/Eventiterator/Packet API.

#include "JEventSourceRCDAQ.h"

#include "RCDAQEventHolder.h"

#include <JANA/JApplication.h>
#include <JANA/JEvent.h>
#include <JANA/JException.h>

#include <edm4hep/EventHeaderCollection.h>
#include <podio/Frame.h>

#include <Event/Event.h>
#include <Event/Eventiterator.h>
#include <Event/fileEventiterator.h>

#include <format>

//------------------------------------------------------------------------------
// Constructor
//------------------------------------------------------------------------------
JEventSourceRCDAQ::JEventSourceRCDAQ(std::string resource_name, JApplication* app)
    : JEventSource(resource_name, app) {
  SetTypeName(NAME_OF_THIS);                   // Provide JANA with class name
  SetCallbackStyle(CallbackStyle::ExpertMode); // Use new, exception-free Emit() callback
}

//------------------------------------------------------------------------------
// Destructor
//------------------------------------------------------------------------------
JEventSourceRCDAQ::~JEventSourceRCDAQ() = default;

//------------------------------------------------------------------------------
// Open
//------------------------------------------------------------------------------
void JEventSourceRCDAQ::Open() {

  int status = 0;
  m_iterator = std::make_unique<fileEventiterator>(GetResourceName().c_str(), status);
  if (status != 0) {
    throw JException(std::format("Unable to open rcdaq file \"{}\"", GetResourceName()));
  }
}

//------------------------------------------------------------------------------
// Close
//------------------------------------------------------------------------------
void JEventSourceRCDAQ::Close() { m_iterator.reset(); }

//------------------------------------------------------------------------------
// Emit
//------------------------------------------------------------------------------
JEventSourceRCDAQ::Result JEventSourceRCDAQ::Emit(JEvent& event) {

  /// Calls to Emit are synchronized with each other, which means they can
  /// read and write state on the JEventSource without causing race conditions.

  Event* evt = m_iterator->getNextEvent();
  if (evt == nullptr) {
    return Result::FailureFinished;
  }

  // The Event object returned by getNextEvent() is freshly allocated, but
  // is pointer-based into the iterator's internal buffer, which gets
  // overwritten the next time the iterator reads a block. convert() copies
  // the data out so it (and the packets decoded from it) stays valid for as
  // long as JANA2 keeps this JEvent - and the RCDAQEventHolder we're about
  // to Insert() - alive.
  evt->convert();

  event.SetEventNumber(evt->getEvtSequence());
  event.SetRunNumber(evt->getRunNumber());

  // the standard EDM4hep event header, as EICrecon's PODIO source provides
  // it: run and event number, and the event's Unix time in timeStamp
  edm4hep::EventHeaderCollection headers;
  auto header = headers.create();
  header.setEventNumber(evt->getEvtSequence());
  header.setRunNumber(evt->getRunNumber());
  header.setTimeStamp(evt->getTime());
  header.setWeight(1.0);

  // a fresh podio::Frame per event holds the collection, and the JEvent
  // takes ownership of the frame - the same pattern as EICrecon's PODIO
  // source (letting InsertCollection() create the frame left the previous
  // event's frame in recycled JEvents unless the podio plugin was loaded)
  auto frame                = std::make_unique<podio::Frame>();
  const auto& header_coll   = frame->put(std::move(headers), "EventHeader");
  event.InsertCollectionAlreadyInFrame<edm4hep::EventHeader>(&header_coll, "EventHeader");
  event.Insert(frame.release());

  // RCDAQEventHolder takes ownership of evt from here on; JANA2 deletes the
  // holder (and thus evt) once every factory/processor is done with this
  // JEvent.
  event.Insert(new RCDAQEventHolder(evt), "RCDAQEvent");

  return Result::Success;
}

//------------------------------------------------------------------------------
// GetDescription
//------------------------------------------------------------------------------
std::string JEventSourceRCDAQ::GetDescription() { return "rcdaq event file (.evt/.prdf)"; }

//------------------------------------------------------------------------------
// CheckOpenable
//------------------------------------------------------------------------------
template <>
double JEventSourceGeneratorT<JEventSourceRCDAQ>::CheckOpenable(std::string resource_name) {

  if (resource_name.ends_with(".evt") || resource_name.ends_with(".prdf")) {
    return 0.02;
  }
  return 0.0;
}
