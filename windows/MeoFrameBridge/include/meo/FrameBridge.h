// The Meo Camera frame bridge — the shared-memory hand-off between the host
// process and every virtual-camera backend.
//
// Design and rationale live in adr/0006-windows-frame-bridge.md. The short
// version, because the constraints here are unusual enough to restate at the
// point of use:
//
//   - One writer (MeoCameraHost), N lock-free readers (the Media Foundation
//     source, the DirectShow filter if ADR 0002 says it is needed, and
//     diagnostics). Readers never mutate, so N costs nothing over one.
//
//   - CAMERA_BUILD_PLAN.md §9.2 loads the DirectShow filter *inside the user's
//     Zoom call*. So the reader below never blocks, never allocates, never
//     throws, and never spins without a bound. Those are not style preferences;
//     a violation crashes a meeting and looks like Zoom's fault.
//
//   - §13.1 fuzzes this memory and §9.2 names torn writes, zero-length frames,
//     and mid-stream format changes as cases that must be survived. The reader
//     therefore treats the entire mapping as hostile input on every read and
//     validates before it dereferences.
//
//   - §8.4 requires the camera to render its own slate when the host is not
//     running. A dead process cannot publish its own death, so absence is
//     *derived* by the reader from a heartbeat, not read from a flag.
//
// The core is deliberately platform-neutral. Only the mapping underneath it is
// Windows code, so the concurrency logic can be tested on the development Mac
// and so a future macOS backend (ADR 0005) can reuse it.

#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace meo {

// Pixel format carried across the bridge. §9.4 settles on NV12 for the Media
// Foundation source; the DirectShow filter negotiates YUY2 as well (§9.5) but
// converts on its own side rather than asking the bridge for a second format.
enum class PixelFormat : uint32_t {
  kUnknown = 0,
  kNV12 = 1,
};

// What the host believes the session is doing. The camera backend maps every
// non-live value to a slate it can draw unaided (§8.4).
//
// Note there is no "host not running" member. That state is unpublishable by
// definition and is derived from the heartbeat instead — see ReadStatus.
enum class StreamState : uint32_t {
  kUnknown = 0,
  kLive = 1,           // frames are flowing from a paired phone
  kPaused = 2,         // user pressed pause; §2.1 privacy slate
  kNoPhonePaired = 3,  // host is running but nothing is paired yet
  kPhoneOffline = 4,   // paired, not currently reachable
  kReconnecting = 5,   // was live, network dropped, backoff in progress
};

// The outcome of a read. Everything except kLive means the caller should draw
// a slate rather than publish pixels.
enum class ReadStatus {
  kLive = 0,
  kPaused,
  kNoPhonePaired,
  kPhoneOffline,
  kReconnecting,

  // Derived, not published. The heartbeat is older than kProducerTimeoutMs, so
  // the host process is gone — crashed, killed, or never started. §8.4's
  // producer-absent case, and the one Milestone 5's gate verifies by
  // force-killing the host mid-call.
  kProducerAbsent,

  // The host is alive and says it is live, but the newest frame is older than
  // kFrameStaleMs. §14's frame-age watchdog: a frozen face must never be
  // mistaken for a live one.
  kStale,

  // Nothing is attached on this side. Distinct from kProducerAbsent, which
  // means "attached, and the other end is dead".
  kNotAttached,

  // The mapping failed validation: a different layout version, fuzzed contents
  // (§13.1), or a published frame too large for the buffer the caller offered,
  // which is how §9.2's mid-stream format change surfaces. Non-fatal by design
  // — the caller draws a slate and tries again on the next frame.
  kMalformed,

  // The seqlock retry budget was exhausted, meaning the writer overwrote the
  // slot mid-copy every time. Bounded rather than spun on, per §9.2.
  kTorn,
};

// Wire layout constants. These are the contract, and they are versioned: a
// reader that sees a different kLayoutVersion refuses the mapping outright
// rather than interpreting it optimistically.
inline constexpr uint32_t kBridgeMagic = 0x424F454D;  // 'MEOB', little-endian
inline constexpr uint16_t kLayoutVersion = 1;

// Four slots gives the writer ~133 ms at 30 FPS to wrap all the way around,
// against a copy measured in hundreds of microseconds. See ADR 0006 on why the
// ring is headroom and the seqlock is the actual guarantee.
inline constexpr uint32_t kSlotCount = 4;

// Sized for the largest format §8.3 and §9.4 advertise: 1920x1080 NV12, which
// is 12 bits per pixel. Every smaller format fits inside it.
inline constexpr uint32_t kMaxWidth = 1920;
inline constexpr uint32_t kMaxHeight = 1080;
inline constexpr uint32_t kPayloadCapacityBytes = kMaxWidth * kMaxHeight * 3 / 2;

