// CameraFrameSource tests — the live-frame-or-slate decision both Windows
// backends share.
//
// The cases below are drawn straight from §9.2's list of things the filter
// must survive ("missing host, torn writes, zero-length frames, format changes
// mid-stream, host killed under load") and from Milestone 5's gate ("a crash
// or update of the host app can never leave a permanently frozen camera").

#include "FrameSource.h"

#include "../MeoFrameBridge/src/Mapping.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

int g_failures = 0;
int g_checks = 0;

void Check(bool condition, const char* what, int line) {
  ++g_checks;
  if (!condition) {
    ++g_failures;
    std::printf("  FAIL (line %d): %s\n", line, what);
  }
}

#define CHECK(cond) Check((cond), #cond, __LINE__)

constexpr size_t kOffHeartbeat = 24;

std::string UniqueName(const char* tag) {
  static int counter = 0;
  char buffer[128];
  std::snprintf(buffer, sizeof(buffer), "Local\\MeoCamera.FsTest.%s.%d", tag,
                ++counter);
  return std::string(buffer);
}

size_t Nv12Bytes(uint32_t stride, uint32_t height) {
  return static_cast<size_t>(stride) * height +
         static_cast<size_t>(stride) * (height / 2);
}

// Publishes a frame whose every luma byte is `fill` and every chroma byte is
// `fill ^ 0xFF`, so a plane mix-up or a stride error is visible by inspection.
bool PublishFilled(meo::FrameBridgeWriter& writer, uint32_t width,
                   uint32_t height, uint32_t stride, uint8_t fill) {
  std::vector<uint8_t> pixels(Nv12Bytes(stride, height));
  std::memset(pixels.data(), fill, static_cast<size_t>(stride) * height);
  std::memset(pixels.data() + static_cast<size_t>(stride) * height,
              static_cast<uint8_t>(fill ^ 0xFF),
              static_cast<size_t>(stride) * (height / 2));

  meo::FrameInfo info;
  info.width = width;
  info.height = height;
  info.stride_y = stride;
  info.pixel_format = meo::PixelFormat::kNV12;
  return writer.PublishFrame(pixels.data(),
                             static_cast<uint32_t>(pixels.size()), info);
}

void TestNoHostDrawsTheHostAbsentSlate() {
  std::printf("with no host at all, the camera still produces frames (§8.4)\n");

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting("Local\\MeoCamera.FsTest.NeverCreated");
  source.SetOutputFormat(640, 480);

  std::vector<uint8_t> dest(Nv12Bytes(640, 480), 0);

  // The camera is in Zoom's list before Meo has ever been started. It must
  // keep answering, forever, without a host.
  for (int i = 0; i < 120; ++i) {
    const meo::ReadStatus status =
        source.FillFrame(dest.data(), 640, static_cast<uint64_t>(i));
    CHECK(status == meo::ReadStatus::kNotAttached);
    if (g_failures > 0) return;
  }
  CHECK(source.stats().slates_drawn == 120);
  CHECK(source.stats().frames_delivered == 0);

  // Something was actually drawn, not left as zeroes.
  bool nonzero = false;
  for (uint8_t b : dest) {
    if (b != 0) { nonzero = true; break; }
  }
  CHECK(nonzero);
}

void TestLiveFrameIsDeliveredWithStrideConversion() {
  std::printf("a live frame survives a stride change intact\n");
  const std::string name = UniqueName("live");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(640, 480);

  // Bridge stride equals width; the consumer asks for a padded stride. This is
  // the ordinary case in Media Foundation, and getting it wrong produces the
  // skewed diagonal picture the probe README describes.
  CHECK(PublishFilled(writer, 640, 480, 640, 0x7C));

  const uint32_t dest_stride = 768;
  std::vector<uint8_t> dest(Nv12Bytes(dest_stride, 480), 0x11);

  CHECK(source.FillFrame(dest.data(), dest_stride, 0) == meo::ReadStatus::kLive);
  CHECK(source.stats().frames_delivered == 1);

  bool luma_ok = true, chroma_ok = true, padding_ok = true;
  for (uint32_t y = 0; y < 480; ++y) {
    for (uint32_t x = 0; x < 640; ++x) {
      if (dest[static_cast<size_t>(y) * dest_stride + x] != 0x7C) luma_ok = false;
    }
    for (uint32_t x = 640; x < dest_stride; ++x) {
      if (dest[static_cast<size_t>(y) * dest_stride + x] != 0x11) {
        padding_ok = false;
      }
    }
  }
  const size_t chroma_base = static_cast<size_t>(dest_stride) * 480;
  for (uint32_t y = 0; y < 240; ++y) {
    for (uint32_t x = 0; x < 640; ++x) {
      if (dest[chroma_base + static_cast<size_t>(y) * dest_stride + x] !=
          static_cast<uint8_t>(0x7C ^ 0xFF)) {
        chroma_ok = false;
      }
    }
  }
  CHECK(luma_ok);
  CHECK(chroma_ok);
  CHECK(padding_ok);
}

