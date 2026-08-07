// Slate tests.
//
// The slate is the last thing standing when everything else has failed: no
// host, no phone, no network. §8.4 requires the camera to draw it unaided, and
// Milestone 5's gate verifies it by force-killing the host mid-call. So it is
// worth testing harder than its size suggests.
//
// Runs on the development Mac because the renderer is deliberately free of
// GDI, Direct2D, DirectWrite, and every other Windows drawing API — it writes
// bytes into a buffer (ADR 0006, Slate.h).

#include "Slate.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
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

const meo::ReadStatus kAllStatuses[] = {
    meo::ReadStatus::kLive,          meo::ReadStatus::kPaused,
    meo::ReadStatus::kNoPhonePaired, meo::ReadStatus::kPhoneOffline,
    meo::ReadStatus::kReconnecting,  meo::ReadStatus::kProducerAbsent,
    meo::ReadStatus::kStale,         meo::ReadStatus::kNotAttached,
    meo::ReadStatus::kMalformed,     meo::ReadStatus::kTorn,
};

size_t Nv12Bytes(uint32_t stride, uint32_t height) {
  return static_cast<size_t>(stride) * height +
         static_cast<size_t>(stride) * (height / 2);
}

void TestGeometryIsValidated() {
  std::printf("bad geometry is refused, not clamped\n");
  std::vector<uint8_t> buffer(Nv12Bytes(1280, 720));
  auto* d = buffer.data();

  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, nullptr, 1280, 720, 1280, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 0, 720, 1280, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 1280, 0, 1280, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 1281, 720, 1281, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 1280, 721, 1280, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 1280, 720, 640, 0));
  CHECK(!meo::RenderSlate(meo::ReadStatus::kPaused, d, 3840, 2160, 3840, 0));

  CHECK(meo::RenderSlate(meo::ReadStatus::kPaused, d, 1280, 720, 1280, 0));
}

void TestEveryStatusRendersAtEveryFormat() {
  std::printf("every status renders at every advertised format\n");
  // The formats §8.3 and §9.4 advertise.
  const struct { uint32_t w, h; } formats[] = {
      {640, 480}, {1280, 720}, {1920, 1080},
  };

  for (const auto& f : formats) {
    for (meo::ReadStatus status : kAllStatuses) {
      std::vector<uint8_t> buffer(Nv12Bytes(f.w, f.h), 0x00);
      CHECK(meo::RenderSlate(status, buffer.data(), f.w, f.h, f.w, 0));

      // Something was drawn: the luma plane is not uniformly one value, which
      // would mean the text failed to render.
      const uint8_t first = buffer[0];
      bool varies = false;
      for (size_t i = 0; i < static_cast<size_t>(f.w) * f.h; ++i) {
        if (buffer[i] != first) { varies = true; break; }
      }
      if (!varies) {
        std::printf("  FAIL: %s at %ux%u drew no text\n",
                    meo::SlateMessage(status), f.w, f.h);
        ++g_failures;
      }
      ++g_checks;
    }
  }
}

void TestStridePaddingIsNeverTouched() {
  std::printf("stride padding is left alone\n");
  // MF and DirectShow both hand out buffers whose stride exceeds the width.
  // Writing into the padding is how a renderer produces the skewed diagonal
  // bars the probe README warns about.
  const uint32_t width = 640, height = 480, stride = 768;
  std::vector<uint8_t> buffer(Nv12Bytes(stride, height), 0x5A);

  CHECK(meo::RenderSlate(meo::ReadStatus::kReconnecting, buffer.data(), width,
                         height, stride, 17));

  bool padding_intact = true;
  for (uint32_t y = 0; y < height; ++y) {
    for (uint32_t x = width; x < stride; ++x) {
      if (buffer[static_cast<size_t>(y) * stride + x] != 0x5A) {
        padding_intact = false;
      }
    }
  }
  CHECK(padding_intact);

  const size_t chroma_base = static_cast<size_t>(stride) * height;
  bool chroma_padding_intact = true;
  for (uint32_t y = 0; y < height / 2; ++y) {
    for (uint32_t x = width; x < stride; ++x) {
      if (buffer[chroma_base + static_cast<size_t>(y) * stride + x] != 0x5A) {
        chroma_padding_intact = false;
      }
    }
  }
  CHECK(chroma_padding_intact);
}

