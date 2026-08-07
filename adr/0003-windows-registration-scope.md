# ADR 0003 — `HKCU` or `HKLM` for the Media Foundation source?

- **Status:** **Blocked.** Nothing is decided here yet.
- **Date opened:** 2026-08-07
- **Plan:** §9.4, §9.6, §18 step 3
- **Resolved by:** running [`probes/windows-virtual-camera`](../probes/windows-virtual-camera/), registering per-user first

## Context

The Windows frame server is a separate service running under a different
account from the user. Meo's media source is an in-process COM object the
frame server activates by CLSID. Whether the frame server can find a CLSID
registered only under the *user's* `HKCU\Software\Classes` is an open
question that §9.4 explicitly refuses to guess at.

The stakes are one UAC prompt:

- **`HKCU` works** → Meo installs entirely per-user with no elevation
  anywhere. Combined with §5.1's outbound-only network design (no firewall
  rule, no prompt), install becomes genuinely friction-free.
- **`HKLM` required** → one UAC prompt at install. Constraint C2 permits this
  — the constraint is money, not friction — but it is worse, and it is worth
  knowing rather than assuming.

Note that §9.5 expects the DirectShow filter, if it is needed at all, to
register cleanly per-user regardless, since `HKCU\Software\Classes` merges
into `HKEY_CLASSES_ROOT` for the app doing the loading. That is a different
mechanism from frame-server activation and does not answer this.

## Why this is still open

Needs a Windows 11 machine. The probe is written; it has not been run.

## How to answer it

The order matters. `scripts/register-hkcu.ps1` **first**, then run
`MeoProbeHost.exe`:

- `Virtual camera STARTED` → `HKCU` is sufficient. Done.
- `MFCreateVirtualCamera` succeeds but `Start()` fails → the frame server
  could not activate the CLSID. Then unregister, run
  `scripts/register-hklm.ps1`, and retry.

Going straight to `HKLM` destroys the result, because a machine-wide
registration also satisfies a per-user lookup. Record the HRESULT either way;
"it didn't work" is not an answer an installer can be designed against.

## Related things the same run should capture

- Whether `MFCreateVirtualCamera` returns `E_ACCESSDENIED`. §9.4 requires the
  Windows camera privacy setting to surface as an actionable message rather
  than a generic failure, and that path needs to be seen at least once.
- Whether the machine is Windows 10, where `MFCreateVirtualCamera` does not
  exist at all. That is a legitimate result and part of why §9.5 exists.

## Consequences of leaving it open

§9.6's installer design cannot be finalised. The portable-ZIP-plus-per-user-
setup story in §16 assumes no elevation; if `HKLM` turns out to be required,
that story needs a UAC step written into it, and §16.1's honesty requirements
mean the README has to show it up front rather than let users discover it.