void TestSourceStrideWiderThanWidth() {
  std::printf("a padded source stride is unpacked correctly\n");
  const std::string name = UniqueName("srcstride");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(640, 480);

  // The host publishes with padding of its own; the consumer wants none.
  CHECK(PublishFilled(writer, 640, 480, 704, 0x3D));

  std::vector<uint8_t> dest(Nv12Bytes(640, 480), 0);
  CHECK(source.FillFrame(dest.data(), 640, 0) == meo::ReadStatus::kLive);

  bool ok = true;
  for (uint32_t y = 0; y < 480; ++y) {
    for (uint32_t x = 0; x < 640; ++x) {
      if (dest[static_cast<size_t>(y) * 640 + x] != 0x3D) ok = false;
    }
  }
  CHECK(ok);
}

void TestFormatMismatchShowsSlateInsteadOfGarbage() {
  std::printf("a mid-stream format change becomes a slate, not garbage (§5.4)\n");
  const std::string name = UniqueName("mismatch");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(1280, 720);

  // The host publishes 640x480 while the camera advertises 720p. §5.4 forbids
  // renegotiating the media type mid-call, so the camera must hold its format
  // and show a slate rather than scale or reinterpret.
  CHECK(PublishFilled(writer, 640, 480, 640, 0x55));

  std::vector<uint8_t> dest(Nv12Bytes(1280, 720), 0);
  const meo::ReadStatus status = source.FillFrame(dest.data(), 1280, 0);

  CHECK(status != meo::ReadStatus::kLive);
  CHECK(source.stats().format_mismatches == 1);
  CHECK(source.stats().frames_delivered == 0);
  CHECK(source.stats().slates_drawn == 1);
}

void TestStatePublishesReachTheSlate() {
  std::printf("host state changes reach the right slate\n");
  const std::string name = UniqueName("states");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(640, 480);
  std::vector<uint8_t> dest(Nv12Bytes(640, 480), 0);

  const struct {
    meo::StreamState state;
    meo::ReadStatus expected;
  } cases[] = {
      {meo::StreamState::kPaused, meo::ReadStatus::kPaused},
      {meo::StreamState::kNoPhonePaired, meo::ReadStatus::kNoPhonePaired},
      {meo::StreamState::kPhoneOffline, meo::ReadStatus::kPhoneOffline},
      {meo::StreamState::kReconnecting, meo::ReadStatus::kReconnecting},
  };

  for (const auto& c : cases) {
    CHECK(writer.PublishState(c.state));
    CHECK(source.FillFrame(dest.data(), 640, 0) == c.expected);
  }

  // And back to live without reattaching.
  CHECK(PublishFilled(writer, 640, 480, 640, 0x99));
  CHECK(source.FillFrame(dest.data(), 640, 0) == meo::ReadStatus::kLive);
}

