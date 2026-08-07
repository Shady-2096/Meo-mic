# ADR 0004 — macOS Camera cannot be distributed under the zero-budget constraint

- **Status:** Accepted
- **Date:** 2026-08-07
- **Plan:** §8.1, §16, §18 step 2, §19
- **Evidence:** [`probes/macos-camera-extension/RESULTS-2026-08-07.md`](../probes/macos-camera-extension/RESULTS-2026-08-07.md)

## Context

§8.1 states the entitlement problem and then proposes a way to live with it:

> **Primary path:** clone, build in Xcode with an ad-hoc or personal-team
> signature, `systemextensionsctl developer on`, install, use.

§18 step 2 required this to be measured before any macOS product work, on the
grounds that the answer decides whether the macOS path is viable at all. It
has now been measured on macOS 26.5.1 with Xcode 26.6, SIP enabled, and no
code-signing identity on the machine.

## What was measured

1. An ad-hoc-signed app that **claims**
   `com.apple.developer.system-extension.install` is **SIGKILLed at launch**
   (exit 137). It does not fail to install; it does not run.
2. The same app without that entitlement runs, and activation fails with
   `OSSystemExtensionErrorDomain` code 2, `missingEntitlement`.
3. `/Applications` is not the confounder. Verified from `/Applications` with
   the signature re-checked in place: identical failure.
4. **`systemextensionsctl developer on` refuses to run while SIP is enabled.**
   Its exact response: *"At this time, this tool cannot be used if System
   Integrity Protection is enabled."*

Point 4 is the one the plan did not anticipate, and it is the one that
matters.

## Decision

**The macOS camera receiver is blocked, not cancelled.** §8.1's primary path
does not exist on current macOS, and the plan's claim that it does is retired.

Specifically:

- Meo will **not** ask users to disable System Integrity Protection. It is
  free, and it does work, and it is the wrong thing to ask. A project whose
  pitch is privacy and local-only operation cannot reasonably instruct people
  to turn off a core OS security control so they can use a webcam. That is a
  larger ask than Meo Mic's one-time Gatekeeper click, and it is not the same
  kind of friction.
- Meo will **not** buy a Developer Program membership. That is C1, and C1 is
  an input, not a preference.
- The macOS camera extension code stays in the repository as a probe. It is
  not deleted, and it is not built on.
- macOS Camera ships when Apple's developer-mode restriction lifts, or never.
  Apple's own message says the limitation "will be removed in the near
  future"; that is worth re-testing on each macOS release and worth nothing
  as a plan.

## Consequences

- §8.1 and §16 of the plan are now wrong where they promise a working
  build-from-source macOS path. §16.1's honesty requirements apply to the plan
  as much as to the README, so those sections need correcting.
- Milestone 5's "pick whichever platform Milestone 0 showed the clearer path
  for" is decided by elimination. See [ADR 0005](0005-first-desktop-platform.md).
- The macOS frame-bridge ADR (§8.3) is deferred. Specifying a bridge into an
  extension that cannot be installed is work with no way to be validated.
- The §13.2 compatibility matrix loses every macOS row for v1. Those are not
  failures to record; they are untestable.
- **Meo Mic is unaffected.** It ships an unsigned app with no system
  extension, and none of this touches it.

## What would reverse this

Any one of these, in order of likelihood:

1. Apple restores `systemextensionsctl developer on` under SIP. Re-run the
   probe on each macOS release; it is two commands.
2. A free personal team turns out to be able to carry the entitlement. Not yet
   tested — this machine has no Apple ID in Xcode. Expected to fail, but it is
   one command and it is the last free option, so it should be measured rather
   than assumed. **This is the one open action on this ADR.**
3. The budget constraint changes. If a paid account ever appears, §8.1 is
   right that only signing configuration and the release job change — so keep
   signing settings in one place.