// A host that has not stamped the header within this window is treated as
// gone. Long enough that a scheduling hiccup or a GC pause cannot fake a
// crash, short enough that a real crash reaches the slate within a few frames.
inline constexpr uint64_t kProducerTimeoutMs = 1500;

// A published frame older than this stops counting as live even while the host
// keeps heartbeating.
inline constexpr uint64_t kFrameStaleMs = 500;

// §9.2: bounded, never spun on.
inline constexpr int kMaxReadAttempts = 8;

// Metadata describing one frame, copied out of shared memory only after it has
// been validated. Every field here has been range-checked by the time a caller
// sees it.
struct FrameInfo {
  uint64_t frame_id = 0;
  uint64_t capture_timestamp_ms = 0;
  uint64_t age_ms = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t stride_y = 0;
  PixelFormat pixel_format = PixelFormat::kUnknown;
  uint32_t payload_bytes = 0;  // zero is legal: a state-only publish
  uint32_t rotation_degrees = 0;
  StreamState stream_state = StreamState::kUnknown;
  bool mirrored = false;
};

// Total bytes a mapping of the current layout occupies. Both ends compute this
// independently; a mismatch is caught by validation rather than assumed away.
size_t BridgeMappingBytes();

// Machine-wide monotonic milliseconds. Writer and readers are different
// processes, so this must be a clock they genuinely share — GetTickCount64 on
// Windows, CLOCK_MONOTONIC on POSIX. Both are per-boot and process-independent.
uint64_t MonotonicMillis();

namespace detail {
class Mapping;
}  // namespace detail

// The host side. Exactly one of these should exist per machine session.
class FrameBridgeWriter {
 public:
  FrameBridgeWriter();
  ~FrameBridgeWriter();

  FrameBridgeWriter(const FrameBridgeWriter&) = delete;
  FrameBridgeWriter& operator=(const FrameBridgeWriter&) = delete;

  // Creates (or takes over) the shared mapping and initialises the header.
  // `name` is the platform-specific section name; passing nullptr uses the
  // default, which is the only name the shipped backends look for.
  bool Create(const char* name = nullptr);
  void Close();
  bool attached() const;

  // Publishes one frame. `payload` must hold `payload_bytes` bytes of the
  // declared format. Returns false only for a caller error — oversized
  // payload, size disagreeing with the declared geometry, or not attached.
  //
  // This also stamps the heartbeat, so a host publishing at 30 FPS never needs
  // to call Heartbeat separately.
  bool PublishFrame(const void* payload, uint32_t payload_bytes,
                    const FrameInfo& info);

  // Publishes a state change with no pixels — pause, phone dropped, nothing
  // paired. The camera backend answers this by drawing its own slate, which is
  // why the host does not need to synthesise slate frames itself.
  bool PublishState(StreamState state);

  // Call on a timer, at least every kProducerTimeoutMs / 3, whenever the host
  // is alive but not publishing. This is what keeps readers from concluding
  // the host has died.
  void Heartbeat();

 private:
  std::unique_ptr<detail::Mapping> mapping_;
  uint64_t instance_id_ = 0;
  uint64_t next_frame_id_ = 1;
};

// The camera-backend side. Cheap to construct, safe to hold for the lifetime
// of the process, and safe to call from a Media Foundation RequestSample or a
// DirectShow FillBuffer callback.
class FrameBridgeReader {
 public:
  FrameBridgeReader();
  ~FrameBridgeReader();

  FrameBridgeReader(const FrameBridgeReader&) = delete;
  FrameBridgeReader& operator=(const FrameBridgeReader&) = delete;

  // Opens an existing mapping. Returns false when the host has never run,
  // which is an ordinary startup condition and not an error — the camera shows
  // its "Meo isn't running" slate and retries.
  bool Open(const char* name = nullptr);
  void Close();
  bool attached() const;

  // Copies the newest published frame into `dest`.
  //
  // Allocation-free, lock-free, and bounded: it performs at most
  // kMaxReadAttempts seqlock retries and then gives up with kTorn. It never
  // waits for the writer and never throws.
  //
  // `info` is filled in for every status except kNotAttached and kMalformed,
  // so a caller can log frame age even when it is drawing a slate.
  //
  // A return of kLive with `info->payload_bytes == 0` cannot happen: a
  // zero-length publish is always a state change and reports that state.
  ReadStatus ReadLatest(void* dest, size_t dest_capacity, FrameInfo* info);

  // Reads state and liveness without copying pixels. Useful for a backend that
  // wants to decide on a slate before it has a buffer to fill.
  ReadStatus PeekStatus(FrameInfo* info);

 private:
  ReadStatus ReadInternal(void* dest, size_t dest_capacity, FrameInfo* info,
                          bool copy_payload);

  std::unique_ptr<detail::Mapping> mapping_;
};

}  // namespace meo
