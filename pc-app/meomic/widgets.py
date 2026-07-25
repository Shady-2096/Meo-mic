"""
Meo Mic - custom widgets.

The level meter is the centre of this app. Everything else on screen is a
setting you touch once; the meter is the only thing that answers the question
you actually opened the window to ask - "can they hear me?"

So it is built like a real one: segmented, calibrated in dBFS, with meter
ballistics (instant attack, timed release) and a peak-hold marker. Its
segments echo the ribs of the broadcast microphone in the app icon.
"""

from __future__ import annotations

import tkinter as tk
from typing import Optional

import customtkinter as ctk

from . import theme as t


class Wordmark(ctk.CTkFrame):
    """The app name, set against the grille-rib mark from the icon."""

    def __init__(self, parent, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)

        self.mark = tk.Canvas(
            self, width=16, height=18, bg=t.CRUST,
            highlightthickness=0, bd=0
        )
        self.mark.pack(side="left", padx=(0, 9), pady=(2, 0))

        # Five ribs, shortest at the top - the curve of a ribbon mic grille.
        widths = (7, 11, 14, 14, 11)
        for row, width in enumerate(widths):
            x = (16 - width) / 2
            y = 3 + row * 3
            self.mark.create_rectangle(
                x, y, x + width, y + 1.6,
                fill=t.MAUVE, outline=""
            )

        ctk.CTkLabel(
            self,
            text=t.track("MEO MIC", 1),
            font=t.font("display", 15, "bold"),
            text_color=t.TEXT,
        ).pack(side="left")


class StatusPill(ctk.CTkFrame):
    """Connection state. Reads as a lamp on an equipment panel."""

    def __init__(self, parent, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)

        self.dot = tk.Canvas(self, width=8, height=8, bg=t.CRUST,
                             highlightthickness=0, bd=0)
        self.dot.pack(side="left", padx=(0, 7), pady=(1, 0))
        self._dot_id = self.dot.create_oval(1, 1, 7, 7, fill=t.OVERLAY, outline="")

        self.label = ctk.CTkLabel(
            self,
            text=t.track("STANDBY"),
            font=t.font("display", 11),
            text_color=t.OVERLAY,
        )
        self.label.pack(side="left")

    def set_state(self, connected: bool, detail: Optional[str] = None):
        if connected:
            self.dot.itemconfig(self._dot_id, fill=t.GREEN)
            self.label.configure(text=t.track("LIVE"), text_color=t.GREEN)
        else:
            self.dot.itemconfig(self._dot_id, fill=t.OVERLAY)
            self.label.configure(text=t.track("STANDBY"), text_color=t.OVERLAY)


