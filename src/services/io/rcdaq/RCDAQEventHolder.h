#pragma once

#include <Event/Event.h>

/// Owns the rcdaq Event* for the lifetime of the JEvent it was Insert()'d
/// into. JEventSourceRCDAQ::Emit() got the Event from
/// Eventiterator::getNextEvent() and, by the eventlibraries convention, has
/// to delete it; this holder takes over that job once JANA2 manages the
/// JEvent's lifetime.
struct RCDAQEventHolder {
  explicit RCDAQEventHolder(Event* event) : evt(event) {}
  ~RCDAQEventHolder() { delete evt; }

  RCDAQEventHolder(const RCDAQEventHolder&)            = delete;
  RCDAQEventHolder& operator=(const RCDAQEventHolder&) = delete;

  Event* evt;
};
