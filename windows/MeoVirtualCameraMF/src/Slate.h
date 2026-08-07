// Slate rendering for the Meo virtual camera.
//
// §8.4 states the rule this file exists to satisfy: the virtual camera is a
// separate process with its own lifetime, it appears in Zoom's device list
// whether or not the Meo host is running, and "a camera that returns no frames
// because the host is closed will hang or error inside the consuming app."
// So every non-live condition maps to a slate the camera can render **alone**,
// with no help from the host and no pixels handed to it.
//
// Consequences that shape the code below:
//
//   - No GDI, no Direct2D, no DirectWrite, no font loading, no file access, no
//     allocation. This runs inside the Windows frame server, and — if ADR 0002
//     says DirectShow is needed — inside the user's Zoom process (§9.2). It
//     writes bytes into a buffer it was handed and does nothing else.
//
//   - Text is drawn from a bitmap font compiled into the binary. §15 requires
//     user-facing errors to be actionable, and a camera showing
//     "MEO IS NOT RUNNING" is the difference between a user who knows what to
//     do and a user filing a bug against Zoom.
//
//   - Rendering is deterministic given (status, geometry, tick), which is what
//     makes it testable off-Windows.

#pragma once

#include "meo/FrameBridge.h"

#include <cstdint>

namespace meo {

// The message a given status shows. Never null; unknown statuses fall back to
// a generic but still honest string.
const char* SlateMessage(ReadStatus status);

// The second, smaller line — what the user should actually do about it.
// Returns nullptr when the headline says everything.
const char* SlateHint(ReadStatus status);

// Renders a full NV12 slate for `status`.
//
// `dest` must hold at least `stride * height * 3 / 2` bytes; `width` and
// `height` must be even and `stride >= width`. Out-of-range geometry is
// ignored rather than clamped-and-drawn, because a half-drawn slate is worse
// than the caller noticing it passed nonsense.
//
// `tick` drives the one animated element — a sweep used only for states that
// are genuinely transient. A paused or stopped slate is deliberately still:
// motion on those would suggest the camera is doing something it is not.
//
// Returns false if the geometry was rejected, in which case `dest` is
// untouched.
bool RenderSlate(ReadStatus status, uint8_t* dest, uint32_t width,
                 uint32_t height, uint32_t stride, uint64_t tick);

}  // namespace meo
