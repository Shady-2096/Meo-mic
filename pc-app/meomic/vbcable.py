"""
Meo Mic - VB-Cable detection and one-click installation (Windows).

Meo Mic does not bundle or redistribute VB-CABLE. VB-CABLE is donationware by
VB-Audio (Vincent Burel) and its licence does not permit redistribution as part
of another package. Instead this module:

  1. downloads the official driver pack straight from vb-audio.com,
  2. verifies the Authenticode signature on VB-Audio's own setup executable,
  3. launches that setup unmodified, elevated, so the user accepts VB-Audio's
     terms in VB-Audio's own installer.

Nothing here runs on non-Windows platforms; macOS uses an AudioServerPlugIn
instead and has no equivalent step.
"""

from __future__ import annotations

import ctypes
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from typing import Callable, List, Optional

# Official VB-Audio download page (shown to the user, and the manual fallback).
DOWNLOAD_PAGE_URL = "https://vb-audio.com/Cable/"
LICENSING_URL = "https://vb-audio.com/Services/licensing.htm"

# Official driver pack URLs, newest first. VB-Audio publishes each release under
# a new pack number and keeps the old ones online, so trying newest-first gets
# the current release without us having to chase the version.
DRIVER_PACK_URLS = (
    "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip",
    "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack44.zip",
    "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip",
)

SETUP_EXE_X64 = "VBCABLE_Setup_x64.exe"
SETUP_EXE_X86 = "VBCABLE_Setup.exe"

# Authenticode subject fragments we accept for the setup executable. Current
# packs are signed "BUREL VINCENT Entrepreneur individuel" (GlobalSign EV);
# older ones used the VB-Audio company name.
ACCEPTED_SIGNERS = ("BUREL VINCENT", "VINCENT BUREL", "VB-AUDIO")

DOWNLOAD_TIMEOUT = 30
MAX_DOWNLOAD_BYTES = 32 * 1024 * 1024  # sanity cap; the pack is ~1.4 MB

# Progress callback: (message, fraction or None for indeterminate)
ProgressCallback = Callable[[str, Optional[float]], None]


class InstallError(Exception):
    """Raised when the guided install cannot complete."""

    def __init__(self, message: str, *, can_retry: bool = True):
        super().__init__(message)
        self.can_retry = can_retry


class InstallCancelled(InstallError):
    """Raised when the user cancels, including declining the UAC prompt."""

    def __init__(self, message: str = "Installation cancelled."):
        super().__init__(message, can_retry=True)


def is_windows() -> bool:
    return sys.platform == "win32"


def can_auto_install() -> bool:
    """One-click install is Windows-only."""
    return is_windows()


# --------------------------------------------------------------------------- #
# Detection
# --------------------------------------------------------------------------- #

@dataclass
class CableStatus:
    """What we know about VB-Cable on this machine."""

    input_device: Optional[str] = None      # "CABLE Input"  (an output device)
    output_device: Optional[str] = None     # "CABLE Output" (an input device)
    registry_present: bool = False

    @property
    def devices_present(self) -> bool:
        return self.input_device is not None

    @property
    def installed(self) -> bool:
        return self.devices_present

    @property
    def reboot_pending(self) -> bool:
        """Installed on disk but the audio endpoints have not appeared yet."""
        return self.registry_present and not self.devices_present


def refresh_device_list() -> None:
    """Force PortAudio to re-enumerate devices after a driver install."""
    try:
        import sounddevice as sd

        sd._terminate()
        sd._initialize()
    except Exception:
        pass


def detect() -> CableStatus:
    """Detect VB-Cable endpoints and its installed-on-disk footprint."""
    status = CableStatus()

    try:
        import sounddevice as sd

        for dev in sd.query_devices():
            name = dev["name"]
            lowered = name.lower()
            if "cable input" in lowered and dev["max_output_channels"] > 0:
                status.input_device = status.input_device or name
            elif "cable output" in lowered and dev["max_input_channels"] > 0:
                status.output_device = status.output_device or name
    except Exception:
        pass

    status.registry_present = _registry_has_vbcable()
    return status


def _registry_has_vbcable() -> bool:
    """Look for a VB-Cable uninstall entry.

    Lets us tell "not installed" apart from "installed, waiting for a reboot",
    which is the difference between showing an install button and showing a
    restart prompt.
    """
    if not is_windows():
        return False

    try:
        import winreg
    except ImportError:
        return False

    roots = (
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
    )

    for hive, path in roots:
        try:
            with winreg.OpenKey(hive, path) as key:
                count = winreg.QueryInfoKey(key)[0]
                for i in range(count):
                    try:
                        sub = winreg.EnumKey(key, i)
                        with winreg.OpenKey(key, sub) as subkey:
                            name = str(winreg.QueryValueEx(subkey, "DisplayName")[0]).lower()
                    except OSError:
                        continue
                    if "vb-cable" in name or "vb-audio virtual cable" in name or "vbcable" in name:
                        return True
        except OSError:
            continue

    return False


# --------------------------------------------------------------------------- #
# Install
# --------------------------------------------------------------------------- #

