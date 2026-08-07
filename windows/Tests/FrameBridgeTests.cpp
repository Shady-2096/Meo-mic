// Frame-bridge tests.
//
// These run on the development Mac as well as on Windows, which is the whole
// reason the bridge core was kept platform-neutral (ADR 0006): the seqlock,
// the ring wrap, the validation, and the watchdogs are the parts most likely
// to be wrong and the parts least dependent on the platform.
//
// Several tests reach into the mapping and edit raw bytes at documented
// offsets rather than going through the writer. That is deliberate twice over:
// it is the only way to reach states a correct writer never produces (a
// crashed host mid-write, a fuzzed header), and it pins the wire layout, so a
// silent change to the struct fails here instead of in a user's Zoom call.
//
// No test framework, on purpose — the DirectShow filter this bridge feeds
// (§9.2) is the highest-blast-radius code in the project, and it should be
// buildable and testable with nothing but a compiler.

#include "meo/FrameBridge.h"

#include "../MeoFrameBridge/src/Mapping.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
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

const char* StatusName(meo::ReadStatus s) {
  switch (s) {
    case meo::ReadStatus::kLive: return "Live";
    case meo::ReadStatus::kPaused: return "Paused";
    case meo::ReadStatus::kNoPhonePaired: return "NoPhonePaired";
    case meo::ReadStatus::kPhoneOffline: return "PhoneOffline";
    case meo::ReadStatus::kReconnecting: return "Reconnecting";
    case meo::ReadStatus::kProducerAbsent: return "ProducerAbsent";
    case meo::ReadStatus::kStale: return "Stale";
    case meo::ReadStatus::kNotAttached: return "NotAttached";
    case meo::ReadStatus::kMalformed: return "Malformed";
    case meo::ReadStatus::kTorn: return "Torn";
  }
  return "?";
}

// Documented wire offsets from adr/0006-windows-frame-bridge.md. Hard-coded
// rather than derived, so that changing the layout without updating the ADR
// breaks a test.
constexpr size_t kOffMagic = 0;
constexpr size_t kOffLayoutVersion = 4;
constexpr size_t kOffSlotCount = 8;
constexpr size_t kOffHeartbeat = 24;
constexpr size_t kOffLatestSlot = 40;
constexpr size_t kHeaderBytes = 64;
constexpr size_t kSlotHeaderBytes = 64;
constexpr size_t kSlotSeqOffset = 0;
constexpr size_t kSlotTimestampOffset = 16;

size_t SlotOffset(uint32_t index) {
  return kHeaderBytes +
         static_cast<size_t>(index) * (kSlotHeaderBytes + meo::kPayloadCapacityBytes);
}

// A private bridge name per test, so a failure in one cannot poison another
// and so a crashed earlier run leaves nothing behind that changes a result.
std::string UniqueName(const char* tag) {
  static int counter = 0;
  char buffer[128];
  std::snprintf(buffer, sizeof(buffer), "Local\\MeoCamera.Test.%s.%d", tag,
                ++counter);
  return std::string(buffer);
}

struct TestFrame {
  uint32_t width = 320;
  uint32_t height = 240;
  uint32_t stride = 320;
  std::vector<uint8_t> pixels;

  explicit TestFrame(uint8_t fill = 0x40) {
    pixels.assign(static_cast<size_t>(stride) * height +
                      static_cast<size_t>(stride) * (height / 2),
                  fill);
  }

  meo::FrameInfo Info() const {
    meo::FrameInfo info;
    info.width = width;
    info.height = height;
    info.stride_y = stride;
    info.pixel_format = meo::PixelFormat::kNV12;
    info.rotation_degrees = 0;
    return info;
  }
};

// --------------------------------------------------------------------------

void TestLayoutIsStable() {
  std::printf("layout is stable\n");
  // 1920x1080 NV12 = 3,110,400 bytes per slot payload, four slots.
  CHECK(meo::kPayloadCapacityBytes == 1920u * 1080u * 3u / 2u);
  CHECK(meo::kSlotCount == 4);
  CHECK(meo::BridgeMappingBytes() ==
        kHeaderBytes + 4 * (kSlotHeaderBytes + meo::kPayloadCapacityBytes));
  // ~11.9 MiB, as ADR 0006 claims.
  CHECK(meo::BridgeMappingBytes() < 13u * 1024 * 1024);
}

