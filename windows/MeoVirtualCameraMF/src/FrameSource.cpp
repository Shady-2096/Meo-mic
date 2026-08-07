#include "FrameSource.h"

#include <cstring>

namespace meo {
namespace {

// The camera exists in the consumer's device list whether or not Meo is
// running, so it spends most of its life unattached. Retrying twice a second
// is responsive enough that starting Meo feels immediate, and infrequent
// enough that an idle camera costs nothing.
constexpr uint64_t kReattachIntervalMs = 500;

}  // namespace

CameraFrameSource::CameraFrameSource() {
  staging_.resize(kPayloadCapacityBytes);
}

CameraFrameSource::~CameraFrameSource() = default;

void CameraFrameSource::SetOutputFormat(uint32_t width, uint32_t height) {
  if (width == 0 || height == 0) return;
  if ((width % 2) != 0 || (height % 2) != 0) return;
  if (width > kMaxWidth || height > kMaxHeight) return;
  out_width_ = width;
  out_height_ = height;
}

void CameraFrameSource::MaybeAttach(uint64_t now_ms) {
  if (reader_.attached()) return;
  if (attach_attempted_ && now_ms - last_attach_attempt_ms_ < kReattachIntervalMs) {
    return;
  }
  last_attach_attempt_ms_ = now_ms;
  attach_attempted_ = true;
  // Failure is the normal case when Meo is not running. Nothing is logged and
  // nothing is retried harder.
  reader_.Open(bridge_name_);
}

ReadStatus CameraFrameSource::FillFrame(uint8_t* dest, uint32_t stride,
                                        uint64_t tick) {
  if (dest == nullptr || stride < out_width_) {
    // Nothing sane can be done with this buffer. The caller is the backend, so
    // this is a programming error rather than anything the user caused, but it
    // still must not become a crash inside a meeting app.
    return ReadStatus::kMalformed;
  }

  const uint64_t now = MonotonicMillis();
  MaybeAttach(now);

  FrameInfo info;
  ReadStatus status = ReadStatus::kNotAttached;

  if (reader_.attached()) {
    status = reader_.ReadLatest(staging_.data(), staging_.size(), &info);

    // A host that exited leaves the mapping behind on Windows only as long as
    // a handle remains open; either way the heartbeat has gone stale and the
    // reader says so. Dropping the attachment lets a restarted host be picked
    // up by the next MaybeAttach rather than being shadowed by a dead mapping.
    if (status == ReadStatus::kProducerAbsent ||
        status == ReadStatus::kMalformed) {
      reader_.Close();
      last_attach_attempt_ms_ = now;
    }
  }

  if (status == ReadStatus::kTorn) ++stats_.torn_reads;

  if (status == ReadStatus::kLive) {
    // §5.4 keeps the bridge format fixed for the life of a stream, so a
    // mismatch here means either a host bug or a mid-stream change. Either
    // way the camera must not renegotiate and must not render garbage: it
    // shows a slate and counts the event for the §15 health panel.
    if (info.width != out_width_ || info.height != out_height_) {
      ++stats_.format_mismatches;
      status = ReadStatus::kStale;
    }
  }

  if (status == ReadStatus::kLive) {
    // Row-by-row, because the source stride and the consumer's stride are
    // independent. Copying the whole plane in one memcpy is the mistake that
    // produces the skewed diagonal picture the probe README describes.
    const uint8_t* src = staging_.data();
    for (uint32_t y = 0; y < out_height_; ++y) {
      std::memcpy(dest + static_cast<size_t>(y) * stride,
                  src + static_cast<size_t>(y) * info.stride_y, out_width_);
    }
    const uint8_t* src_chroma =
        src + static_cast<size_t>(info.stride_y) * out_height_;
    uint8_t* dst_chroma = dest + static_cast<size_t>(stride) * out_height_;
    for (uint32_t y = 0; y < out_height_ / 2; ++y) {
      std::memcpy(dst_chroma + static_cast<size_t>(y) * stride,
                  src_chroma + static_cast<size_t>(y) * info.stride_y,
                  out_width_);
    }

    ++stats_.frames_delivered;
    stats_.last_frame_id = info.frame_id;
    stats_.last_age_ms = info.age_ms;
    stats_.last_status = status;
    return status;
  }

  RenderSlate(status, dest, out_width_, out_height_, stride, tick);
  ++stats_.slates_drawn;
  stats_.last_age_ms = info.age_ms;
  stats_.last_status = status;
  return status;
}

}  // namespace meo