def _os_is_64bit() -> bool:
    """Bitness of Windows itself, not of the Python process."""
    if os.environ.get("PROCESSOR_ARCHITEW6432"):
        return True
    arch = os.environ.get("PROCESSOR_ARCHITECTURE", platform.machine()).upper()
    return arch in ("AMD64", "ARM64", "IA64", "X86_64")


def _setup_exe_name() -> str:
    return SETUP_EXE_X64 if _os_is_64bit() else SETUP_EXE_X86


def _download_pack(dest: str, progress: ProgressCallback, cancel: threading.Event) -> str:
    """Download the driver pack to *dest*. Returns the URL actually used."""
    last_error: Optional[Exception] = None

    for url in DRIVER_PACK_URLS:
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": "Meo-Mic/1.0 (+https://github.com/Shady-2096/Meo-mic)"},
            )
            with urllib.request.urlopen(request, timeout=DOWNLOAD_TIMEOUT) as response:
                total = int(response.headers.get("Content-Length") or 0)
                read = 0
                with open(dest, "wb") as handle:
                    while True:
                        if cancel.is_set():
                            raise InstallCancelled()
                        chunk = response.read(64 * 1024)
                        if not chunk:
                            break
                        read += len(chunk)
                        if read > MAX_DOWNLOAD_BYTES:
                            raise InstallError("Download was unexpectedly large; aborting.")
                        handle.write(chunk)
                        fraction = (read / total) if total else None
                        progress(f"Downloading VB-Cable... {read // 1024} KB", fraction)
            if os.path.getsize(dest) > 0:
                return url
            last_error = InstallError("Downloaded file was empty.")
        except InstallError:
            raise
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            last_error = exc
            continue

    raise InstallError(
        "Could not download VB-Cable. Check your internet connection, or install "
        f"it manually from {DOWNLOAD_PAGE_URL}.\n({last_error})"
    )


def _extract_pack(zip_path: str, target_dir: str) -> str:
    """Extract the pack and return the path to the setup executable."""
    wanted = _setup_exe_name()

    try:
        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            if wanted not in names:
                raise InstallError(
                    f"The downloaded package does not contain {wanted}. "
                    "VB-Audio may have changed the package layout."
                )
            # The pack is flat, but never trust archive paths. Validate every
            # member before writing anything.
            for name in names:
                if os.path.isabs(name) or ".." in name.replace("\\", "/").split("/"):
                    raise InstallError("The downloaded package contains unsafe file paths.")
            archive.extractall(target_dir)
    except zipfile.BadZipFile:
        raise InstallError("The downloaded package is corrupt. Try again.")

    setup_path = os.path.join(target_dir, wanted)
    if not os.path.isfile(setup_path):
        raise InstallError(f"{wanted} was not extracted correctly.")
    return setup_path


def _verify_signature(exe_path: str) -> str:
    """Verify the Authenticode signature. Returns the signer subject.

    Fails closed: we are about to run this binary with administrator rights, so
    an unverifiable signature aborts the install rather than warning.
    """
    if not is_windows():
        raise InstallError("Signature verification is only available on Windows.")

    quoted = exe_path.replace("'", "''")
    script = (
        "$ErrorActionPreference='Stop';"
        f"$s = Get-AuthenticodeSignature -LiteralPath '{quoted}';"
        "Write-Output $s.Status;"
        "Write-Output $s.SignerCertificate.Subject"
    )

    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-Command", script],
            capture_output=True,
            text=True,
            timeout=60,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise InstallError(
            "Could not verify the installer's digital signature "
            f"({exc}). For safety, install VB-Cable manually instead."
        )

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if result.returncode != 0 or len(lines) < 2:
        raise InstallError(
            "Could not verify the installer's digital signature. "
            "For safety, install VB-Cable manually instead."
        )

    status, subject = lines[0], lines[1]
    if status.lower() != "valid":
        raise InstallError(
            f"The downloaded installer's signature is not valid (status: {status}). "
            "Aborting for safety."
        )

    upper = subject.upper()
    if not any(signer in upper for signer in ACCEPTED_SIGNERS):
        raise InstallError(
            "The downloaded installer is signed by an unexpected publisher:\n"
            f"{subject}\nAborting for safety."
        )

    return subject