class LevelMeter(ctk.CTkFrame):
    """Segmented dBFS meter with ballistics and peak hold."""

    MIN_DB = -60.0
    MAX_DB = 0.0

    SEGMENTS = 30
    RELEASE_DB_PER_SEC = 26.0     # how fast the bar falls once you stop talking
    PEAK_HOLD_SECONDS = 1.1
    PEAK_FALL_DB_PER_SEC = 34.0
    FRAME_MS = 33                 # ~30 fps

    # Where the scale changes colour, in dBFS. These are the standard broadcast
    # zones: below -12 you have headroom, above -3 you are about to clip.
    ZONES = ((-3.0, t.RED), (-6.0, t.PEACH), (-12.0, t.YELLOW), (-60.0, t.GREEN))

    TICKS = (-60, -48, -36, -24, -12, -6, 0)

    def __init__(self, parent, width: int = 316, height: int = 48, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)

        self._meter_w = width
        self._meter_h = height
        self._bar_h = 22
        self._connected = False
        self._level_db = self.MIN_DB
        self._target_db = self.MIN_DB
        self._peak_db = self.MIN_DB
        self._peak_age = 0.0
        self._running = False

        self.canvas = tk.Canvas(
            self, width=width, height=height, bg=t.CRUST,
            highlightthickness=0, bd=0
        )
        self.canvas.pack()

        self._off_color = t.mix(t.SURFACE0, t.MANTLE, 0.5)
        self._segments = []
        self._segment_db = []
        self._build()

    # -- geometry ---------------------------------------------------------- #

    def _db_to_x(self, db: float) -> float:
        span = self.MAX_DB - self.MIN_DB
        fraction = (db - self.MIN_DB) / span
        return max(0.0, min(1.0, fraction)) * self._meter_w

    def _zone_color(self, db: float) -> str:
        for threshold, color in self.ZONES:
            if db >= threshold:
                return color
        return t.GREEN

    def _build(self):
        gap = 2
        seg_w = (self._meter_w - gap * (self.SEGMENTS - 1)) / self.SEGMENTS
        span = self.MAX_DB - self.MIN_DB

        # Trough, so the meter reads as recessed into the panel.
        self.canvas.create_rectangle(
            0, 0, self._meter_w, self._bar_h, fill=t.MANTLE, outline=""
        )

        for i in range(self.SEGMENTS):
            x = i * (seg_w + gap)
            # The dB this segment stands for: its right edge, so a segment only
            # lights once the signal has actually reached it.
            db = self.MIN_DB + span * ((i + 1) / self.SEGMENTS)
            self._segment_db.append(db)
            self._segments.append(
                self.canvas.create_rectangle(
                    x, 0, x + seg_w, self._bar_h,
                    fill=self._off_color, outline=""
                )
            )

        # Peak-hold marker, parked off-scale until there is signal.
        self._peak_id = self.canvas.create_rectangle(
            -4, 0, -2, self._bar_h, fill=t.OVERLAY, outline=""
        )

        # Calibrated scale. Ticks encode headroom, which is the only thing the
        # numbers here are for - they are not decoration.
        tick_y = self._bar_h + 6
        for db in self.TICKS:
            x = self._db_to_x(db)
            x = min(x, self._meter_w - 1)
            self.canvas.create_rectangle(
                x, tick_y, x + 1, tick_y + 4,
                fill=t.mix(t.OVERLAY, t.CRUST, 0.45), outline=""
            )

            if db == 0:
                anchor, label_x = "e", self._meter_w
            elif db == self.MIN_DB:
                anchor, label_x = "w", 0
            else:
                anchor, label_x = "center", x

            self.canvas.create_text(
                label_x, tick_y + 13,
                text=str(db), anchor=anchor,
                fill=t.mix(t.OVERLAY, t.CRUST, 0.3),
                font=(t.data(), 8),
            )

    # -- animation --------------------------------------------------------- #

    def start(self):
        if not self._running:
            self._running = True
            self._tick()

    def stop(self):
        self._running = False

    def set_db(self, db: float):
        """Feed the meter a dBFS value. Safe to call from any thread."""
        self._target_db = max(self.MIN_DB, min(self.MAX_DB, db))

    def set_connected(self, connected: bool):
        self._connected = connected
        if not connected:
            self._target_db = self.MIN_DB
            self._level_db = self.MIN_DB
            self._peak_db = self.MIN_DB

    def _tick(self):
        if not self._running:
            return

        step = self.FRAME_MS / 1000.0

        # Attack is instant, release is timed. That asymmetry is what makes a
        # meter readable: you catch every transient, but the bar does not
        # flicker on every syllable.
        if self._target_db >= self._level_db:
            self._level_db = self._target_db
        else:
            self._level_db = max(
                self._target_db,
                self._level_db - self.RELEASE_DB_PER_SEC * step,
            )

        if self._level_db >= self._peak_db:
            self._peak_db = self._level_db
            self._peak_age = 0.0
        else:
            self._peak_age += step
            if self._peak_age > self.PEAK_HOLD_SECONDS:
                self._peak_db = max(
                    self._level_db,
                    self._peak_db - self.PEAK_FALL_DB_PER_SEC * step,
                )

        self._redraw()

        try:
            self.after(self.FRAME_MS, self._tick)
        except Exception:
            self._running = False

    def _redraw(self):
        live = self._connected and self._level_db > self.MIN_DB

        for segment, db in zip(self._segments, self._segment_db):
            if live and self._level_db >= db:
                color = self._zone_color(db)
            else:
                color = self._off_color
            self.canvas.itemconfig(segment, fill=color)

        if live and self._peak_db > self.MIN_DB:
            x = self._db_to_x(self._peak_db)
            x = min(max(x, 2), self._meter_w)
            self.canvas.coords(self._peak_id, x - 2, 0, x, self._bar_h)
            self.canvas.itemconfig(self._peak_id, fill=self._zone_color(self._peak_db))
        else:
            self.canvas.coords(self._peak_id, -4, 0, -2, self._bar_h)

    @property
    def level_db(self) -> float:
        return self._level_db


def eyebrow(parent, text: str) -> ctk.CTkLabel:
    """A tracked, all-caps section label."""
    return ctk.CTkLabel(
        parent,
        text=t.track(text),
        font=t.font("display", 10),
        text_color=t.OVERLAY,
        anchor="w",
    )


def hairline(parent, color: str = t.LINE) -> ctk.CTkFrame:
    """A one-pixel rule."""
    return ctk.CTkFrame(parent, height=1, fg_color=color, corner_radius=0)
