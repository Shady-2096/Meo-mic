# Windows virtual-camera probes

Throwaway feasibility code for `CAMERA_BUILD_PLAN.md` §18 steps 1 and 3. It is
not product code and must not grow into any. Its whole job is to answer three
questions that decide how big the Windows half of Meo Camera is.

| # | Question | Plan | Decides |
|---|---|---|---|
| 1 | Which apps can see a virtual camera that exists **only** as a Media Foundation source? | §18.1, §9.1 | Whether the DirectShow backend (§9.5) is mandatory or optional |
| 2 | What is the **exact** name Windows shows for it? | §1.1 | What the README and screenshots are allowed to claim |
| 3 | Can the frame server activate a source registered only under `HKCU`? | §18.3, §9.4 | Whether install needs a UAC prompt |

Question 1 is the expensive one. If Zoom and OBS cannot see an MF-only camera,
then §9.2's in-process DirectShow filter — the highest-blast-radius code in the
whole project, the thing that can crash a user's meeting — is unavoidable work,
and the Windows estimate roughly doubles. **Do not skip it and do not guess it.**

## What this is not

No network, no phone, no decode, no frame bridge, no privacy slate, no error
recovery. It draws colour bars. Every one of those omissions is deliberate: if
an application cannot see this camera, the cause cannot be anything Meo is
doing with video, because Meo is not doing anything with video here.

## Requirements

- **Windows 11** (build 22000+) for the full result. `MFCreateVirtualCamera`
  does not exist on Windows 10 — the host is written to say so clearly and
  exit rather than look broken. A Windows 10 run is still worth recording,
  because "MF is unavailable here" is itself part of the §9.1 answer.
- Visual Studio 2022 with **Desktop development with C++** (brings CMake and
  the Windows SDK).
- A webcam is *not* required.

## Running it

```powershell
cd probes\windows-virtual-camera
.\scripts\build.ps1
```

Then, in this order — the order matters, because trying `HKLM` first destroys
the Probe 3 result:

```powershell
# 1. Per-user registration. Should NOT prompt for UAC.
.\scripts\register-hkcu.ps1

# 2. Start the camera and leave the window open.
.\build\out\MeoProbeHost.exe
```

If the host prints `Virtual camera STARTED`, HKCU was enough — that is the
Probe 3 answer, and it is the good outcome. If `Start()` fails, close the host
and try the machine-wide path:

```powershell
.\scripts\unregister.ps1
.\scripts\register-hklm.ps1     # this one does prompt for UAC, by design
.\build\out\MeoProbeHost.exe
```

While the host is running, walk the application list in
`RESULTS-TEMPLATE.md` and fill it in. When you are finished:

```powershell
.\scripts\unregister.ps1
```

## What a working camera looks like

Colour bars with a **white vertical line sweeping left to right, once every two
seconds**.

The sweep is the whole point. A still frame of colour bars and a frozen frame
of colour bars look identical, and §14 lists "stale frozen image mistaken for
live" as a threat the product must design against. If the bars are there but
the line is not moving, frames stopped — record that as a failure, not a pass.

Skewed diagonal bars mean a stride mismatch. Note it; it is a real bug in the
probe's frame writer rather than an enumeration finding.

## Reading a failure

| Symptom | Most likely cause |
|---|---|
| `MFCreateVirtualCamera` returns `E_ACCESSDENIED` | Windows camera privacy setting is denying access. §9.4 requires this to become an actionable message in the product, so record it and fix the setting. |
| `MFCreateVirtualCamera` fails to resolve at all | Windows 10. Expected; record the OS build. |
| Create succeeds, `Start()` fails | The frame server could not activate the CLSID. This is the Probe 3 negative result — check which hive the DLL is in. |
| Camera appears, frames are black | The source activated but is not delivering samples. Attach DebugView to see the probe's `[MeoProbe]` lines from inside the frame server process. |
| Camera does not appear in one specific app | The interesting case. That app is not using the frame server, which is the §9.1 finding the whole probe exists to produce. |

`DebugView` (Sysinternals) run **as administrator** with *Capture Global Win32*
enabled is the only way to see the DLL's log lines, because it runs inside the
frame server's process and not in your console.

## Cleaning up

`.\scripts\unregister.ps1` removes both hives and any system-lifetime camera.
The default lifetime is `session`, so a camera created by a plain run
disappears when the host exits and leaves nothing behind.

## Then what

Paste the filled-in `RESULTS-TEMPLATE.md` back. It feeds:

- `adr/0002-directshow-scope.md` — mandatory, optional, or unnecessary
- `adr/0003-windows-registration-scope.md` — `HKCU` or `HKLM`
- the §13.2 compatibility matrix's "Capture API observed" column
- the real device-name strings the §16.1 honesty requirements demand