void TestPublishAndRead() {
  std::printf("a published frame reads back intact\n");
  const std::string name = UniqueName("publish");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0xAB);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;
  const meo::ReadStatus status =
      reader.ReadLatest(dest.data(), dest.size(), &info);

  CHECK(status == meo::ReadStatus::kLive);
  CHECK(info.width == 320);
  CHECK(info.height == 240);
  CHECK(info.stride_y == 320);
  CHECK(info.pixel_format == meo::PixelFormat::kNV12);
  CHECK(info.payload_bytes == frame.pixels.size());
  CHECK(info.frame_id == 1);
  CHECK(std::memcmp(dest.data(), frame.pixels.data(), frame.pixels.size()) == 0);
}

void TestReaderWithoutWriter() {
  std::printf("a reader with no host attaches to nothing\n");
  meo::FrameBridgeReader reader;
  // Nothing ever created this name. §8.4's ordinary startup case: the camera
  // exists in Zoom's list before Meo has ever run.
  CHECK(!reader.Open("Local\\MeoCamera.Test.NeverCreated"));

  meo::FrameInfo info;
  std::vector<uint8_t> dest(1024);
  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kNotAttached);
}

void TestRingWrapAlwaysYieldsNewest() {
  std::printf("the ring always yields the newest frame\n");
  const std::string name = UniqueName("wrap");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);

  // Publish well past kSlotCount so the ring wraps several times. §5.4 says
  // stale frames are dropped rather than queued, so the reader must never see
  // anything but the most recent publish.
  for (uint32_t i = 1; i <= 4 * meo::kSlotCount + 3; ++i) {
    TestFrame frame(static_cast<uint8_t>(i));
    CHECK(writer.PublishFrame(frame.pixels.data(),
                              static_cast<uint32_t>(frame.pixels.size()),
                              frame.Info()));

    meo::FrameInfo info;
    CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
          meo::ReadStatus::kLive);
    CHECK(info.frame_id == i);
    CHECK(dest[0] == static_cast<uint8_t>(i));
    CHECK(dest[frame.pixels.size() - 1] == static_cast<uint8_t>(i));
  }
}

void TestStatePublishDrawsSlates() {
  std::printf("state publishes map to slates, with no pixels\n");
  const std::string name = UniqueName("state");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;

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
    const meo::ReadStatus status =
        reader.ReadLatest(dest.data(), dest.size(), &info);
    CHECK(status == c.expected);
    // §9.2 lists zero-length frames as a case to survive; here it arrives
    // legitimately and must not be mistaken for corruption.
    CHECK(info.payload_bytes == 0);
  }

  // kUnknown is not a publishable state.
  CHECK(!writer.PublishState(meo::StreamState::kUnknown));
}

void TestPeekDoesNotNeedABuffer() {
  std::printf("status can be peeked without a buffer\n");
  const std::string name = UniqueName("peek");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x11);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  meo::FrameInfo info;
  CHECK(reader.PeekStatus(&info) == meo::ReadStatus::kLive);
  CHECK(info.payload_bytes == frame.pixels.size());
  CHECK(info.width == 320);
}

void TestWriterRejectsBadGeometry() {
  std::printf("the writer refuses frames its readers would reject\n");
  const std::string name = UniqueName("geometry");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));

  TestFrame frame(0x22);
  meo::FrameInfo info = frame.Info();

  // Size disagreeing with declared geometry.
  CHECK(!writer.PublishFrame(frame.pixels.data(), 100, info));

  // Larger than the slot can hold.
  CHECK(!writer.PublishFrame(frame.pixels.data(),
                             meo::kPayloadCapacityBytes + 1, info));

  // Odd dimensions cannot be NV12.
  meo::FrameInfo odd = info;
  odd.height = 241;
  CHECK(!writer.PublishFrame(frame.pixels.data(),
                             static_cast<uint32_t>(frame.pixels.size()), odd));

  // Stride narrower than the picture.
  meo::FrameInfo narrow = info;
  narrow.stride_y = 160;
  CHECK(!writer.PublishFrame(frame.pixels.data(),
                             static_cast<uint32_t>(frame.pixels.size()),
                             narrow));

  // Beyond the largest advertised format (§8.3).
  meo::FrameInfo huge = info;
  huge.width = 3840;
  huge.height = 2160;
  huge.stride_y = 3840;
  CHECK(!writer.PublishFrame(frame.pixels.data(),
                             static_cast<uint32_t>(frame.pixels.size()), huge));

  CHECK(!writer.PublishFrame(nullptr, 0, info));
}

