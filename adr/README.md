# Architecture decision records

`CAMERA_BUILD_PLAN.md` §12 makes written ADRs part of the Milestone 0 exit
gate. This directory is that gate's evidence.

## The rule these follow

An ADR here is only marked **Accepted** when something was measured. A
decision reached by reading documentation, or by reasoning about what Apple
and Microsoft probably do, is marked **Blocked** with the experiment that
would settle it named. §11.2 puts it plainly: a target without a rig is not a
test, and the same applies to a decision without a measurement.

That is why several records below decide nothing yet. They are not drafts —
they are open questions with the cost of leaving them open written down.

## Status

| ADR | Subject | Status |
|---|---|---|
| [0001](0001-transport-and-control-plane.md) | WebRTC media plane, JSON control plane | Accepted (inherited), one sub-question open |
| [0002](0002-directshow-scope.md) | Is a DirectShow backend mandatory on Windows? | **Blocked** — needs the Windows probe run |
| [0003](0003-windows-registration-scope.md) | `HKCU` or `HKLM` for the MF source? | **Blocked** — needs the Windows probe run |
| [0004](0004-macos-distribution-reality.md) | How macOS Camera can be distributed with no paid account | **Accepted** — measured 2026-08-07 |
| [0005](0005-first-desktop-platform.md) | Which desktop platform finishes first | **Accepted** — follows from 0004 |

## Still owed before the Milestone 0 gate closes

§12 names these and none of them have been started, because each depends on a
probe that has not run:

- **WebRTC distribution and license.** Which prebuilt binary, from where,
  under what license, updated how. §5.2 requires the provenance recorded
  before anything ships.
- **Recording architecture.** Single shared encoder or a device-gated second
  one (§7.4). Depends on the dual-encoder spike, which needs real phones.
- **macOS frame bridge.** Exact IOSurface pool shape and wire layout (§8.3).
  Blocked behind ADR 0004 — there is no point specifying a bridge to an
  extension that cannot be installed.
- **Windows frame bridge.** Shared-texture or shared-memory layout read by
  both camera backends (§9.3). Needs ADR 0002 first, because the answer
  changes whether one reader or two must be supported.

## Format

Short. Context, decision, consequences, and — where it applies — what was
actually measured and when. If a record cannot say what evidence it rests on,
it is not ready to be Accepted.
