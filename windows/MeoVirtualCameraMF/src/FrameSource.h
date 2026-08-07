// The decision layer between the frame bridge and a virtual-camera backend.
//
// Both Windows backends — the Media Foundation source, and the DirectShow
// filter if ADR 0002 says one is needed — face the same question every time
// the consumer asks for a frame: is there a live frame to hand over, or should
// this be a slate? Answering it identically in two places is how the two
// backends drift apart, so it is answered once, here.
//
// §9.2's discipline applies in full, because this runs inside the frame server
// and possibly inside the user's Zoom process:
//
//   - No allocation after construction. The staging buffer is sized once, for
//     the largest advertised format.
//   - No blocking, no waiting on the host, no unbounded loops.
//   - No exceptions. Every failure is a return value that becomes a slate.
//
// It is deliberately free of COM and of Media Foundation types so it can be
// tested off-Windows, which is where its logic actually gets exercised.

#pragma once

#include "Slate.h"
#include "meo/FrameBridge.h"

#include <cstdint>
#include <vector>

namespace meo {

// Counters for the §15 health panel. Cheap to read, never reset by the source
// itself.
struct FrameSourceStats {
  uint64_t frames_delivered = 0;
  uint64_t slates_drawn = 0;
  uint64_t format_mismatches = 0;
  uint64_t torn_reads = 0;
  uint64_t last_frame_id = 0;
  uint64_t last_age_ms = 0;
  ReadStatus last_status = ReadStatus::kNotAttached;
};

class CameraFrameSource {
 public:
  CameraFrameSource();
  ~CameraFrameSource();

  CameraFrameSource(const CameraFrameSource&) = delete;
  CameraFrameSource& operator=(const CameraFrameSource&) = delete;

  // Sets the format this camera advertises to its consumer. §5.4 forbids
  // renegotiating a virtual camera's media type mid-call — "the most reliable
  // way to break Zoom" — so this is fixed for the life of a stream and the
  // source refuses to emit anything else.
  void SetOutputFormat(uint32_t width, uint32_t height);

  // Fills one NV12 frame. Always succeeds in producing *something*: if there
  // is no host, no phone, or no valid frame, it draws the matching slate.
  // That is §8.4's requirement — a camera that returns no frames hangs the
  // application consuming it.
  //
  // `stride` is the destination stride, which the consumer chooses and which
  // frequently exceeds the width.
  //
  // Returns the status that produced this frame, for logging. A return of
  // kLive means real phone pixels were written; anything else means a slate.
  ReadStatus FillFrame(uint8_t* dest, uint32_t stride, uint64_t tick);

  const FrameSourceStats& stats() const { return stats_; }

  // Exposed for tests, so a test can drive a specific bridge instead of the
  // machine-wide default one.
  void SetBridgeNameForTesting(const char* name) { bridge_name_ = name; }

 private:
  // Tries to attach to the bridge, at most once per kReattachIntervalMs.
  // The camera routinely outlives every host process, so "not attached" is an
  // ordinary steady state rather than an error to retry aggressively.
  void MaybeAttach(uint64_t now_ms);

  FrameBridgeReader reader_;
  const char* bridge_name_ = nullptr;
  uint64_t last_attach_attempt_ms_ = 0;
  bool attach_attempted_ = false;

  uint32_t out_width_ = 1280;
  uint32_t out_height_ = 720;

  // Allocated once, at construction, for the largest format the plan
  // advertises. Sizing it per-format would mean reallocating on a format
  // change, inside a callback that must not allocate.
  std::vector<uint8_t> staging_;

  FrameSourceStats stats_;
};

}  // namespace meo