void TestBufferTooSmallIsNotACrash() {
  std::printf("a caller buffer that is too small refuses rather than overruns\n");
  const std::string name = UniqueName("small");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x33);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  std::vector<uint8_t> tiny(64, 0);
  meo::FrameInfo info;
  CHECK(reader.ReadLatest(tiny.data(), tiny.size(), &info) ==
        meo::ReadStatus::kMalformed);
  // Untouched: the copy must be refused before it starts, not truncated.
  for (uint8_t b : tiny) CHECK(b == 0);
}

// --------------------------------------------------------------------------
// Tests that poke the mapping directly to reach states a correct writer never
// produces.

void TestProducerAbsentWhenHeartbeatGoesStale() {
  std::printf("a dead host becomes a producer-absent slate (§8.4)\n");
  const std::string name = UniqueName("heartbeat");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x44);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;
  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kLive);

  // Wind the heartbeat back past the timeout. This is what a crashed or
  // force-killed host looks like from the camera's side — Milestone 5's gate
  // verifies exactly this by killing the host mid-call.
  meo::detail::Mapping poke;
  CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
  auto* bytes = static_cast<uint8_t*>(poke.data());
  uint64_t stale = meo::MonotonicMillis() - (meo::kProducerTimeoutMs + 200);
  std::memcpy(bytes + kOffHeartbeat, &stale, sizeof(stale));

  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kProducerAbsent);

  // A live host recovers without reattaching.
  writer.Heartbeat();
  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kLive);
}

void TestStaleFrameWatchdog() {
  std::printf("a frozen frame becomes stale even while the host lives (§14)\n");
  const std::string name = UniqueName("stale");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x55);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  meo::detail::Mapping poke;
  CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
  auto* bytes = static_cast<uint8_t*>(poke.data());

  uint32_t latest = 0;
  std::memcpy(&latest, bytes + kOffLatestSlot, sizeof(latest));
  const size_t ts = SlotOffset(latest) + kSlotTimestampOffset;

  uint64_t old = meo::MonotonicMillis() - (meo::kFrameStaleMs + 200);
  std::memcpy(bytes + ts, &old, sizeof(old));

  // The host is still heartbeating, so this is not producer-absent. The frame
  // itself is old, which is the frozen-face case §14 requires be caught.
  writer.Heartbeat();

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;
  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kStale);
  CHECK(info.age_ms > meo::kFrameStaleMs);
}

void TestTornWriteIsBoundedNotSpun() {
  std::printf("a slot left mid-write gives up instead of spinning (§9.2)\n");
  const std::string name = UniqueName("torn");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x66);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  meo::detail::Mapping poke;
  CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
  auto* bytes = static_cast<uint8_t*>(poke.data());

  uint32_t latest = 0;
  std::memcpy(&latest, bytes + kOffLatestSlot, sizeof(latest));
  const size_t seq_offset = SlotOffset(latest) + kSlotSeqOffset;

  uint64_t seq = 0;
  std::memcpy(&seq, bytes + seq_offset, sizeof(seq));
  const uint64_t odd = seq | 1ull;  // writer never finished
  std::memcpy(bytes + seq_offset, &odd, sizeof(odd));

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;

  const auto start = std::chrono::steady_clock::now();
  const meo::ReadStatus status =
      reader.ReadLatest(dest.data(), dest.size(), &info);
  const auto elapsed = std::chrono::steady_clock::now() - start;

  CHECK(status == meo::ReadStatus::kTorn);
  // The point is the bound. A filter running inside Zoom must return, not wait.
  CHECK(std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count() <
        50);

  // Restoring the counter restores the frame; the slot was never damaged.
  std::memcpy(bytes + seq_offset, &seq, sizeof(seq));
  CHECK(reader.ReadLatest(dest.data(), dest.size(), &info) ==
        meo::ReadStatus::kLive);
}

