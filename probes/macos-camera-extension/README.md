# macOS camera-extension probe

Throwaway feasibility code for `CAMERA_BUILD_PLAN.md` §18 step 2. It answers
one question: **can a Core Media I/O camera extension be installed and used on
a stock Mac with a free Apple ID — no paid Developer Program, no notarization,
SIP left alone?**

§8.1 says that answer decides whether the macOS path is viable at all, which
is why it runs before any macOS product work.

## It has already been run

See [`RESULTS-2026-08-07.md`](RESULTS-2026-08-07.md). Short version: **no.**

- Ad-hoc signature that claims `com.apple.developer.system-extension.install`
  → the app is **SIGKILLed at launch** by AMFI. It never runs.
- Ad-hoc signature without it → runs, and activation fails with
  `OSSystemExtensionErrorDomain code 2 — Missing entitlement`.
- `systemextensionsctl developer on`, which §8.1 treats as the free way
  around this, **refuses to run while SIP is enabled** on macOS 26.5.1.

So on current macOS the free path costs the user a Recovery-mode reboot and a
disabled System Integrity Protection. That is a materially different ask from
Meo Mic's "click past Gatekeeper once", and the plan should say so.

Re-run it on a new macOS release before trusting it again — Apple's message
says the developer-mode limitation "will be removed in the near future", and
if that happens the verdict changes.

## What is here

```
Extension/main.swift     CMIO provider: one 1280x720 NV12 stream of colour bars
Host/main.swift          SwiftUI app that requests activation and reports back
build.sh                 assembles + signs both bundles by hand
install.sh               copies to /Applications and launches
uninstall.sh             removes both
```

Bundles are assembled by hand rather than with an `.xcodeproj` deliberately.
The question is what happens with *no* signing identity, and an Xcode project
silently adopts whatever team the machine has — which is the one variable the
probe exists to control. Here every signing decision is one visible line in
`build.sh`.

## Running it

```bash
./build.sh              # ad-hoc (the zero-budget case)
./install.sh            # /Applications is mandatory; see below
```

Then press **Install extension** and read the log pane.

For a result you can paste into a document rather than screenshot:

```bash
"build/Meo Camera Probe.app/Contents/MacOS/MeoCameraProbe" --cli-install
```

To test the other half of the §8.1 question, with an Apple ID signed into
Xcode:

```bash
security find-identity -v -p codesigning     # find the name
./build.sh "Apple Development: you@example.com (XXXXXXXXXX)"
```

### Why `/Applications` is not optional

macOS refuses to install a system extension from an app anywhere else, failing
with `unsupportedParentBundleLocation`. Running straight out of `./build` is
the most common way to get a refusal that has nothing to do with signing. The
probe rules this out explicitly — see result §3 — so it cannot be mistaken for
the cause.

## What a working extension looks like

Colour bars with a white line sweeping across every two seconds.

The sweep is the point. Live bars and frozen bars are identical to look at,
and §14 lists "stale frozen image mistaken for live" as a threat the product
must design against. Bars that are not moving mean frames stopped — a failure,
not a pass.

## Watching what the system thinks

```bash
systemextensionsctl list
log stream --predicate 'subsystem == "com.meo.camera.probe.extension"'
```

The extension runs in its own process, so its `os_log` output is the only way
to see inside it.

## Cleaning up

```bash
./uninstall.sh
```

Deactivation goes through the app, because `systemextensionsctl uninstall`
wants a team identifier that an ad-hoc build does not have. If nothing ever
installed — the current situation — there is nothing to clean beyond deleting
the copy in `/Applications`.

## What it is not

No network, no phone, no decode, no frame bridge, no privacy slate. It draws
colour bars. Every omission is deliberate: if the extension will not install,
nothing about video can be the reason, because there is no video code here.

None of the frame path has been verified, because the extension has never
loaded. NV12 layout, timing, and consumer visibility are all still open.
