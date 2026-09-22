// Copyright 2026, Martin L. Purschke
// Subject to the terms in the LICENSE file found in the top-level directory.

#pragma once

#include <Event/Event.h>

/// Owns the rcdaq Event* for the lifetime of the JEvent it was Insert()'d
/// into. JEventSourceRCDAQ::Emit() is the "requestor" that called
/// Eventiterator::getNextEvent() and is therefore responsible for deleting
/// what it got back (the rcdaq eventlibraries convention); this holder is
/// just where that responsibility ends up living once JANA2 takes over the
/// JEvent's lifetime.
struct RCDAQEventHolder {
  explicit RCDAQEventHolder(Event* event) : evt(event) {}
  ~RCDAQEventHolder() { delete evt; }

  RCDAQEventHolder(const RCDAQEventHolder&)            = delete;
  RCDAQEventHolder& operator=(const RCDAQEventHolder&) = delete;

  Event* evt;
};