void TestHostKilledMidCallRecoversWhenItReturns() {
  std::printf("host killed mid-call, then restarted, recovers (Milestone 5)\n");
  const std::string name = UniqueName("killed");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(640, 480);
  std::vector<uint8_t> dest(Nv12Bytes(640, 480), 0);

  CHECK(PublishFilled(writer, 640, 480, 640, 0x21));
  CHECK(source.FillFrame(dest.data(), 640, 0) == meo::ReadStatus::kLive);

  // Simulate the host being force-killed by winding its heartbeat back. This
  // is precisely what Milestone 5's gate does with a real process, and the
  // requirement is that the camera never freezes on the last live frame.
  {
    meo::detail::Mapping poke;
    CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
    uint64_t stale = meo::MonotonicMillis() - (meo::kProducerTimeoutMs + 200);
    std::memcpy(static_cast<uint8_t*>(poke.data()) + kOffHeartbeat, &stale,
                sizeof(stale));
  }

  CHECK(source.FillFrame(dest.data(), 640, 0) ==
        meo::ReadStatus::kProducerAbsent);

  // The frame must have been replaced by the slate, not left frozen on the
  // last live picture. §14 calls a stale frozen image mistaken for live a
  // threat the product designs against.
  CHECK(dest[static_cast<size_t>(240) * 640 + 320] != 0x21);

  // Host comes back. The source throttles reattachment, so give it past the
  // interval and confirm it recovers on its own with no restart of the
  // consuming app.
  writer.Heartbeat();
  CHECK(PublishFilled(writer, 640, 480, 640, 0x64));
  std::this_thread::sleep_for(std::chrono::milliseconds(600));

  meo::ReadStatus recovered = meo::ReadStatus::kNotAttached;
  for (int i = 0; i < 5 && recovered != meo::ReadStatus::kLive; ++i) {
    writer.Heartbeat();
    CHECK(PublishFilled(writer, 640, 480, 640, 0x64));
    recovered = source.FillFrame(dest.data(), 640, 0);
  }
  CHECK(recovered == meo::ReadStatus::kLive);
  CHECK(dest[static_cast<size_t>(240) * 640 + 320] == 0x64);
}

void TestBadCallerBufferIsRefused() {
  std::printf("a bad destination buffer is refused, not written\n");
  meo::CameraFrameSource source;
  source.SetOutputFormat(640, 480);
  std::vector<uint8_t> dest(Nv12Bytes(640, 480), 0);

  CHECK(source.FillFrame(nullptr, 640, 0) == meo::ReadStatus::kMalformed);
  // Stride narrower than the advertised width.
  CHECK(source.FillFrame(dest.data(), 320, 0) == meo::ReadStatus::kMalformed);
}

void TestOutputFormatRejectsNonsense() {
  std::printf("the advertised format cannot be set to nonsense\n");
  meo::CameraFrameSource source;
  source.SetOutputFormat(1280, 720);

  // Each of these must be ignored, leaving 1280x720 in place — verified by the
  // fact that a 1280x720 publish still reads as live afterwards.
  source.SetOutputFormat(0, 0);
  source.SetOutputFormat(641, 480);
  source.SetOutputFormat(3840, 2160);

  const std::string name = UniqueName("format");
  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  source.SetBridgeNameForTesting(name.c_str());

  CHECK(PublishFilled(writer, 1280, 720, 1280, 0x42));
  std::vector<uint8_t> dest(Nv12Bytes(1280, 720), 0);
  CHECK(source.FillFrame(dest.data(), 1280, 0) == meo::ReadStatus::kLive);
}

void TestSustainedRunNeverStalls() {
  std::printf("a sustained run always produces a frame\n");
  const std::string name = UniqueName("sustained");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::CameraFrameSource source;
  source.SetBridgeNameForTesting(name.c_str());
  source.SetOutputFormat(1280, 720);
  std::vector<uint8_t> dest(Nv12Bytes(1280, 720), 0);

  // Alternating live frames, state changes, and gaps. Whatever the host does,
  // the consumer must get a frame every single time it asks — that is the
  // whole contract §8.4 imposes.
  int produced = 0;
  for (int i = 0; i < 300; ++i) {
    if (i % 7 == 0) {
      writer.PublishState(meo::StreamState::kReconnecting);
    } else if (i % 11 == 0) {
      writer.Heartbeat();  // alive, publishing nothing
    } else {
      PublishFilled(writer, 1280, 720, 1280, static_cast<uint8_t>(i));
    }

    const meo::ReadStatus status =
        source.FillFrame(dest.data(), 1280, static_cast<uint64_t>(i));
    // Every status is acceptable; silence is not.
    (void)status;
    ++produced;
  }
  CHECK(produced == 300);
  CHECK(source.stats().frames_delivered + source.stats().slates_drawn == 300);
}

}  // namespace

int main() {
  std::printf("Meo camera frame-source tests\n\n");

  TestNoHostDrawsTheHostAbsentSlate();
  TestLiveFrameIsDeliveredWithStrideConversion();
  TestSourceStrideWiderThanWidth();
  TestFormatMismatchShowsSlateInsteadOfGarbage();
  TestStatePublishesReachTheSlate();
  TestHostKilledMidCallRecoversWhenItReturns();
  TestBadCallerBufferIsRefused();
  TestOutputFormatRejectsNonsense();
  TestSustainedRunNeverStalls();

  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