void TestMalformedHeadersAreRefused() {
  std::printf("malformed headers are refused, one field at a time\n");

  struct Corruption {
    const char* what;
    size_t offset;
    uint32_t value;
  };
  const Corruption corruptions[] = {
      {"wrong magic", kOffMagic, 0xDEADBEEF},
      {"zeroed magic", kOffMagic, 0},
      {"future layout version", kOffLayoutVersion, 99},
      {"absurd slot count", kOffSlotCount, 0xFFFFFFFF},
      {"zero slot count", kOffSlotCount, 0},
      {"latest slot out of range", kOffLatestSlot, 12345},
  };

  for (const auto& c : corruptions) {
    const std::string name = UniqueName("malformed");

    meo::FrameBridgeWriter writer;
    CHECK(writer.Create(name.c_str()));
    meo::FrameBridgeReader reader;
    CHECK(reader.Open(name.c_str()));

    TestFrame frame(0x77);
    CHECK(writer.PublishFrame(frame.pixels.data(),
                              static_cast<uint32_t>(frame.pixels.size()),
                              frame.Info()));

    meo::detail::Mapping poke;
    CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
    auto* bytes = static_cast<uint8_t*>(poke.data());
    std::memcpy(bytes + c.offset, &c.value, sizeof(c.value));

    std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
    meo::FrameInfo info;
    const meo::ReadStatus status =
        reader.ReadLatest(dest.data(), dest.size(), &info);
    if (status != meo::ReadStatus::kMalformed) {
      std::printf("  FAIL: %s gave %s, expected Malformed\n", c.what,
                  StatusName(status));
      ++g_failures;
    }
    ++g_checks;
  }
}

void TestFuzzedMappingNeverCrashes() {
  std::printf("a fuzzed mapping never crashes the reader (§13.1)\n");
  const std::string name = UniqueName("fuzz");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  TestFrame frame(0x88);
  CHECK(writer.PublishFrame(frame.pixels.data(),
                            static_cast<uint32_t>(frame.pixels.size()),
                            frame.Info()));

  meo::detail::Mapping poke;
  CHECK(poke.Open(name.c_str(), meo::BridgeMappingBytes()));
  auto* bytes = static_cast<uint8_t*>(poke.data());

  std::mt19937 rng(0xC0FFEE);
  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;

  // Only the header and the slot headers are mutated. That is where every
  // value the reader uses to compute an offset or size a copy lives; the
  // payload region is pure data and cannot steer a dereference.
  //
  // Each iteration starts from a pristine snapshot and injects one to three
  // faults. Mutating cumulatively instead would destroy the magic within the
  // first few iterations and spend the rest of the run re-testing that one
  // rejection, never reaching the geometry checks this exists to cover.
  std::vector<uint8_t> pristine_header(bytes, bytes + kHeaderBytes);
  std::vector<std::vector<uint8_t>> pristine_slots;
  for (uint32_t i = 0; i < meo::kSlotCount; ++i) {
    const uint8_t* slot = bytes + SlotOffset(i);
    pristine_slots.emplace_back(slot, slot + kSlotHeaderBytes);
  }

  auto restore = [&] {
    std::memcpy(bytes, pristine_header.data(), kHeaderBytes);
    for (uint32_t i = 0; i < meo::kSlotCount; ++i) {
      std::memcpy(bytes + SlotOffset(i), pristine_slots[i].data(),
                  kSlotHeaderBytes);
    }
  };

  int accepted = 0;
  for (int iteration = 0; iteration < 20000; ++iteration) {
    restore();

    const int faults = 1 + static_cast<int>(rng() % 3);
    for (int f = 0; f < faults; ++f) {
      const size_t target =
          (rng() % 2 == 0)
              ? rng() % kHeaderBytes
              : SlotOffset(rng() % meo::kSlotCount) + (rng() % kSlotHeaderBytes);
      bytes[target] = static_cast<uint8_t>(rng() & 0xFF);
    }

    const meo::ReadStatus status =
        reader.ReadLatest(dest.data(), dest.size(), &info);

    // The only requirement is that it returns, and returns something valid. A
    // crash or a hang here is a crash or a hang inside a user's meeting app.
    switch (status) {
      case meo::ReadStatus::kLive:
      case meo::ReadStatus::kPaused:
      case meo::ReadStatus::kNoPhonePaired:
      case meo::ReadStatus::kPhoneOffline:
      case meo::ReadStatus::kReconnecting:
      case meo::ReadStatus::kProducerAbsent:
      case meo::ReadStatus::kStale:
      case meo::ReadStatus::kNotAttached:
      case meo::ReadStatus::kMalformed:
      case meo::ReadStatus::kTorn:
        break;
      default:
        CHECK(false);
        return;
    }

    // Whenever it does claim a live frame, the claim has to be internally
    // consistent — accepting a plausible-looking but bogus geometry is how a
    // reader gets tricked into reading past the end of a slot.
    if (status == meo::ReadStatus::kLive) {
      ++accepted;
      CHECK(info.payload_bytes > 0);
      CHECK(info.payload_bytes <= meo::kPayloadCapacityBytes);
      CHECK(info.width > 0 && info.width <= meo::kMaxWidth);
      CHECK(info.height > 0 && info.height <= meo::kMaxHeight);
      CHECK(info.stride_y >= info.width);
      CHECK(static_cast<uint64_t>(info.stride_y) * info.height +
                static_cast<uint64_t>(info.stride_y) * (info.height / 2) ==
            info.payload_bytes);
      if (g_failures > 0) return;
    }
  }

  std::printf("    survived 20000 mutations, %d still classed live\n", accepted);
}

