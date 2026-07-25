"""
Meo Mic - First-Run Setup Wizard

One-click VB-Cable installation, with the manual steps kept as a fallback.
"""

import threading
import webbrowser
from typing import Callable, List, Optional

import customtkinter as ctk

from . import vbcable

ACCENT = "#3B8ED0"
GREEN = "#4ADE80"
RED = "#F87171"
AMBER = "#F6AD55"
MUTED = "gray"


class SetupWizard:
    """Setup wizard to guide users through VB-Cable installation."""

    VB_CABLE_URL = vbcable.DOWNLOAD_PAGE_URL

    def __init__(self):
        self.window: Optional[ctk.CTkToplevel] = None
        self.on_complete: Optional[Callable] = None
        self.on_skip: Optional[Callable] = None

        self.status_label: Optional[ctk.CTkLabel] = None
        self.continue_btn: Optional[ctk.CTkButton] = None
        self.install_btn: Optional[ctk.CTkButton] = None
        self.restart_btn: Optional[ctk.CTkButton] = None
        self.progress_bar: Optional[ctk.CTkProgressBar] = None
        self.progress_label: Optional[ctk.CTkLabel] = None
        self.manual_frame: Optional[ctk.CTkFrame] = None
        self.manual_toggle: Optional[ctk.CTkButton] = None

        self._manual_visible = False
        self._installing = False
        self._cancel = threading.Event()

    # ------------------------------------------------------------------ #
    # Detection helpers (kept for callers outside this module)
    # ------------------------------------------------------------------ #

    @staticmethod
    def find_virtual_devices() -> List[dict]:
        """Find virtual audio devices."""
        return vbcable.find_virtual_output_devices()

    @staticmethod
    def needs_setup() -> bool:
        """Check if setup wizard should be shown."""
        return len(SetupWizard.find_virtual_devices()) == 0

    # ------------------------------------------------------------------ #
    # Window
    # ------------------------------------------------------------------ #

    def show(self, parent: ctk.CTk):
        """Show the setup wizard window."""
        self.window = ctk.CTkToplevel(parent)
        self.window.title("Meo Mic Setup")
        self.window.geometry("520x700")
        self.window.resizable(False, False)
        self.window.transient(parent)
        self.window.grab_set()
        self.window.protocol("WM_DELETE_WINDOW", self._on_skip)

        self.window.update_idletasks()
        x = parent.winfo_x() + (parent.winfo_width() - 520) // 2
        y = parent.winfo_y() + (parent.winfo_height() - 700) // 2
        self.window.geometry(f"520x700+{x}+{y}")

        main = ctk.CTkFrame(self.window, fg_color="transparent")
        main.pack(fill="both", expand=True, padx=25, pady=20)

        ctk.CTkLabel(
            main,
            text="Virtual Audio Setup",
            font=ctk.CTkFont(size=24, weight="bold")
        ).pack(pady=(0, 3))

        ctk.CTkLabel(
            main,
            text="One-time setup to use your phone as a PC microphone",
            font=ctk.CTkFont(size=12),
            text_color=MUTED
        ).pack(pady=(0, 15))

        scroll = ctk.CTkScrollableFrame(main, fg_color="transparent", height=460)
        scroll.pack(fill="both", expand=True)

        self._build_why_card(scroll)
        self._build_install_card(scroll)
        self._build_manual_section(scroll)

        self._build_bottom_bar(main)

        self._refresh_state()

    def _build_why_card(self, parent):
        card = ctk.CTkFrame(parent, corner_radius=10)
        card.pack(fill="x", pady=(0, 15))

        ctk.CTkLabel(
            card,
            text="Why is this needed?",
            font=ctk.CTkFont(size=13, weight="bold")
        ).pack(pady=(12, 5), padx=15, anchor="w")

        ctk.CTkLabel(
            card,
            text="Windows has no built-in way for an app to appear as a microphone.\n"
                 "VB-Cable adds a virtual audio device that bridges the gap: Meo Mic\n"
                 "plays your phone's audio into it, and Discord, Zoom or any other\n"
                 "app picks it up as a normal mic.",
            font=ctk.CTkFont(size=12),
            text_color=MUTED,
            justify="left"
        ).pack(pady=(0, 12), padx=15, anchor="w")

    def _build_install_card(self, parent):
        card = ctk.CTkFrame(parent, corner_radius=10, fg_color="#1E3A2F")
        card.pack(fill="x", pady=(0, 15))

        ctk.CTkLabel(
            card,
            text="Install VB-Cable",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color=GREEN
        ).pack(pady=(14, 4), padx=15, anchor="w")

        if vbcable.can_auto_install():
            blurb = ("Meo Mic downloads the official installer from vb-audio.com\n"
                     "(about 1.4 MB), checks its signature, and runs it for you.\n"
                     "Windows will ask for administrator permission.")
        else:
            blurb = ("Automatic installation is available on Windows only.\n"
                     "On this platform, install a virtual audio device manually.")

        ctk.CTkLabel(
            card,
            text=blurb,
            font=ctk.CTkFont(size=12),
            text_color="#A0AEC0",
            justify="left"
        ).pack(pady=(0, 10), padx=15, anchor="w")

        self.install_btn = ctk.CTkButton(
            card,
            text="Install VB-Cable",
            width=240,
            height=40,
            corner_radius=8,
            font=ctk.CTkFont(size=14, weight="bold"),
            command=self._start_install
        )
        self.install_btn.pack(pady=(0, 8), padx=15, anchor="w")

        self.restart_btn = ctk.CTkButton(
            card,
            text="Restart now",
            width=240,
            height=40,
            corner_radius=8,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#2F855A",
            hover_color="#276749",
            command=self._restart_now
        )
        # Shown only once an install is waiting on a reboot.

        self.progress_bar = ctk.CTkProgressBar(card, height=8, corner_radius=4)
        self.progress_bar.set(0)

        self.progress_label = ctk.CTkLabel(
            card,
            text="",
            font=ctk.CTkFont(size=11),
            text_color="#A0AEC0",
            justify="left",
            wraplength=440
        )

        ctk.CTkLabel(
            card,
            text="VB-CABLE is donationware by VB-Audio (Vincent Burel). Meo Mic does\n"
                 "not bundle or modify it — you accept VB-Audio's terms in their own\n"
                 "installer. If it's useful, consider donating to them.",
            font=ctk.CTkFont(size=10),
            text_color="#718096",
            justify="left"
        ).pack(pady=(6, 4), padx=15, anchor="w")

        link = ctk.CTkLabel(
            card,
            text="vb-audio.com/Cable",
            font=ctk.CTkFont(size=10, underline=True),
            text_color="#63B3ED",
            cursor="hand2"
        )
        link.pack(pady=(0, 12), padx=15, anchor="w")
        link.bind("<Button-1>", lambda _event: self._open_download())

    def _build_manual_section(self, parent):
        self.manual_toggle = ctk.CTkButton(
            parent,
            text="Install manually instead  ▸",
            height=30,
            corner_radius=8,
            fg_color="transparent",
            hover_color="#333",
            anchor="w",
            text_color=MUTED,
            command=self._toggle_manual
        )
        self.manual_toggle.pack(fill="x", pady=(0, 5))

        self.manual_frame = ctk.CTkFrame(parent, corner_radius=10, fg_color="#252525")

        steps = [
            ("1", "Download VB-Cable", "Opens vb-audio.com/Cable in your browser"),
            ("2", "Extract the ZIP file", "Right-click the downloaded file → Extract All"),
            ("3", "Run the right installer",
             "64-bit Windows: VBCABLE_Setup_x64.exe\n32-bit Windows: VBCABLE_Setup.exe"),
            ("4", "Run as Administrator",
             "Right-click the installer → 'Run as administrator' → Install Driver"),
            ("5", "Restart your PC", "Required before Windows shows the new device"),
        ]

        for number, title, detail in steps:
            self._create_step(self.manual_frame, number, title, detail).pack(
                fill="x", padx=15, pady=6
            )

        ctk.CTkButton(
            self.manual_frame,
            text="Open download page",
            width=200,
            height=34,
            corner_radius=8,
            fg_color="#444",
            hover_color="#555",
            command=self._open_download
        ).pack(pady=(4, 14), padx=15, anchor="w")

    def _create_step(self, parent, number: str, title: str, details: str) -> ctk.CTkFrame:
        """Create a step frame with number, title, and details."""
        frame = ctk.CTkFrame(parent, fg_color="transparent")

        header = ctk.CTkFrame(frame, fg_color="transparent")
        header.pack(fill="x")

        ctk.CTkLabel(
            header,
            text=number,
            font=ctk.CTkFont(size=14, weight="bold"),
            width=28,
            height=28,
            corner_radius=14,
            fg_color=ACCENT
        ).pack(side="left", padx=(0, 10))

        ctk.CTkLabel(
            header,
            text=title,
            font=ctk.CTkFont(size=14, weight="bold"),
            anchor="w"
        ).pack(side="left", fill="x", expand=True)

        if details:
            ctk.CTkLabel(
                frame,
                text=details,
                font=ctk.CTkFont(size=12),
                text_color=MUTED,
                anchor="w",
                justify="left"
            ).pack(fill="x", padx=(38, 0), pady=(2, 0))

        return frame

    def _build_bottom_bar(self, parent):
        bottom = ctk.CTkFrame(parent, fg_color="transparent")
        bottom.pack(fill="x", pady=(10, 0))

        self.status_label = ctk.CTkLabel(bottom, text="", font=ctk.CTkFont(size=12))
        self.status_label.pack(pady=(0, 8))

        buttons = ctk.CTkFrame(bottom, fg_color="transparent")
        buttons.pack(fill="x")

        ctk.CTkButton(
            buttons,
            text="Skip for now",
            width=110,
            height=36,
            corner_radius=8,
            fg_color="#444",
            hover_color="#555",
            command=self._on_skip
        ).pack(side="left")

        ctk.CTkButton(
            buttons,
            text="Re-check",
            width=90,
            height=36,
            corner_radius=8,
            fg_color="#444",
            hover_color="#555",
            command=self._recheck
        ).pack(side="left", padx=10)

        self.continue_btn = ctk.CTkButton(
            buttons,
            text="Continue",
            width=110,
            height=36,
            corner_radius=8,
            state="disabled",
            command=self._on_continue
        )
        self.continue_btn.pack(side="right")

    # ------------------------------------------------------------------ #
    # Install flow
    # ------------------------------------------------------------------ #

    def _start_install(self):
        if self._installing:
            return

        self._installing = True
        self._cancel.clear()

        self.install_btn.configure(state="disabled", text="Installing...")
        self.restart_btn.pack_forget()
        self.progress_bar.pack(fill="x", padx=15, pady=(0, 4))
        self.progress_bar.set(0)
        self.progress_label.pack(fill="x", padx=15, pady=(0, 6))
        self.progress_label.configure(text="Starting...", text_color="#A0AEC0")
        self._set_status("", MUTED)

        threading.Thread(target=self._install_worker, daemon=True).start()

    def _install_worker(self):
        try:
            status = vbcable.install(self._report_progress, self._cancel)
            self._ui(lambda: self._install_succeeded(status))
        except vbcable.InstallCancelled as exc:
            self._ui(lambda: self._install_failed(str(exc), warn_only=True))
        except vbcable.InstallError as exc:
            self._ui(lambda: self._install_failed(str(exc)))
        except Exception as exc:  # noqa: BLE001 - never kill the wizard
            self._ui(lambda: self._install_failed(f"Unexpected error: {exc}"))

    def _report_progress(self, message: str, fraction: Optional[float]):
        def update():
            if not self.progress_label:
                return
            self.progress_label.configure(text=message, text_color="#A0AEC0")
            if fraction is None:
                self.progress_bar.configure(mode="indeterminate")
                self.progress_bar.start()
            else:
                self.progress_bar.stop()
                self.progress_bar.configure(mode="determinate")
                self.progress_bar.set(max(0.0, min(1.0, fraction)))

        self._ui(update)

    def _install_succeeded(self, status: "vbcable.CableStatus"):
        self._installing = False
        self.progress_bar.stop()
        self.progress_bar.pack_forget()
        self.install_btn.configure(state="normal", text="Install VB-Cable")

        if status.installed:
            self.progress_label.configure(
                text="VB-Cable is installed and ready.",
                text_color=GREEN
            )
            self.install_btn.pack_forget()
            self._refresh_state()
            return

        # Installed on disk, endpoints appear after a reboot. Normal outcome.
        self.install_btn.pack_forget()
        self.progress_label.configure(
            text="VB-Cable installed. Restart Windows to finish — the microphone "
                 "won't appear until you do.",
            text_color=AMBER
        )
        self.restart_btn.pack(pady=(0, 8), padx=15, anchor="w")
        self._set_status("Restart required to finish setup", AMBER)

    def _install_failed(self, message: str, warn_only: bool = False):
        self._installing = False
        self.progress_bar.stop()
        self.progress_bar.pack_forget()
        self.install_btn.configure(state="normal", text="Try again")
        self.progress_label.configure(text=message, text_color=AMBER if warn_only else RED)

        if not warn_only and not self._manual_visible:
            self._toggle_manual()

    def _restart_now(self):
        if vbcable.restart_windows(delay_seconds=10):
            self._set_status("Restarting in 10 seconds...", AMBER)
            self.restart_btn.configure(state="disabled", text="Restarting...")
        else:
            self._set_status("Could not trigger a restart — please restart manually.", RED)

    # ------------------------------------------------------------------ #
    # State
    # ------------------------------------------------------------------ #

    def _refresh_state(self):
        """Sync buttons and status text with what's actually installed."""
        status = vbcable.detect()
        devices = self.find_virtual_devices()

        if devices:
            names = ", ".join(d["name"][:30] for d in devices[:2])
            self._set_status(f"Found: {names}", GREEN)
            self.continue_btn.configure(state="normal")
            if self.install_btn and not self._installing:
                self.install_btn.configure(text="Reinstall VB-Cable")
            return

        self.continue_btn.configure(state="disabled")

        if status.reboot_pending:
            self._set_status("VB-Cable installed — restart Windows to finish", AMBER)
            if self.restart_btn and not self.restart_btn.winfo_ismapped():
                self.install_btn.pack_forget()
                self.restart_btn.pack(pady=(0, 8), padx=15, anchor="w")
        else:
            self._set_status("No virtual audio device detected yet", RED)

        if not vbcable.can_auto_install() and self.install_btn:
            self.install_btn.configure(state="disabled")

    def _recheck(self):
        """Re-check for virtual audio devices."""
        vbcable.refresh_device_list()
        self._refresh_state()

    def _set_status(self, text: str, color: str):
        if self.status_label:
            self.status_label.configure(text=text, text_color=color)

    def _toggle_manual(self):
        self._manual_visible = not self._manual_visible
        if self._manual_visible:
            self.manual_frame.pack(fill="x", pady=(0, 10))
            self.manual_toggle.configure(text="Install manually instead  ▾")
        else:
            self.manual_frame.pack_forget()
            self.manual_toggle.configure(text="Install manually instead  ▸")

    def _ui(self, func: Callable):
        """Run *func* on the Tk main thread."""
        if self.window is not None:
            try:
                self.window.after(0, func)
            except Exception:
                pass

    def _open_download(self):
        """Open VB-Cable download page."""
        webbrowser.open(self.VB_CABLE_URL)

    # ------------------------------------------------------------------ #
    # Exit
    # ------------------------------------------------------------------ #

    def _close(self):
        self._cancel.set()
        if self.window:
            self.window.destroy()
            self.window = None

    def _on_skip(self):
        """Handle skip button."""
        self._close()
        if self.on_skip:
            self.on_skip()

    def _on_continue(self):
        """Handle continue button."""
        self._close()
        if self.on_complete:
            self.on_complete()


def check_and_show_setup(parent: ctk.CTk, on_complete: Callable = None, on_skip: Callable = None) -> bool:
    """
    Check if setup is needed and show wizard if so.
    Returns True if setup wizard was shown, False if not needed.
    """
    if SetupWizard.needs_setup():
        wizard = SetupWizard()
        wizard.on_complete = on_complete
        wizard.on_skip = on_skip
        wizard.show(parent)
        return True
    return False
