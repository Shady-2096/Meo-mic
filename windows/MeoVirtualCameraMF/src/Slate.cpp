#include "Slate.h"

#include <cstring>

namespace meo {
namespace {

// A 5x7 bitmap font, one byte per row, bit 4 leftmost. Uppercase only, because
// every string this renders is a short status line and dropping lowercase
// halves the table. Unmapped characters render as blank rather than as a
// missing-glyph box — a stray character should not draw attention to itself on
// a screen the user is already confused by.
struct Glyph {
  char code;
  uint8_t rows[7];
};

constexpr Glyph kFont[] = {
    {' ', {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}},
    {'A', {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}},
    {'B', {0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E}},
    {'C', {0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E}},
    {'D', {0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E}},
    {'E', {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F}},
    {'F', {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}},
    {'G', {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F}},
    {'H', {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}},
    {'I', {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E}},
    {'J', {0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C}},
    {'K', {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11}},
    {'L', {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F}},
    {'M', {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11}},
    {'N', {0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11}},
    {'O', {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}},
    {'P', {0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10}},
    {'Q', {0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D}},
    {'R', {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11}},
    {'S', {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}},
    {'T', {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04}},
    {'U', {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}},
    {'V', {0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04}},
    {'W', {0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11}},
    {'X', {0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11}},
    {'Y', {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04}},
    {'Z', {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F}},
    {'0', {0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E}},
    {'1', {0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E}},
    {'2', {0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F}},
    {'3', {0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E}},
    {'4', {0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02}},
    {'5', {0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E}},
    {'6', {0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E}},
    {'7', {0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08}},
    {'8', {0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E}},
    {'9', {0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C}},
    {'.', {0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C}},
    {',', {0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08}},
    {'-', {0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x00}},
    {':', {0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00}},
    {'?', {0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04}},
    {'!', {0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04}},
    {'/', {0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10}},
    {'\'', {0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00}},
};

constexpr uint32_t kGlyphWidth = 5;
constexpr uint32_t kGlyphHeight = 7;
constexpr uint32_t kGlyphAdvance = 6;  // one column of tracking

const uint8_t* FindGlyph(char c) {
  if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
  for (const Glyph& g : kFont) {
    if (g.code == c) return g.rows;
  }
  return nullptr;
}

// BT.601 studio-swing YUV, which is what §5.4's NV12 pipeline carries.
struct Color {
  uint8_t y, u, v;
};

struct Palette {
  Color background;
  uint8_t text_luma;
  bool animated;
};

Palette PaletteFor(ReadStatus status) {
  switch (status) {
    case ReadStatus::kPaused:
      // Deep amber. §6.5 requires pausing to be unmistakable, so this is the
      // one slate that is deliberately loud.
      return {{90, 60, 175}, 235, false};
    case ReadStatus::kReconnecting:
      // Transient and self-resolving, so it animates.
      return {{70, 130, 130}, 225, true};
    case ReadStatus::kPhoneOffline:
    case ReadStatus::kStale:
      return {{58, 128, 128}, 220, false};
    case ReadStatus::kNoPhonePaired:
      return {{50, 128, 128}, 215, false};
    case ReadStatus::kProducerAbsent:
    case ReadStatus::kNotAttached:
      // Near-black. The host is gone; the camera should look inert, not busy.
      return {{32, 128, 128}, 200, false};
    case ReadStatus::kMalformed:
    case ReadStatus::kTorn:
    case ReadStatus::kLive:
    default:
      return {{40, 128, 128}, 210, false};
  }
}

uint32_t TextWidth(const char* text, uint32_t scale) {
  uint32_t chars = 0;
  for (const char* p = text; *p != '\0'; ++p) ++chars;
  if (chars == 0) return 0;
  // No tracking after the final glyph.
  return (chars * kGlyphAdvance - 1) * scale;
}

// Draws `text` into the luma plane only. Chroma is left at the background,
// giving neutral text over a tinted field — which avoids a second plane's
// worth of subsampling arithmetic for no visible benefit at this size.
void DrawText(uint8_t* luma, uint32_t width, uint32_t height, uint32_t stride,
              const char* text, int32_t origin_x, int32_t origin_y,
              uint32_t scale, uint8_t value) {
  int32_t pen_x = origin_x;
  for (const char* p = text; *p != '\0'; ++p) {
    const uint8_t* rows = FindGlyph(*p);
    if (rows != nullptr) {
      for (uint32_t gy = 0; gy < kGlyphHeight; ++gy) {
        const uint8_t bits = rows[gy];
        for (uint32_t gx = 0; gx < kGlyphWidth; ++gx) {
          if ((bits & (1u << (kGlyphWidth - 1 - gx))) == 0) continue;
          // Expand one font pixel into a scale x scale block.
          for (uint32_t sy = 0; sy < scale; ++sy) {
            const int64_t py = origin_y + static_cast<int64_t>(gy) * scale + sy;
            if (py < 0 || py >= height) continue;
            for (uint32_t sx = 0; sx < scale; ++sx) {
              const int64_t px = pen_x + static_cast<int64_t>(gx) * scale + sx;
              if (px < 0 || px >= width) continue;
              luma[py * stride + px] = value;
            }
          }
        }
      }
    }
    pen_x += static_cast<int32_t>(kGlyphAdvance * scale);
  }
}

}  // namespace

const char* SlateMessage(ReadStatus status) {
  switch (status) {
    case ReadStatus::kPaused:            return "PAUSED";
    case ReadStatus::kReconnecting:      return "RECONNECTING";
    case ReadStatus::kPhoneOffline:      return "PHONE OFFLINE";
    case ReadStatus::kNoPhonePaired:     return "NO PHONE PAIRED";
    case ReadStatus::kStale:             return "NO SIGNAL";
    case ReadStatus::kProducerAbsent:    return "MEO IS NOT RUNNING";
    case ReadStatus::kNotAttached:       return "MEO IS NOT RUNNING";
    case ReadStatus::kMalformed:
    case ReadStatus::kTorn:              return "MEO CAMERA ERROR";
    case ReadStatus::kLive:              return "MEO CAMERA";
  }
  return "MEO CAMERA";
}

const char* SlateHint(ReadStatus status) {
  switch (status) {
    case ReadStatus::kPaused:         return "RESUME FROM THE MEO APP OR YOUR PHONE";
    case ReadStatus::kReconnecting:   return "REJOINING THE NETWORK";
    case ReadStatus::kPhoneOffline:   return "CHECK THE PHONE IS ON THE SAME NETWORK";
    case ReadStatus::kNoPhonePaired:  return "SCAN THE QR CODE IN THE MEO APP";
    case ReadStatus::kStale:          return "WAITING FOR VIDEO FROM THE PHONE";
    case ReadStatus::kProducerAbsent:
    case ReadStatus::kNotAttached:    return "START MEO ON THIS COMPUTER";
    case ReadStatus::kMalformed:
    case ReadStatus::kTorn:           return "RESTART MEO ON THIS COMPUTER";
    case ReadStatus::kLive:           return nullptr;
  }
  return nullptr;
}

bool RenderSlate(ReadStatus status, uint8_t* dest, uint32_t width,
                 uint32_t height, uint32_t stride, uint64_t tick) {
  if (dest == nullptr) return false;
  if (width == 0 || height == 0) return false;
  if ((width % 2) != 0 || (height % 2) != 0) return false;
  if (stride < width) return false;
  if (width > kMaxWidth || height > kMaxHeight) return false;

  const Palette palette = PaletteFor(status);

  // Y plane.
  for (uint32_t y = 0; y < height; ++y) {
    std::memset(dest + static_cast<size_t>(y) * stride, palette.background.y,
                width);
  }
  // UV plane: half height, interleaved U,V per 2x2 luma block.
  uint8_t* chroma = dest + static_cast<size_t>(stride) * height;
  for (uint32_t y = 0; y < height / 2; ++y) {
    uint8_t* row = chroma + static_cast<size_t>(y) * stride;
    for (uint32_t x = 0; x < width; x += 2) {
      row[x] = palette.background.u;
      row[x + 1] = palette.background.v;
    }
  }

  // Scale the headline to roughly 70% of the frame width, so the same code
  // reads correctly at 480p and at 1080p without per-format tuning.
  const char* headline = SlateMessage(status);
  uint32_t scale = 1;
  while (TextWidth(headline, scale + 1) <= (width * 7) / 10 &&
         (kGlyphHeight * (scale + 1)) <= height / 6) {
    ++scale;
  }

  const uint32_t headline_width = TextWidth(headline, scale);
  const int32_t headline_x =
      static_cast<int32_t>(width / 2) - static_cast<int32_t>(headline_width / 2);
  const int32_t headline_y = static_cast<int32_t>(height / 2) -
                             static_cast<int32_t>(kGlyphHeight * scale);
  DrawText(dest, width, height, stride, headline, headline_x, headline_y, scale,
           palette.text_luma);

  const char* hint = SlateHint(status);
  if (hint != nullptr) {
    // Roughly half the headline, never smaller than 1.
    const uint32_t hint_scale = scale > 2 ? scale / 2 : 1;
    const uint32_t hint_width = TextWidth(hint, hint_scale);
    if (hint_width < width) {
      const int32_t hint_x = static_cast<int32_t>(width / 2) -
                             static_cast<int32_t>(hint_width / 2);
      const int32_t hint_y =
          headline_y + static_cast<int32_t>(kGlyphHeight * scale) +
          static_cast<int32_t>(kGlyphHeight * scale) / 2;
      DrawText(dest, width, height, stride, hint, hint_x, hint_y, hint_scale,
               static_cast<uint8_t>(palette.text_luma - 40));
    }
  }

  if (palette.animated) {
    // A sweep across the lower third. Only transient states get this: it says
    // "something is still happening", which would be a lie on a paused or
    // host-absent slate. It is also the only thing distinguishing this slate
    // from a frozen copy of itself, which §14 treats as a real hazard.
    const uint32_t bar_height = height / 60 > 2 ? height / 60 : 2;
    const uint32_t bar_width = width / 6;
    const uint32_t travel = width - bar_width;
    const uint32_t phase = static_cast<uint32_t>(tick % 120);
    // Ping-pong, so the bar never jumps discontinuously back to the start.
    const uint32_t position =
        phase < 60 ? (travel * phase) / 60 : (travel * (120 - phase)) / 60;
    const uint32_t bar_top = (height * 2) / 3;

    for (uint32_t y = bar_top; y < bar_top + bar_height && y < height; ++y) {
      uint8_t* row = dest + static_cast<size_t>(y) * stride;
      for (uint32_t x = position; x < position + bar_width && x < width; ++x) {
        row[x] = palette.text_luma;
      }
    }
  }

  return true;
}

}  // namespace meo
