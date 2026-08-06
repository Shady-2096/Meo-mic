"""
Meo Mic - main window.

One column, two shapes.

Waiting: a sentence tells you what to do, and a card carries the address, copy
and QR. Live: the card gets out of the way and the voice bar carries the
window. Everything else - where the audio goes, how loud - is set once and then
ignored, so it sits below both.
"""

from __future__ import annotations

import os
import sys
from typing import Callable, List, Optional

import customtkinter as ctk

from . import theme as t
from .widgets import StatusDot, VoiceBar, field_label, hairline

ctk.set_appearance_mode("dark")

WIDTH = 400
HEIGHT_WAITING = 610
HEIGHT_LIVE = 430
QR_EXTRA = 190   # the window grows to make room rather than clipping


class MainWindow:
    def __init__(self):
        self.root: Optional[ctk.CTk] = None
        self.running = False

        # State
        self.is_connected = False
        self.client_ip: Optional[str] = None
        self.local_ip: Optional[str] = None
        self.port: int = 48888
        self.audio_level: float = 0.0

        # Callbacks
        self.on_device_change: Optional[Callable[[int], None]] = None
        self.on_volume_change: Optional[Callable[[float], None]] = None
        self.on_quit: Optional[Callable] = None
        self.on_show_setup: Optional[Callable] = None

        # Devices
        self.devices: List[dict] = []
        self.selected_device: Optional[int] = None
        self._pending_devices: Optional[tuple] = None
        self._pending_connection_info: Optional[tuple] = None

        # Widgets
        self.status_dot: Optional[StatusDot] = None
        self.status_headline: Optional[ctk.CTkLabel] = None
        self.status_detail: Optional[ctk.CTkLabel] = None
        self.voice: Optional[VoiceBar] = None
        self.pairing_card: Optional[ctk.CTkFrame] = None
        self.address_label: Optional[ctk.CTkLabel] = None
        self.device_menu: Optional[ctk.CTkOptionMenu] = None
        self.device_note: Optional[ctk.CTkLabel] = None
        self.copy_btn: Optional[ctk.CTkButton] = None
        self.qr_btn: Optional[ctk.CTkButton] = None
        self.volume_slider: Optional[ctk.CTkSlider] = None
        self.volume_label: Optional[ctk.CTkLabel] = None

        self._qr_frame: Optional[ctk.CTkFrame] = None
        self._qr_visible = False
        self._qr_image = None

    # ------------------------------------------------------------------ #
    # Construction
    # ------------------------------------------------------------------ #

    def create_window(self):
        self.root = ctk.CTk(fg_color=t.WINDOW)
        self.root.title("Meo Mic")
        self.root.geometry(f"{WIDTH}x{HEIGHT_WAITING}")
        self.root.resizable(False, False)
        self.root.configure(fg_color=t.WINDOW)

        self._set_icon()

        self.root.update_idletasks()
        x = (self.root.winfo_screenwidth() - WIDTH) // 2
        y = (self.root.winfo_screenheight() - HEIGHT_WAITING) // 2
        self.root.geometry(f"{WIDTH}x{HEIGHT_WAITING}+{x}+{y}")

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._build_footer()   # packed to the bottom first
        self._build_status()
        self._build_voice()
        self._build_pairing()
        self._build_output()

        self.voice.start()
        self._apply_pending_data()

    def _section(self, pady=(t.LG, 0)) -> ctk.CTkFrame:
        frame = ctk.CTkFrame(self.root, fg_color="transparent")
        frame.pack(fill="x", padx=t.PAD, pady=pady)
        return frame

    # -- status ---------------------------------------------------------- #

    def _build_status(self):
        block = self._section(pady=(t.XL, 0))

        headline_row = ctk.CTkFrame(block, fg_color="transparent")
        headline_row.pack(fill="x")

        self.status_dot = StatusDot(headline_row)
        self.status_dot.pack(side="left", padx=(0, 9), pady=(9, 0))

        self.status_headline = ctk.CTkLabel(
            headline_row,
            text="Waiting for your phone",
            font=t.font("status", 19, "bold"),
            text_color=t.TEXT,
            anchor="w",
        )
        self.status_headline.pack(side="left")

        self.status_detail = ctk.CTkLabel(
            block,
            text="Open Meo Mic on your phone - it will find this PC.",
            font=t.font("body", 12),
            text_color=t.TEXT_SECONDARY,
            anchor="w",
            justify="left",
            wraplength=WIDTH - 2 * t.PAD - 19,
        )
        self.status_detail.pack(fill="x", padx=(19, 0), pady=(t.XS, 0))

    # -- voice bar ------------------------------------------------------- #

    def _build_voice(self):
        block = self._section(pady=(t.LG, 0))
        self.voice = VoiceBar(block, width=WIDTH - 2 * t.PAD)
        self.voice.pack(fill="x")

    # -- pairing --------------------------------------------------------- #

    def _build_pairing(self):
        self.pairing_card = ctk.CTkFrame(
            self.root,
            fg_color=t.CARD,
            corner_radius=t.RADIUS_LG,
            border_width=1,
            border_color=t.BORDER,
        )
        self.pairing_card.pack(fill="x", padx=t.PAD, pady=(t.XL, 0))

        inner = ctk.CTkFrame(self.pairing_card, fg_color="transparent")
        inner.pack(fill="x", padx=t.LG, pady=t.LG)

        ctk.CTkLabel(
            inner,
            text="Connect your phone",
            font=t.font("title", 14, "bold"),
            text_color=t.TEXT,
            anchor="w",
        ).pack(fill="x")

        self.address_label = ctk.CTkLabel(
            inner,
            text="Looking for your network...",
            font=t.font("body", 17, "bold"),
            text_color=t.TEXT,
            anchor="w",
        )
        self.address_label.pack(fill="x", pady=(t.SM, 0))

        ctk.CTkLabel(
            inner,
            text="Tap Search for PC on your phone, or scan the code.",
            font=t.font("label", 11),
            text_color=t.TEXT_TERTIARY,
            anchor="w",
            justify="left",
            wraplength=WIDTH - 2 * t.PAD - 2 * t.LG,
        ).pack(fill="x", pady=(t.XS, 0))

        actions = ctk.CTkFrame(inner, fg_color="transparent")
        actions.pack(fill="x", pady=(t.MD, 0))

        self.copy_btn = self._card_button(actions, "Copy address", self._copy_ip, width=118)
        self.copy_btn.pack(side="left")

        self.qr_btn = self._card_button(actions, "Show QR", self._toggle_qr, width=92)
        self.qr_btn.pack(side="left", padx=(t.SM, 0))

        self._qr_frame = ctk.CTkFrame(inner, fg_color="transparent")

    # -- output ---------------------------------------------------------- #

    def _build_output(self):
        block = self._section(pady=(t.XL, 0))

        field_label(block, "Send audio to").pack(fill="x", pady=(0, t.XS))

        self.device_menu = ctk.CTkOptionMenu(
            block,
            values=["No devices found"],
            height=36,
            corner_radius=t.RADIUS,
            font=t.font("body", 12),
            dropdown_font=t.font("body", 12),
            fg_color=t.CARD_HOVER,
            button_color=t.CARD_HOVER,
            button_hover_color=t.SURFACE1,
            text_color=t.TEXT,
            dropdown_fg_color=t.CARD,
            dropdown_hover_color=t.CARD_HOVER,
            dropdown_text_color=t.TEXT,
            command=self._on_device_selected,
        )
        self.device_menu.pack(fill="x")

        self.device_note = ctk.CTkLabel(
            block,
            text="",
            font=t.font("label", 11),
            text_color=t.TEXT_TERTIARY,
            anchor="w",
            justify="left",
            wraplength=WIDTH - 2 * t.PAD,
        )
        self.device_note.pack(fill="x", pady=(t.SM, 0))

        volume_row = ctk.CTkFrame(block, fg_color="transparent")
        volume_row.pack(fill="x", pady=(t.LG, 0))

        field_label(volume_row, "Volume").pack(side="left")

        self.volume_label = ctk.CTkLabel(
            volume_row,
            text="100%",
            font=t.font("label", 11),
            text_color=t.TEXT_SECONDARY,
        )
        self.volume_label.pack(side="right")

        self.volume_slider = ctk.CTkSlider(
            block,
            from_=0,
            to=200,
            number_of_steps=200,
            height=16,
            button_length=0,
            corner_radius=3,
            fg_color=t.CARD_HOVER,
            progress_color=t.ACCENT,
            button_color=t.TEXT,
            button_hover_color=t.ACCENT_HOVER,
            command=self._on_volume_changed,
        )
        self.volume_slider.pack(fill="x", pady=(t.SM, 0))
        self.volume_slider.set(100)

    # -- footer ---------------------------------------------------------- #

    def _build_footer(self):
        footer = ctk.CTkFrame(self.root, fg_color="transparent")
        footer.pack(side="bottom", fill="x", padx=t.PAD, pady=(0, t.LG))

        rule = hairline(self.root)
        rule.pack(side="bottom", fill="x", padx=t.PAD, pady=(0, t.LG))

        self._link_button(footer, "Audio setup", self._on_show_setup).pack(side="left")
        self._link_button(footer, "Quit", self._on_close).pack(side="right")

    def _card_button(self, parent, text: str, command, width: int = 100) -> ctk.CTkButton:
        """Filled, quiet. Nothing on this window shouts."""
        return ctk.CTkButton(
            parent,
            text=text,
            width=width,
            height=32,
            corner_radius=t.RADIUS,
            font=t.font("label", 11),
            fg_color=t.CARD_HOVER,
            hover_color=t.SURFACE1,
            text_color=t.TEXT,
            command=command,
        )

    def _link_button(self, parent, text: str, command) -> ctk.CTkButton:
        return ctk.CTkButton(
            parent,
            text=text,
            width=1,
            height=22,
            corner_radius=t.RADIUS,
            font=t.font("label", 11),
            fg_color="transparent",
            hover_color=t.CARD,
            text_color=t.TEXT_SECONDARY,
            command=command,
        )

    # ------------------------------------------------------------------ #
    # Window shape
    # ------------------------------------------------------------------ #

    def _resize_window(self):
        """The window is as tall as the state needs, and no taller."""
        if not self.root:
            return
        height = HEIGHT_LIVE if self.is_connected else HEIGHT_WAITING
        if self._qr_visible and not self.is_connected:
            height += QR_EXTRA
        self.root.geometry(f"{WIDTH}x{height}")

    # ------------------------------------------------------------------ #
    # QR
    # ------------------------------------------------------------------ #

    def _toggle_qr(self):
        if self._qr_visible:
            self._qr_frame.pack_forget()
            for child in self._qr_frame.winfo_children():
                child.destroy()
            self.qr_btn.configure(text="Show QR")
            self._qr_visible = False
            self._resize_window()
            return

        image = self._render_qr()
        if image is None:
            self.device_note.configure(
                text="No address yet, so there is nothing to scan.", text_color=t.HOT
            )
            return

        holder = ctk.CTkFrame(self._qr_frame, fg_color=t.TEXT, corner_radius=t.RADIUS)
        holder.pack(anchor="w")
        ctk.CTkLabel(holder, image=image, text="").pack(padx=10, pady=10)

        ctk.CTkLabel(
            self._qr_frame,
            text="Tap Scan QR Code on your phone.",
            font=t.font("label", 11),
            text_color=t.TEXT_TERTIARY,
            anchor="w",
        ).pack(fill="x", pady=(t.SM, 0))

        self._qr_frame.pack(fill="x", pady=(t.MD, 0))
        self.qr_btn.configure(text="Hide QR")
        self._qr_visible = True
        self._resize_window()

    def _render_qr(self):
        if not self.local_ip:
            return None
        try:
            import qrcode
            from PIL import Image

            qr = qrcode.QRCode(version=1, border=0, box_size=4,
                               error_correction=qrcode.constants.ERROR_CORRECT_M)
            qr.add_data(f"meomic://{self.local_ip}:{self.port}")
            qr.make(fit=True)

            # Dark modules on a light field so phone cameras still lock on,
            # but both values come from the palette.
            img = qr.make_image(fill_color=t.WINDOW, back_color=t.TEXT).convert("RGB")
            img = img.resize((132, 132), Image.Resampling.NEAREST)

            self._qr_image = ctk.CTkImage(light_image=img, dark_image=img, size=(132, 132))
            return self._qr_image
        except Exception:
            return None

    # ------------------------------------------------------------------ #
    # Events
    # ------------------------------------------------------------------ #

    def _copy_ip(self):
        if self.local_ip and self.root:
            self.root.clipboard_clear()
            self.root.clipboard_append(f"{self.local_ip}:{self.port}")
            self.copy_btn.configure(text="Copied")
            self.root.after(1400, lambda: self.copy_btn.configure(text="Copy address"))

    def _on_device_selected(self, choice: str):
        if self.on_device_change and self.devices:
            for dev in self.devices:
                if self._device_label(dev) == choice:
                    self.selected_device = dev["id"]
                    self.on_device_change(dev["id"])
                    self._update_device_note()
                    break

    def _on_volume_changed(self, value: float):
        if self.volume_label:
            self.volume_label.configure(text=f"{int(value)}%")
        if self.on_volume_change:
            self.on_volume_change(value / 100.0)

    def _on_close(self):
        self.running = False
        if self.voice:
            self.voice.stop()
        if self.on_quit:
            self.on_quit()
        if self.root:
            self.root.quit()
            self.root.destroy()

    def _on_show_setup(self):
        if self.on_show_setup:
            self.on_show_setup()

    def _set_icon(self):
        try:
            candidates = [
                os.path.join(os.path.dirname(sys.executable), "icon.ico"),
                os.path.join(os.path.dirname(__file__), "..", "icon.ico"),
                os.path.join(os.path.dirname(__file__), "icon.ico"),
                "icon.ico",
            ]
            for path in candidates:
                if os.path.exists(path):
                    self.root.iconbitmap(path)
                    return
        except Exception:
            pass

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    def _apply_pending_data(self):
        if self._pending_connection_info:
            ip, port = self._pending_connection_info
            self._do_set_connection_info(ip, port)
            self._pending_connection_info = None

        if self._pending_devices:
            devices, selected = self._pending_devices
            self._do_set_devices(devices, selected)
            self._pending_devices = None

    def set_connection_info(self, ip: str, port: int):
        self.local_ip = ip
        self.port = port
        if self.root and self.address_label:
            self.root.after(0, lambda: self._do_set_connection_info(ip, port))
        else:
            self._pending_connection_info = (ip, port)

    def _do_set_connection_info(self, ip: str, port: int):
        # These handlers own the state they render. Letting the caller set it
        # first means any path that does not go through the public setter
        # renders against stale values.
        self.local_ip = ip
        self.port = port
        if self.address_label:
            self.address_label.configure(text=f"{ip}:{port}")
        self._update_status_text()

    @staticmethod
    def _device_label(dev: dict) -> str:
        return dev["name"]

    def set_devices(self, devices: List[dict], selected: Optional[int] = None):
        self.devices = devices
        self.selected_device = selected
        if self.root and self.device_menu:
            self.root.after(0, lambda: self._do_set_devices(devices, selected))
        else:
            self._pending_devices = (devices, selected)

    def _do_set_devices(self, devices: List[dict], selected: Optional[int]):
        self.devices = devices
        self.selected_device = selected
        if not self.device_menu:
            return

        names, selected_name = [], None
        for dev in devices:
            label = self._device_label(dev)
            names.append(label)
            if dev["id"] == selected:
                selected_name = label

        if names:
            self.device_menu.configure(values=names)
            self.device_menu.set(selected_name or names[0])
        else:
            self.device_menu.configure(values=["No devices found"])
            self.device_menu.set("No devices found")

        self._update_device_note()
        self._update_status_text()

    def _current_device(self) -> Optional[dict]:
        return next((d for d in self.devices if d["id"] == self.selected_device), None)

    def _update_device_note(self):
        """Say what this choice means, in the user's words - not the driver's."""
        if not self.device_note:
            return

        current = self._current_device()

        if current is None:
            self.device_note.configure(
                text="Pick a virtual audio device so call apps can hear your phone.",
                text_color=t.TEXT_TERTIARY,
            )
        elif current["is_virtual"]:
            self.device_note.configure(
                text="Ready - choose CABLE Output as your microphone in Discord, Zoom, or Meet.",
                text_color=t.TEXT_SECONDARY,
            )
        else:
            self.device_note.configure(
                text="This plays out loud. No app can use it as a microphone.",
                text_color=t.HOT,
            )

    def update_status(self, connected: bool, client_ip: Optional[str] = None):
        self.is_connected = connected
        self.client_ip = client_ip
        if self.root:
            self.root.after(0, lambda: self._do_update_status(connected, client_ip))

    def _do_update_status(self, connected: bool, client_ip: Optional[str]):
        self.is_connected = connected
        self.client_ip = client_ip
        if self.status_dot:
            self.status_dot.set_live(connected)
        if self.voice:
            self.voice.set_connected(connected)

        # Waiting asks a question the pairing card answers; live does not.
        if self.pairing_card:
            if connected and self.pairing_card.winfo_ismapped():
                self.pairing_card.pack_forget()
            elif not connected and not self.pairing_card.winfo_ismapped():
                self.pairing_card.pack(
                    fill="x", padx=t.PAD, pady=(t.XL, 0), after=self._voice_anchor()
                )

        self._update_status_text()
        self._resize_window()

    def _voice_anchor(self):
        """The pairing card belongs directly under the voice bar."""
        return self.voice.master if self.voice else None

    def _update_status_text(self):
        if not self.status_headline or not self.status_detail:
            return

        if self.is_connected:
            self.status_headline.configure(text="Your phone is live")
            device = self._current_device()
            where = self.client_ip or "your phone"
            if device and device["is_virtual"]:
                detail = f"Arriving from {where} and going into {device['name']}."
            else:
                detail = f"Arriving from {where}."
            self.status_detail.configure(text=detail, text_color=t.TEXT_SECONDARY)
        else:
            self.status_headline.configure(text="Waiting for your phone")
            if self.local_ip:
                detail = "Open Meo Mic on your phone - it will find this PC."
            else:
                detail = "Connect this PC to Wi-Fi first."
            self.status_detail.configure(text=detail, text_color=t.TEXT_SECONDARY)

    def update_level(self, level: float):
        """Legacy 0..1 RMS input, kept for callers that still use it."""
        import math

        self.audio_level = level
        db = 20.0 * math.log10(max(level * 10000.0 / 32768.0, 1e-6))
        self.update_level_db(db)

    def update_level_db(self, db: float):
        """Feed the voice bar peak dBFS."""
        if self.voice:
            self.voice.set_db(db)

    def run(self):
        self.create_window()
        self.running = True
        self.root.mainloop()

    def stop(self):
        self.running = False
        if self.voice:
            self.voice.stop()
        if self.root:
            try:
                self.root.quit()
            except Exception:
                pass
