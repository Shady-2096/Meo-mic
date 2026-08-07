# ADR 0005 — Windows is the first desktop platform

- **Status:** Accepted
- **Date:** 2026-08-07
- **Plan:** §12 Milestone 5, §19
- **Depends on:** [ADR 0004](0004-macos-distribution-reality.md)

## Context

§12's Milestone 5 says to "pick whichever platform Milestone 0 showed the
clearer path for, and finish it completely", on the reasoning that porting the
second platform is far cheaper once the frame bridge and slate semantics have
survived contact with real meeting apps. §19 lists the choice as a decision to
lock after Milestone 0.

## Decision

**Windows.**

This is not a judgement that Windows looked easier. It is elimination. ADR
0004 measured that macOS cannot install a camera extension at all under
constraint C1 on current macOS, so there is no macOS path to finish. Windows
is the only desktop platform where Milestone 5 can be attempted.

## Consequences

- Milestone 5 targets the Windows Media Foundation backend end to end:
  install, camera visible in real apps, controls, slate, repair, upgrade,
  uninstall.
- Milestone 6's "second and third desktop backends" loses its macOS half for
  now. What remains is the DirectShow backend, scoped by
  [ADR 0002](0002-directshow-scope.md).
- The frame bridge (§9.3) is designed against Windows first. It should still
  be specified in a way that does not bake in Windows assumptions, because the
  macOS side may unblock later — but the plan's hope of learning the
  frame-bridge lessons once and porting them is now sequenced Windows → macOS
  rather than the other way round.
- Meo Mic's macOS client keeps shipping. It is unaffected by any of this.
- §17's release ladder needs its "all three OSes" wording in the public-alpha
  rung revisited. It already hedges with "at whatever coverage the Milestone 0
  probes justified", which turns out to have been the right hedge.

## Risk this accepts

The plan's §5.1 network design — desktop dials out, phone listens — was
motivated primarily by avoiding a Windows Defender Firewall prompt. Building
Windows first means that design gets validated on the platform it was designed
for, which is good. But it also means the Android sender's listener behaviour
will be tuned against exactly one desktop client, and cross-platform
assumptions will not be tested until much later. Worth remembering when macOS
unblocks: the second platform will find bugs the first one hid.