def _run_elevated(exe_path: str, work_dir: str, cancel: threading.Event) -> int:
    """Run *exe_path* elevated and wait for it. Returns its exit code."""
    from ctypes import wintypes

    SEE_MASK_NOCLOSEPROCESS = 0x00000040
    SEE_MASK_NOASYNC = 0x00000100
    SW_SHOWNORMAL = 1
    ERROR_CANCELLED = 1223
    WAIT_TIMEOUT = 0x00000102

    class SHELLEXECUTEINFOW(ctypes.Structure):
        _fields_ = [
            ("cbSize", wintypes.DWORD),
            ("fMask", ctypes.c_ulong),
            ("hwnd", wintypes.HWND),
            ("lpVerb", wintypes.LPCWSTR),
            ("lpFile", wintypes.LPCWSTR),
            ("lpParameters", wintypes.LPCWSTR),
            ("lpDirectory", wintypes.LPCWSTR),
            ("nShow", ctypes.c_int),
            ("hInstApp", wintypes.HINSTANCE),
            ("lpIDList", ctypes.c_void_p),
            ("lpClass", wintypes.LPCWSTR),
            ("hkeyClass", wintypes.HKEY),
            ("dwHotKey", wintypes.DWORD),
            ("hIcon", wintypes.HANDLE),
            ("hProcess", wintypes.HANDLE),
        ]

    # use_last_error is required: ctypes clears the thread error code between
    # calls on the cached windll handles, so ERROR_CANCELLED (the user clicking
    # "No" on the UAC prompt) would otherwise be unreadable.
    shell32 = ctypes.WinDLL("shell32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    shell32.ShellExecuteExW.argtypes = [ctypes.POINTER(SHELLEXECUTEINFOW)]
    shell32.ShellExecuteExW.restype = wintypes.BOOL
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.WaitForSingleObject.restype = wintypes.DWORD
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]

    info = SHELLEXECUTEINFOW()
    info.cbSize = ctypes.sizeof(info)
    info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC
    info.hwnd = None
    info.lpVerb = "runas"
    info.lpFile = exe_path
    info.lpParameters = None
    info.lpDirectory = work_dir
    info.nShow = SW_SHOWNORMAL

    if not shell32.ShellExecuteExW(ctypes.byref(info)):
        error = ctypes.get_last_error()
        if error == ERROR_CANCELLED:
            raise InstallCancelled(
                "Administrator permission was declined. VB-Cable installs a "
                "driver, so Windows requires it."
            )
        raise InstallError(f"Could not launch the VB-Cable installer (error {error}).")

    handle = info.hProcess
    if not handle:
        # Launched, but we cannot wait on it. Treat as success and let the
        # caller re-detect.
        return 0

    try:
        while True:
            # Poll rather than block forever so the caller stays responsive.
            if kernel32.WaitForSingleObject(handle, 500) != WAIT_TIMEOUT:
                break
            # Note: cancel is deliberately not honoured here. Killing VB-Audio's
            # installer mid-driver-install would leave the machine in a worse
            # state than letting it finish.
        exit_code = wintypes.DWORD()
        kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
        return int(exit_code.value)
    finally:
        kernel32.CloseHandle(handle)


def install(progress: ProgressCallback,
            cancel: Optional[threading.Event] = None) -> CableStatus:
    """Download, verify and run VB-Audio's official VB-Cable installer.

    Blocking; call it on a worker thread. *progress* is invoked with a status
    message and a 0..1 fraction (or None when indeterminate).

    Returns the post-install status. A result where ``reboot_pending`` is true
    is the normal successful outcome: VB-Cable's endpoints only appear after a
    restart.
    """
    if not can_auto_install():
        raise InstallError(
            "Automatic VB-Cable installation is only available on Windows.",
            can_retry=False,
        )

    cancel = cancel or threading.Event()
    work_dir = tempfile.mkdtemp(prefix="meomic-vbcable-")

    try:
        progress("Contacting vb-audio.com...", None)
        zip_path = os.path.join(work_dir, "VBCABLE_Driver_Pack.zip")
        _download_pack(zip_path, progress, cancel)

        if cancel.is_set():
            raise InstallCancelled()

        progress("Extracting...", None)
        extract_dir = os.path.join(work_dir, "pack")
        os.makedirs(extract_dir, exist_ok=True)
        setup_path = _extract_pack(zip_path, extract_dir)

        progress("Verifying VB-Audio's signature...", None)
        _verify_signature(setup_path)

        if cancel.is_set():
            raise InstallCancelled()

        progress("Waiting for Windows administrator approval...", None)
        _run_elevated(setup_path, extract_dir, cancel)

        progress("Checking for the new audio device...", None)
        # The driver needs a moment to register even before a reboot.
        time.sleep(1.5)
        refresh_device_list()
        status = detect()

        if not status.installed and not status.registry_present:
            raise InstallError(
                "The installer finished but VB-Cable was not detected. "
                "It may not have been installed — try again, or install it "
                f"manually from {DOWNLOAD_PAGE_URL}."
            )

        return status
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def restart_windows(delay_seconds: int = 10) -> bool:
    """Ask Windows to restart. Returns True if the request was accepted."""
    if not is_windows():
        return False
    try:
        subprocess.run(
            ["shutdown", "/r", "/t", str(delay_seconds), "/c",
             "Restarting to finish installing VB-Cable for Meo Mic."],
            check=True,
            capture_output=True,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def find_virtual_output_devices() -> List[dict]:
    """All virtual audio devices we could route into (any vendor)."""
    keywords = ("cable", "virtual", "vb-audio", "blackhole", "soundflower", "loopback")
    found: List[dict] = []

    try:
        import sounddevice as sd

        for index, dev in enumerate(sd.query_devices()):
            if dev["max_output_channels"] > 0:
                lowered = dev["name"].lower()
                if any(keyword in lowered for keyword in keywords):
                    found.append({
                        "id": index,
                        "name": dev["name"],
                        "channels": dev["max_output_channels"],
                    })
    except Exception:
        pass

    return found
