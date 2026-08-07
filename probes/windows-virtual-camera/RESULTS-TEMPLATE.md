# Windows virtual-camera probe — results

Copy this file to `RESULTS-<date>.md`, fill it in while the probe host is
running, and commit it. Plan §11.2 and §16.1 both insist that claims come from
recorded measurements rather than memory, and this is where the Windows
measurements live.

Leave a row blank rather than guessing. A blank row is an unanswered question;
a guessed row is a wrong answer that survives into the README.

## Machine

| Field | Value |
|---|---|
| Windows edition | |
| Windows version (`winver`) | |
| OS build | |
| CPU / GPU | |
| Physical webcam present? | |
| Date of run | |

## Probe 3 — registration scope (§9.4)

| Step | Result |
|---|---|
| `register-hkcu.ps1` prompted for UAC? | yes / no |
| With **HKCU only**, `MFCreateVirtualCamera` returned | `S_OK` / HRESULT: |
| With **HKCU only**, `Start()` returned | `S_OK` / HRESULT: |
| With HKCU only, did any app show live frames? | yes / no |
| If HKCU failed — with **HKLM**, `Start()` returned | `S_OK` / HRESULT: |

**Conclusion:** Meo's Windows installer needs `HKLM` (one UAC prompt) / works
entirely per-user with no prompt. *(delete one)*

## §1.1 — the real device name

The plan says Windows appends its own suffix and there is no flag to suppress
it. Copy these character for character; do not tidy them up.

| Where | String |
|---|---|
| Name we requested | `Meo Camera Probe` |
| Name in the host's own `MFEnumDeviceSources` listing | |
| Name shown in the Windows **Camera** app | |
| Name shown in **Zoom** | |
| Name shown in **OBS** | |

If these differ from each other, that is a finding: the product cannot promise
one string, and §16.1 requires the docs to show the real ones.

## Probe 1 — which apps enumerate an MF-only virtual camera (§9.1)

For each app: does the camera appear, what does it show, and does it produce
**moving** frames (the sweep bar must travel, or it is not live).

| App | Version | Appears? | Live moving frames? | Notes |
|---|---|---|---|---|
| Windows Camera app | | | | frame server baseline — if this fails, everything below is meaningless |
| Zoom (desktop) | | | | |
| Discord (desktop) | | | | |
| Chrome → Google Meet | | | | |
| Chrome → `webrtc.github.io/samples/src/content/devices/input-output/` | | | | cheaper than joining a real meeting |
| Edge → Google Meet | | | | |
| Microsoft Teams (desktop) | | | | |
| OBS → **Video Capture Device** source | | | | classic source; historically DirectShow |
| OBS → **Video Capture Device (V2)** source | | | | if present — this one is the MF path |

### Extra checks per §13.2

| Check | Result |
|---|---|
| App opened **before** the probe host started — does it appear after a rescan? | |
| App opened **after** the probe host started | |
| Probe host force-killed mid-preview — does the app hang, crash, or show an error? | |
| Switching to another camera and back | |

That force-kill row matters more than it looks. §8.4 and §14 both require the
virtual camera to keep producing frames when no host process is alive, and
this probe deliberately does **not** do that. Recording how badly each app
behaves when the producer vanishes is what sizes that work.

## Conclusion for §9.1

Answer this in one sentence, because it sets the size of the Windows path:

> DirectShow is **mandatory / optional / unnecessary**, because
> _______________________ could not see the MF-only camera.

## Anything surprising

Free text. Crashes, delays before the camera appears, duplicate entries, names
that change between runs, apps that need a restart to notice the camera.
