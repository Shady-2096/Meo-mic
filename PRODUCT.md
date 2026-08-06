# Meo Mic — product truth

## What it is

Meo Mic turns an Android phone into a wireless microphone for a Windows or
macOS computer. The phone captures audio and streams it over the local network
as UDP; the desktop app writes it into a virtual audio device, which call and
recording apps then read as if it were a real microphone.

Free, open source, ad-free, no account, local network only.

## Who uses it

Someone about to join a Discord/Zoom/Meet call, record, or stream, who does not
own a decent USB microphone but does own a phone with a good one. Not an audio
engineer. They do not know what dBFS is and should never need to.

## The one question the desktop app answers

**"Is my phone's voice actually reaching the app I'm calling from?"**

Everything else on the window is set once and forgotten: which virtual device to
write into, and how loud. The app is opened, glanced at, and left alone in a
corner of the screen for the length of a call.

## Jobs, in the order they happen

1. Install the virtual audio device (one-click, first run only).
2. Pair the phone — auto-discovery, QR scan, or typing an IP.
3. Confirm voice is arriving (the glance).
4. Pick the virtual device as the microphone in the call app.
5. Adjust volume if too quiet or too loud.

## Constraints

- **Zero recurring cost.** No paid signing certificates, no hosted services.
  The macOS app is ad-hoc signed and will not be notarized.
- **Local network only.** No relay, no remote viewing, no telemetry.
- **Single maintainer**, limited coding experience, heavy AI assistance. Code
  and design must stay legible and conventional enough to be maintained.
- **Three platforms share one identity**: Android (Compose), Windows
  (CustomTkinter), macOS (SwiftUI). The desktop apps must read as the same
  product as the phone app.

## Brand commitments

- Catppuccin Mocha is the palette across all three apps. Kept.
- Dark interface. Chosen from the use scene, not from category habit: the
  window sits beside a call or streaming app, usually dark, often in a dim
  room at night, and its job is to be glanceable in peripheral vision.
- The app name is "Meo Mic", set in sentence case.

## Assumptions (inferred, not confirmed)

The maintainer asked for this redesign without an interview, so the following
are inferred from their brief and from the code, and should be corrected if
wrong:

- The audience skews non-technical; the previous instrument-panel styling
  (dBFS ruler, monospace readouts, tracked uppercase labels) was read as
  performative rather than informative.
- "Professional" here means calm and credible, not corporate or bland.
- Desktop parity matters more than platform-idiomatic divergence: the Windows
  and macOS windows should be recognizably the same design, while still using
  each platform's own type and controls.
