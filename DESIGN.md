# Meo Mic — macOS design system

Covers the macOS (SwiftUI) app. The Windows (CustomTkinter) and Android
(Compose) apps keep Catppuccin Mocha; **the Mac app no longer shares a palette
with them**, and that is deliberate — see Color.

## Direction contract

**THESIS.** Meo Mic is a Mac utility you park in a corner during a call, so it
is built as one: a compact vibrant panel that answers "is my voice getting
through" with a status line and a living waveform, and hides everything else
behind two rows. It refuses three arrangements this app has actually shipped —
the studio-equipment panel (dBFS ruler, monospace readouts, tracked capitals),
the humane-minimal column of sentences that replaced it, and the airport-signage
build that replaced that one, which was distinctive but bulky, too wide, and
spent its largest element diagramming a path that only matters when it breaks.

**OWN-WORLD.** The platform's own. `NSVisualEffectView` behind-window vibrancy
running to all four edges under a hidden title bar; one inset grouped card with
hairline separators; AppKit semantic colours throughout, so the window follows
the system appearance and the user's own accent colour. No brand palette, no
custom control shapes, no invented affordances. Craft bar: Raycast, CleanShot X,
Bartender.

**STORY.** Open it: one line tells you whether the phone is through. Speak: the
waveform moves. Set the output device once. Close it and forget it.

**FIRST VIEWPORT.** A 30pt status glyph and the status line at title2, the
supporting fact beneath it at subheadline. Under that, either the waveform (live)
or the address field with copy and QR buttons (waiting) — never both, because
only one of them is ever the task. Then the grouped card: Output, Volume. A
footer link opens setup.

**FORM.** Single-column utility panel, 360pt wide, fixed width, hidden title
bar. Chosen directly by the user against a named craft bar rather than by a
concept roll: this is the category standard played straight, and Operate mode
rewards earned familiarity over invention.

## Color

Platform colours, not brand colours. Everything resolves through AppKit
semantic colours or through `primary` at an opacity, so light and dark both
work with one definition and the user's accent colour, increased-contrast
setting, and wallpaper tinting all carry through.

A hand-rolled dark-only palette is the most reliable tell that an app is not
really a Mac app. That is why Catppuccin Mocha, which the Windows and Android
apps still use, stops at the Mac boundary.

| Role | Source | Use |
|---|---|---|
| `label` | `.labelColor` | primary type |
| `secondary` | `.secondaryLabelColor` | supporting sentences, captions |
| `tertiary` | `.tertiaryLabelColor` | hints, idle waveform |
| `groupFill` | `primary` @ 4.5% | inset card fill |
| `groupStroke` | `primary` @ 9% | card hairline |
| `separator` | `primary` @ 8% | row separators |
| `controlFill` | `primary` @ 6% | icon-button hover, step chips |
| `accent` | `.accentColor` | the live waveform, controls, selection |
| `live` | `.systemGreen` | connected status glyph |
| `warning` | `.systemOrange` | clipping, unstable link, broken route |
| `error` | `.systemRed` | errors |

Rules:

- Surfaces are opacities on `primary`, never fixed greys. An opaque card on a
  vibrant window reads as a rectangle pasted onto a blurred photo.
- The accent is the user's, not ours. Never hard-code a brand hue for a control.
- Colour appears only where it carries state. Chrome is achromatic.

## Type

The system face at native text styles — `.title2`, `.title3`, `.body`,
`.subheadline`, `.caption` — never fixed point sizes, so the window tracks the
user's text-size setting and stays optically correct in both appearances.

| Step | Style | Use |
|---|---|---|
| Status | title2 semibold | the one status line |
| Address | title3 medium, tabular | the address while waiting |
| Row | body | row labels |
| Supporting | subheadline | the line under the status |
| Caption | caption | hints, meter caption, footer |

Sentence case for prose; **Title Case for buttons and sheet titles**, which is
the platform convention and the one place this differs from the app's other
platforms.

## Space

Window 360pt fixed. Gutter 20. Between blocks 18. Inside a group 6–8. Top inset
40 to clear the traffic lights, which float over the content once the title bar
is hidden. Row padding 12 × 9.

Corner radius: 10 for the grouped card, 6 for controls. Two values.

## The waveform

The only drawn element, and the reason the window feels alive rather than
reported-on.

- A rolling ~2s window of levels — 58 samples at 30Hz, oldest first — drawn as
  3pt capsules with 2pt gaps, mirrored around the centre line.
- Ballistics carried forward unchanged through every redesign: instant attack,
  ~26 dB/s release. They are what makes a level readable.
- Older samples fade to 35% opacity, so the newest edge reads as the present
  without a playhead.
- Silence is a 2pt hairline, not an empty box: at rest it should still look
  like something that is switched on.
- Tinted `accent`, switching to `warning` above −3 dBFS.
- No tick marks, no dB numbers, no scale. A plain-language caption sits under
  it: "Sounds good", "Very quiet — say something", "Too loud — turn it down on
  your phone".

## States

- **Waiting.** Status glyph is a secondary antenna, the address sits in the
  grouped field with copy and QR buttons. No waveform — there is nothing to
  meter, and a dead meter is noise.
- **Live.** Glyph turns green, the waveform replaces the address field.

Problems are inline lines with a symbol, in the flow, where they happen: a
broken audio route sits under the card, an unstable link and errors sit in the
footer. Never a banner, never a modal for something a line can say.

## Motion

150–250ms, and only to convey state. The waveform animates continuously at
70ms linear while live; the panel crossfades between waiting and live at 220ms.
Nothing else moves — no hover choreography, no load sequence.

## Prohibitions

Each is a device one of this app's builds actually used.

- A brand palette on the Mac. It costs light mode and the user's accent colour,
  and buys nothing the platform did not already provide.
- Dark-only. Follow the system appearance.
- Letter-spaced uppercase section labels; monospace as a signal of technicality.
- Calibrated scales, tick marks, or dB readouts.
- Telemetry — buffer depth, drift, packet counts — as a normal readout. Say
  something when there is a problem; stay quiet otherwise.
- Diagramming the audio path. The route is only interesting when it is broken,
  and then it is one line of text, not a permanent illustration.
- Custom-drawn substitutes for controls the platform already ships.
