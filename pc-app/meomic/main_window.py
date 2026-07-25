"""
Meo Mic - main window.

Laid out as an instrument panel: a status rail, the meter, and below it the
three things you set once - where your phone connects, where the audio goes,
and how loud. The meter gets the space because it is the only element that
answers the question you opened the window to ask.
"""

from __future__ import annotations

import os
import sys
import tkinter as tk
from typing import Callable, List, Optional

import customtkinter as ctk

from . import theme as t
from .widgets import LevelMeter, StatusPill, Wordmark, eyebrow, hairline

ctk.set_appearance_mode("dark")

WIDTH = 380
HEIGHT = 620
QR_EXTRA = 186   # the window grows to make room rather than clipping


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
        self.status_pill: Optional[StatusPill] = None
        self.meter: Optional[LevelMeter] = None
        self.db_readout: Optional[ctk.CTkLabel] = None
        self.address_label: Optional[ctk.CTkLabel] = None
        self.peer_label: Optional[ctk.CTkLabel] = None
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
        self.root = ctk.CTk(fg_color=t.CRUST)
        self.root.title("Meo Mic")
        self.root.geometry(f"{WIDTH}x{HEIGHT}")
        self.root.resizable(False, False)
        self.root.configure(fg_color=t.CRUST)

        self._set_icon()

        self.root.update_idletasks()
        x = (self.root.winfo_screenwidth() - WIDTH) // 2
        y = (self.root.winfo_screenheight() - HEIGHT) // 2
        self.root.geometry(f"{WIDTH}x{HEIGHT}+{x}+{y}")

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._build_header()
        self._build_meter()
        self._build_phone()
        self._build_output()
        self._build_footer()

        self.meter.start()
        self._apply_pending_data()

    def _section(self, pady=(t.LG, 0)) -> ctk.CTkFrame:
        frame = ctk.CTkFrame(self.root, fg_color="transparent")
        frame.pack(fill="x", padx=t.PAD, pady=pady)
        return frame

    def _rule(self, pady=(t.LG, 0)):
        rule = hairline(self.root)
        rule.pack(fill="x", padx=t.PAD, pady=pady)

    def _build_header(self):
        header = self._section(pady=(t.LG, 0))
        Wordmark(header).pack(side="left")
        self.status_pill = StatusPill(header)
        self.status_pill.pack(side="right", pady=(3, 0))

        self._rule(pady=(t.MD, 0))

    def _build_meter(self):
        block = self._section(pady=(t.LG, 0))

        label_row = ctk.CTkFrame(block, fg_color="transparent")
        label_row.pack(fill="x", pady=(0, t.SM))

        eyebrow(label_row, "INPUT LEVEL").pack(side="left")

        self.db_readout = ctk.CTkLabel(
            label_row,
            text="—",
            font=t.font("data", 13, "bold"),
            text_color=t.OVERLAY,
        )
        self.db_readout.pack(side="right")

        self.meter = LevelMeter(block, width=WIDTH - 2 * t.PAD)
        self.meter.pack(fill="x")

        self.peer_label = ctk.CTkLabel(
            block,
            text="Waiting for a phone to connect",
            font=t.font("body", 11),
            text_color=t.OVERLAY,
            anchor="w",
        )
        self.peer_label.pack(fill="x", pady=(t.SM, 0))

        self._rule(pady=(t.MD, 0))

    def _build_phone(self):
        block = self._section(pady=(t.MD, 0))

        eyebrow(block, "PHONE CONNECTS TO").pack(fill="x", pady=(0, t.SM))

        self.address_label = ctk.CTkLabel(
            block,
            text="—",
            font=t.font("data", 19, "bold"),
            text_color=t.TEXT,
            anchor="w",
        )
        self.address_label.pack(fill="x")

        actions = ctk.CTkFrame(block, fg_color="transparent")
        actions.pack(fill="x", pady=(t.MD, 0))

        self.copy_btn = self._ghost_button(actions, "Copy address", self._copy_ip, width=118)
        self.copy_btn.pack(side="left")

        self.qr_btn = self._ghost_button(actions, "Scan QR", self._toggle_qr, width=94)
        self.qr_btn.pack(side="left", padx=(t.SM, 0))

        self._qr_frame = ctk.CTkFrame(block, fg_color="transparent")

        self._rule(pady=(t.MD, 0))

    def _build_output(self):
        block = self._section(pady=(t.MD, 0))

        eyebrow(block, "OUTPUT DEVICE").pack(fill="x", pady=(0, t.SM))

        self.device_menu = ctk.CTkOptionMenu(
            block,
            values=["No devices found"],
            height=36,
            corner_radius=t.RADIUS,
            font=t.font("body", 12),
            dropdown_font=t.font("body", 12),
            fg_color=t.BASE,
            button_color=t.SURFACE0,
            button_hover_color=t.SURFACE1,
            text_color=t.TEXT,
            dropdown_fg_color=t.BASE,
            dropdown_hover_color=t.SURFACE0,
            dropdown_text_color=t.TEXT,
            command=self._on_device_selected,
        )
        self.device_menu.pack(fill="x")

        self.device_note = ctk.CTkLabel(
            block,
            text="",
            font=t.font("body", 11),
            text_color=t.OVERLAY,
            anchor="w",
        )
        self.device_note.pack(fill="x", pady=(t.SM, 0))

        gain_row = ctk.CTkFrame(block, fg_color="transparent")
        gain_row.pack(fill="x", pady=(t.LG, 0))

        eyebrow(gain_row, "GAIN").pack(side="left")

        self.volume_label = ctk.CTkLabel(
            gain_row,
            text="100%",
            font=t.font("data", 12),
            text_color=t.SUBTEXT,
        )
        self.volume_label.pack(side="right")

        self.volume_slider = ctk.CTkSlider(
            block,
            from_=0,
            to=200,
            number_of_steps=200,
            height=14,
            button_length=4,
            corner_radius=3,
            fg_color=t.SURFACE0,
            progress_color=t.mix(t.MAUVE, t.CRUST, 0.5),
            button_color=t.MAUVE,
            button_hover_color=t.LAVENDER,
            command=self._on_volume_changed,
        )
        self.volume_slider.pack(fill="x", pady=(t.SM, 0))
        self.volume_slider.set(100)

    def _build_footer(self):
        footer = ctk.CTkFrame(self.root, fg_color="transparent")
        footer.pack(side="bottom", fill="x", padx=t.PAD, pady=(0, t.LG))

        rule = hairline(self.root)
        rule.pack(side="bottom", fill="x", padx=t.PAD, pady=(0, t.LG))

        self._ghost_button(footer, "Audio setup", self._on_show_setup, width=104).pack(side="left")

        quit_btn = self._ghost_button(footer, "Quit", self._on_close, width=68)
        quit_btn.configure(text_color=t.OVERLAY)
        quit_btn.pack(side="right")

    def _ghost_button(self, parent, text: str, command, width: int = 100) -> ctk.CTkButton:
        """Outlined, quiet. Nothing on this window shouts."""
        return ctk.CTkButton(
            parent,
            text=text,
            width=width,
            height=34,
            corner_radius=t.RADIUS,
            font=t.font("body", 12),
            fg_color="transparent",
            hover_color=t.BASE,
            border_width=1,
            border_color=t.SURFACE0,
            text_color=t.SUBTEXT,
            command=command,
        )

    # ------------------------------------------------------------------ #
    # QR
    # ------------------------------------------------------------------ #

    def _toggle_qr(self):
        if self._qr_visible:
            self._qr_frame.pack_forget()
            for child in self._qr_frame.winfo_children():
                child.destroy()
            self.qr_btn.configure(text="Scan QR")
            self._qr_visible = False
            self.root.geometry(f"{WIDTH}x{HEIGHT}")
            return

        image = self._render_qr()
        if image is None:
            self.device_note.configure(text="Could not build a QR code.", text_color=t.PEACH)
            return

        holder = ctk.CTkFrame(self._qr_frame, fg_color=t.TEXT, corner_radius=t.RADIUS)
        holder.pack(anchor="w")
        ctk.CTkLabel(holder, image=image, text="").pack(padx=10, pady=10)

        ctk.CTkLabel(
            self._qr_frame,
            text="Scan this with the Meo Mic app on your phone",
            font=t.font("body", 11),
            text_color=t.OVERLAY,
            anchor="w",
        ).pack(fill="x", pady=(t.SM, 0))

        self._qr_frame.pack(fill="x", pady=(t.MD, 0))
        self.qr_btn.configure(text="Hide QR")
        self._qr_visible = True
        self.root.geometry(f"{WIDTH}x{HEIGHT + QR_EXTRA}")

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
            img = qr.make_image(fill_color=t.CRUST, back_color=t.TEXT).convert("RGB")
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
            self.root.after(1200, lambda: self.copy_btn.configure(text="Copy address"))

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
        if self.meter:
            self.meter.stop()
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
        if self.address_label:
            self.address_label.configure(text=f"{ip}:{port}")

    @staticmethod
    def _device_label(dev: dict) -> str:
        return f"{'▍ ' if dev['is_virtual'] else '   '}{dev['name']}"

    def set_devices(self, devices: List[dict], selected: Optional[int] = None):
        self.devices = devices
        self.selected_device = selected
        if self.root and self.device_menu:
            self.root.after(0, lambda: self._do_set_devices(devices, selected))
        else:
            self._pending_devices = (devices, selected)

    def _do_set_devices(self, devices: List[dict], selected: Optional[int]):
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

    def _update_device_note(self):
        """Say what this choice means, in the user's words - not the driver's."""
        if not self.device_note:
            return

        current = next((d for d in self.devices if d["id"] == self.selected_device), None)

        if current is None:
            self.device_note.configure(
                text="Pick where your phone's audio should go.",
                text_color=t.OVERLAY,
            )
        elif current["is_virtual"]:
            self.device_note.configure(
                text="Ready. Pick CABLE Output as the mic in Discord or Zoom.",
                text_color=t.SUBTEXT,
            )
        else:
            self.device_note.configure(
                text="Playing out loud - no app can use this as a microphone.",
                text_color=t.PEACH,
            )

    def update_status(self, connected: bool, client_ip: Optional[str] = None):
        self.is_connected = connected
        self.client_ip = client_ip
        if self.root:
            self.root.after(0, lambda: self._do_update_status(connected, client_ip))

    def _do_update_status(self, connected: bool, client_ip: Optional[str]):
        if self.status_pill:
            self.status_pill.set_state(connected)
        if self.meter:
            self.meter.set_connected(connected)
        if self.peer_label:
            if connected:
                self.peer_label.configure(text=f"Streaming from {client_ip}", text_color=t.SUBTEXT)
            else:
                self.peer_label.configure(
                    text="Waiting for a phone to connect", text_color=t.OVERLAY
                )
        if not connected and self.db_readout:
            self.db_readout.configure(text="—", text_color=t.OVERLAY)

    def update_level(self, level: float):
        """Legacy 0..1 RMS input, kept for callers that still use it."""
        import math

        self.audio_level = level
        db = 20.0 * math.log10(max(level * 10000.0 / 32768.0, 1e-6))
        self.update_level_db(db)

    def update_level_db(self, db: float):
        """Feed the meter peak dBFS."""
        if self.meter:
            self.meter.set_db(db)
        if self.root and self.db_readout and self.is_connected:
            self.root.after(0, self._do_update_readout)

    def _do_update_readout(self):
        db = self.meter.level_db if self.meter else -60.0
        if db <= LevelMeter.MIN_DB:
            self.db_readout.configure(text="−∞ dB", text_color=t.OVERLAY)
        else:
            # The meter carries the colour. The number only speaks up when the
            # level is somewhere you would want to do something about.
            color = t.TEXT
            if db >= -3:
                color = t.RED
            elif db >= -6:
                color = t.PEACH
            self.db_readout.configure(text=f"{db:5.1f} dB", text_color=color)

    def run(self):
        self.create_window()
        self.running = True
        self.root.mainloop()

    def stop(self):
        self.running = False
        if self.meter:
            self.meter.stop()
        if self.root:
            try:
                self.root.quit()
            except Exception:
                pass
