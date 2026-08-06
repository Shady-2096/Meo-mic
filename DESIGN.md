# Meo Mic — desktop design system

Covers the macOS (SwiftUI) and Windows (CustomTkinter) apps. The Android app
keeps its own Compose theme; only the palette is shared.

## Direction contract

**THESIS.** Meo Mic answers one question — "is my phone's voice getting
through?" — and the window answers it in one glance, in words a caller
understands. It refuses the equipment-panel arrangement the app used to wear
(condensed uppercase wordmark, dBFS ruler with tick labels, monospace
readouts, a tracked eyebrow over every section), which dressed a two-control
utility as studio hardware.

**OWN-WORLD.** Catppuccin Mocha, re-roled so that chrome is achromatic and
saturated color appears only where it carries meaning: the voice bar and the
live dot. Near-black window, one raised card for the pairing step, hairlines
instead of boxes. Native UI type only — SF Pro on macOS, Segoe UI Variable on
Windows — in four sizes, sentence case throughout. No display face, no
monospace, no letter-spaced capitals.

**STORY.** Open it: a plain sentence tells you whether the phone is connected
and what to do next. Speak: the bar moves and names what it hears. Set the
output device once. Close it and forget it.

**FIRST VIEWPORT.** The status sentence at 22pt, with the state dot inline
beside it, is the largest and first thing on screen; the voice bar runs full
width beneath it. Below the fold of attention: the pairing card (only while
disconnected), the output device, volume, and a quiet footer. There is no
in-window wordmark and no status badge — the title bar already carries the
name, and the sentence already carries the state.

**FORM.** Single-column utility panel, ~420pt wide, fixed width. Chosen
directly from the brief rather than a concept roll: the brief pins the target
feel precisely, and Operate mode rewards earned familiarity over invention.

## Color

Catppuccin Mocha. Role names, not hex values, are what the code refers to.

| Role | Hex | Use |
|---|---|---|
| `window` | `#11111B` | window ground |
| `card` | `#1E1E2E` | raised card, control fill |
| `cardHover` | `#313244` | control hover |
| `border` | `#282839` | hairlines, card outline |
| `text` | `#CDD6F4` | primary type |
| `textSecondary` | `#A6ADC8` | supporting sentences |
| `textTertiary` | `#9399B2` | labels, captions, footer |
| `accent` | `#CBA6F7` | primary action, focus, brand mark |
| `live` | `#A6E3A1` | connected dot, healthy level |
| `warn` | `#F9E2AF` | level getting hot |
| `hot` | `#FAB387` | level near clipping, soft warnings |
| `error` | `#F38BA8` | errors, clipping |

Rules:

- Every text role clears 4.5:1 against both `window` and `card`. That is why
  the tertiary role is Overlay2 rather than the Overlay0 the old build used at
  3.4:1 — small labels are the text most likely to be read in a hurry.
- Chrome is achromatic. Saturated color means something is happening.
- Accent is for the primary action, focus rings, and the brand mark only. It is
  never a status color.
- Level color is a property of the whole bar, not of individual segments.

## Type

Native UI faces only. macOS: the system face (SF Pro), via
`.system(size:weight:)`. Windows: `Segoe UI Variable Text`, falling back to
`Segoe UI`.

| Step | macOS | Windows | Use |
|---|---|---|---|
| Status | 22 semibold | 19 bold | the one status sentence |
| Title | 15 semibold | 14 bold | card titles, app name |
| Body | 13 regular | 12 regular | supporting sentences, controls |
| Label | 11.5 medium | 11 regular | field labels, captions, footer |

Rules:

- Sentence case everywhere. No all-caps labels, no letter-spacing.
- Numbers that change in place (IP address, percentage) use the UI face's
  tabular figures — `.monospacedDigit()` on macOS — never a monospace family.
- One family per platform. No display/body pairing in a utility window.

## Space

4px base grid. Gutter 26 (macOS) / 22 (Windows). Between sections 22. Inside a
group 8–12. More space above a heading than below it.

Corner radius: 10 for cards, 8 for controls, full round for the voice bar and
status pill.

## The voice bar

The only piece of custom drawing in the app, and the only element allowed to
carry saturated color at rest.

- One continuous rounded track, full width, 10px (macOS) / 12px (Windows).
- Fill length follows level from −60 dBFS to 0, with meter ballistics kept from
  the previous build: instant attack, ~26 dB/s release, 1.1s peak hold. Those
  ballistics are what makes it readable; only their presentation changed.
- Fill color is chosen by the current level: `live` below −12, `warn` to −6,
  `hot` to −3, `error` above. One color at a time.
- No tick marks, no dB numbers, no segment gaps, no peak-hold marker.
- A plain-language caption sits under it: "Sounds good", "Very quiet",
  "Too loud — turn the volume down on your phone".

## States

Every control ships default, hover, focus, disabled. Beyond that the window has
two shapes:

- **Waiting.** Status sentence "Waiting for your phone", pairing card visible
  with the address, copy, and QR.
- **Live.** Status sentence names the phone, pairing card is hidden, the voice
  bar and its caption carry the window.

Errors appear inline where they happen, in `error`, naming the problem and the
recovery. Never a modal for something the window can say itself.

## Motion

150–250ms, and only to convey state: the status dot and status sentence
crossfade on connect, the voice bar animates continuously while live, the
pairing card collapses when the phone connects. Nothing else moves.

## Prohibitions

These describe what this product refuses, and each one is a device the previous
build actually used:

- Letter-spaced uppercase section labels.
- Monospace type as a signal of technicality.
- Calibrated scales, tick marks, or dB readouts in the main window.
- A condensed or otherwise "industrial" display face.
- Telemetry (buffer depth, drift, packet counts) presented as a normal readout.
  Surface a problem when there is one, in a sentence, and stay quiet otherwise.