void TestConcurrentWriterAndReaderNeverTear() {
  std::printf("a reader racing a writer never accepts a torn frame\n");
  const std::string name = UniqueName("race");

  meo::FrameBridgeWriter writer;
  CHECK(writer.Create(name.c_str()));
  meo::FrameBridgeReader reader;
  CHECK(reader.Open(name.c_str()));

  // 720p, so each copy is 1.4 MB and the race window is wide enough to matter.
  const uint32_t width = 1280, height = 720, stride = 1280;
  const uint32_t payload_bytes = stride * height + stride * (height / 2);

  std::atomic<bool> stop{false};
  std::atomic<uint64_t> published{0};

  std::thread producer([&] {
    std::vector<uint8_t> pixels(payload_bytes);
    meo::FrameInfo info;
    info.width = width;
    info.height = height;
    info.stride_y = stride;
    info.pixel_format = meo::PixelFormat::kNV12;

    uint64_t frame_id = 1;
    while (!stop.load(std::memory_order_relaxed)) {
      // Every byte of the frame encodes its own frame id, so a read that
      // straddles two publishes is detectable by inspection alone.
      std::memset(pixels.data(), static_cast<int>(frame_id & 0xFF),
                  pixels.size());
      if (writer.PublishFrame(pixels.data(), payload_bytes, info)) {
        published.fetch_add(1, std::memory_order_relaxed);
        ++frame_id;
      }
    }
  });

  std::vector<uint8_t> dest(meo::kPayloadCapacityBytes);
  meo::FrameInfo info;
  int reads = 0, live = 0, torn = 0, inconsistent = 0;

  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(1500);
  while (std::chrono::steady_clock::now() < deadline) {
    const meo::ReadStatus status =
        reader.ReadLatest(dest.data(), dest.size(), &info);
    ++reads;
    if (status == meo::ReadStatus::kTorn) {
      ++torn;
      continue;
    }
    if (status != meo::ReadStatus::kLive) continue;
    ++live;

    const uint8_t expected = static_cast<uint8_t>(info.frame_id & 0xFF);
    // Checking every byte, not a sample: a tear can land anywhere.
    for (uint32_t i = 0; i < info.payload_bytes; ++i) {
      if (dest[i] != expected) {
        ++inconsistent;
        break;
      }
    }
  }

  stop.store(true, std::memory_order_relaxed);
  producer.join();

  std::printf("    %llu published, %d reads, %d live, %d torn\n",
              static_cast<unsigned long long>(published.load()), reads, live,
              torn);

  // The one result that matters. A single inconsistent frame means the seqlock
  // is wrong, and a wrong seqlock shows up as corrupted video in a meeting.
  CHECK(inconsistent == 0);
  CHECK(live > 0);
  // Torn reads are legal but should be rare — the four-slot ring exists to
  // keep the writer from lapping a reader mid-copy.
  CHECK(torn < reads / 10);
}

}  // namespace

int main() {
  std::printf("Meo frame bridge tests\n\n");

  TestLayoutIsStable();
  TestPublishAndRead();
  TestReaderWithoutWriter();
  TestRingWrapAlwaysYieldsNewest();
  TestStatePublishDrawsSlates();
  TestPeekDoesNotNeedABuffer();
  TestWriterRejectsBadGeometry();
  TestBufferTooSmallIsNotACrash();
  TestProducerAbsentWhenHeartbeatGoesStale();
  TestStaleFrameWatchdog();
  TestTornWriteIsBoundedNotSpun();
  TestMalformedHeadersAreRefused();
  TestFuzzedMappingNeverCrashes();
  TestConcurrentWriterAndReaderNeverTear();

  std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