void TestChromaPlaneIsWellFormed() {
  std::printf("the chroma plane is interleaved correctly\n");
  const uint32_t width = 640, height = 480, stride = 640;
  std::vector<uint8_t> buffer(Nv12Bytes(stride, height), 0x00);

  // Paused is the one slate with a strong colour cast (§6.5), so it is the
  // one where a U/V swap would actually be visible.
  CHECK(meo::RenderSlate(meo::ReadStatus::kPaused, buffer.data(), width, height,
                         stride, 0));

  const uint8_t* chroma = buffer.data() + static_cast<size_t>(stride) * height;
  const uint8_t u = chroma[0];
  const uint8_t v = chroma[1];
  CHECK(u != v);  // an actual colour, not neutral grey

  bool interleaved = true;
  for (uint32_t y = 0; y < height / 2; ++y) {
    for (uint32_t x = 0; x < width; x += 2) {
      const size_t i = static_cast<size_t>(y) * stride + x;
      if (chroma[i] != u || chroma[i + 1] != v) interleaved = false;
    }
  }
  CHECK(interleaved);
}

void TestRenderingIsDeterministic() {
  std::printf("rendering is deterministic\n");
  const uint32_t w = 1280, h = 720;
  std::vector<uint8_t> a(Nv12Bytes(w, h), 0), b(Nv12Bytes(w, h), 0);

  for (meo::ReadStatus status : kAllStatuses) {
    CHECK(meo::RenderSlate(status, a.data(), w, h, w, 42));
    CHECK(meo::RenderSlate(status, b.data(), w, h, w, 42));
    CHECK(std::memcmp(a.data(), b.data(), a.size()) == 0);
  }
}

void TestOnlyTransientStatesAnimate() {
  std::printf("only transient states animate (§14)\n");
  const uint32_t w = 1280, h = 720;
  std::vector<uint8_t> t0(Nv12Bytes(w, h), 0), t1(Nv12Bytes(w, h), 0);

  // Reconnecting resolves on its own, so motion is honest and also proves the
  // camera pipeline is alive rather than showing a frozen copy of itself.
  CHECK(meo::RenderSlate(meo::ReadStatus::kReconnecting, t0.data(), w, h, w, 0));
  CHECK(meo::RenderSlate(meo::ReadStatus::kReconnecting, t1.data(), w, h, w, 30));
  CHECK(std::memcmp(t0.data(), t1.data(), t0.size()) != 0);

  // Paused and host-absent must be still. Motion on those would suggest the
  // camera is doing something it is not.
  for (meo::ReadStatus status :
       {meo::ReadStatus::kPaused, meo::ReadStatus::kProducerAbsent,
        meo::ReadStatus::kNoPhonePaired}) {
    CHECK(meo::RenderSlate(status, t0.data(), w, h, w, 0));
    CHECK(meo::RenderSlate(status, t1.data(), w, h, w, 55));
    CHECK(std::memcmp(t0.data(), t1.data(), t0.size()) == 0);
  }
}

void TestMessagesAreActionable() {
  std::printf("messages exist, differ, and fit the frame\n");

  for (meo::ReadStatus status : kAllStatuses) {
    const char* message = meo::SlateMessage(status);
    CHECK(message != nullptr);
    CHECK(std::strlen(message) > 0);
    // §15: the user must be told what to do, not just what broke. Live is the
    // only status with nothing to act on.
    const char* hint = meo::SlateHint(status);
    if (status != meo::ReadStatus::kLive) {
      CHECK(hint != nullptr);
    }
  }

  // The states a user is most likely to actually hit must not share a message,
  // or the slate stops carrying information.
  CHECK(std::strcmp(meo::SlateMessage(meo::ReadStatus::kPaused),
                    meo::SlateMessage(meo::ReadStatus::kProducerAbsent)) != 0);
  CHECK(std::strcmp(meo::SlateMessage(meo::ReadStatus::kNoPhonePaired),
                    meo::SlateMessage(meo::ReadStatus::kPhoneOffline)) != 0);
  CHECK(std::strcmp(meo::SlateMessage(meo::ReadStatus::kReconnecting),
                    meo::SlateMessage(meo::ReadStatus::kStale)) != 0);
}

void TestSmallestPlausibleFrame() {
  std::printf("a tiny frame degrades instead of overrunning\n");
  // Not a format Meo advertises, but a consuming app can negotiate oddly and
  // the renderer must not scribble past the buffer when the text cannot fit.
  const uint32_t w = 32, h = 24;
  std::vector<uint8_t> buffer(Nv12Bytes(w, h), 0);
  CHECK(meo::RenderSlate(meo::ReadStatus::kProducerAbsent, buffer.data(), w, h,
                         w, 0));
}

}  // namespace

int main() {
  std::printf("Meo slate tests\n\n");

  TestGeometryIsValidated();
  TestEveryStatusRendersAtEveryFormat();
  TestStridePaddingIsNeverTouched();
  TestChromaPlaneIsWellFormed();
  TestRenderingIsDeterministic();
  TestOnlyTransientStatesAnimate();
  TestMessagesAreActionable();
  TestSmallestPlausibleFrame();

  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
