"""
Meo Mic - custom widgets.

The voice bar is the centre of this app. Everything else on screen is a setting
you touch once; the bar is the only thing that answers the question you opened
the window to ask - "can they hear me?"

It replaced a segmented, tick-marked dBFS meter. The ballistics are unchanged,
because instant attack and timed release are what make a level readable at a
glance. What changed is that it no longer asks a person joining a Zoom call to
read a calibrated scale: one continuous bar, one colour at a time, and a
sentence underneath saying what it means.
"""

from __future__ import annotations

import tkinter as tk
from typing import Optional

import customtkinter as ctk

from . import theme as t


class StatusDot(tk.Canvas):
    """A small filled dot. Grey while waiting, green while live."""

    SIZE = 10

    def __init__(self, parent, bg: str = t.WINDOW, **kwargs):
        super().__init__(
            parent, width=self.SIZE, height=self.SIZE, bg=bg,
            highlightthickness=0, bd=0, **kwargs
        )
        self._dot = self.create_oval(1, 1, self.SIZE - 1, self.SIZE - 1,
                                     fill=t.TEXT_TERTIARY, outline="")

    def set_live(self, live: bool):
        self.itemconfig(self._dot, fill=t.LIVE if live else t.TEXT_TERTIARY)


class VoiceBar(ctk.CTkFrame):
    """A continuous level bar with meter ballistics and a plain-English caption.

    Feed it dBFS with :meth:`set_db`; it handles its own animation.
    """

    MIN_DB = -60.0
    MAX_DB = 0.0

    RELEASE_DB_PER_SEC = 26.0     # how fast the bar falls once you stop talking
    FRAME_MS = 33                 # ~30 fps

    HEIGHT = 12

    def __init__(self, parent, width: int = 336, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)

        self._width = width
        self._connected = False
        self._level_db = self.MIN_DB
        self._target_db = self.MIN_DB
        self._running = False

        self.canvas = tk.Canvas(
            self, width=width, height=self.HEIGHT, bg=t.WINDOW,
            highlightthickness=0, bd=0
        )
        self.canvas.pack(fill="x")

        self._track = self._rounded(0, 0, width, self.HEIGHT, t.CARD)
        self._fill = self._rounded(0, 0, 1, self.HEIGHT, t.LIVE)
        self.canvas.itemconfigure(self._fill, state="hidden")

        self.caption = ctk.CTkLabel(
            self,
            text="No sound yet",
            font=t.font("label", 11),
            text_color=t.TEXT_TERTIARY,
            anchor="w",
        )
        self.caption.pack(fill="x", pady=(t.SM, 0))

    # -- drawing ----------------------------------------------------------- #

    def _rounded(self, x0, y0, x1, y1, color):
        """A capsule. Tk has no rounded rectangle, so it is drawn as one."""
        radius = (y1 - y0) / 2
        return self.canvas.create_polygon(
            self._capsule_points(x0, y0, x1, y1, radius),
            fill=color, outline="", smooth=True,
        )

    @staticmethod
    def _capsule_points(x0, y0, x1, y1, r):
        return [
            x0 + r, y0,
            x1 - r, y0, x1, y0, x1, y0 + r,
            x1, y1 - r, x1, y1, x1 - r, y1,
            x0 + r, y1, x0, y1, x0, y1 - r,
            x0, y0 + r, x0, y0,
        ]

    def _level_color(self, db: float) -> str:
        if db >= -3:
            return t.ERROR
        if db >= -6:
            return t.HOT
        if db >= -12:
            return t.WARN
        return t.LIVE

    def _caption_for(self, db: float) -> tuple:
        """What the level means, in the words of someone about to join a call."""
        if not self._connected:
            return "No sound yet", t.TEXT_TERTIARY
        if db < -50:
            return "Very quiet - say something", t.TEXT_TERTIARY
        if db < -30:
            return "A little quiet", t.TEXT_SECONDARY
        if db < -6:
            return "Sounds good", t.TEXT_SECONDARY
        if db < -3:
            return "Getting loud", t.TEXT_SECONDARY
        return "Too loud - turn the volume down on your phone", t.HOT

    # -- animation --------------------------------------------------------- #

    def start(self):
        if not self._running:
            self._running = True
            self._tick()

    def stop(self):
        self._running = False

    def set_db(self, db: float):
        """Feed the bar a dBFS value. Safe to call from any thread."""
        self._target_db = max(self.MIN_DB, min(self.MAX_DB, db))

    def set_connected(self, connected: bool):
        self._connected = connected
        if not connected:
            self._target_db = self.MIN_DB
            self._level_db = self.MIN_DB
        # Repaint now rather than on the next frame: a state change the person
        # just caused should not wait 33ms to appear.
        self._redraw()

    def _tick(self):
        if not self._running:
            return

        step = self.FRAME_MS / 1000.0

        # Attack is instant, release is timed. That asymmetry is what makes a
        # level readable: you catch every transient, but the bar does not
        # flicker on every syllable.
        if self._target_db >= self._level_db:
            self._level_db = self._target_db
        else:
            self._level_db = max(
                self._target_db,
                self._level_db - self.RELEASE_DB_PER_SEC * step,
            )

        self._redraw()

        try:
            self.after(self.FRAME_MS, self._tick)
        except Exception:
            self._running = False

    def _redraw(self):
        live = self._connected and self._level_db > self.MIN_DB

        if live:
            span = self.MAX_DB - self.MIN_DB
            fraction = (self._level_db - self.MIN_DB) / span
            width = max(self.HEIGHT, fraction * self._width)
            self.canvas.coords(
                self._fill,
                *self._capsule_points(0, 0, width, self.HEIGHT, self.HEIGHT / 2),
            )
            self.canvas.itemconfigure(
                self._fill, state="normal", fill=self._level_color(self._level_db)
            )
        else:
            self.canvas.itemconfigure(self._fill, state="hidden")

        text, color = self._caption_for(self._level_db)
        if self.caption.cget("text") != text:
            self.caption.configure(text=text, text_color=color)

    def resize(self, width: int):
        self._width = width
        self.canvas.configure(width=width)
        self.canvas.coords(
            self._track, *self._capsule_points(0, 0, width, self.HEIGHT, self.HEIGHT / 2)
        )

    @property
    def level_db(self) -> float:
        return self._level_db


def field_label(parent, text: str) -> ctk.CTkLabel:
    """A quiet, sentence-case label above a control."""
    return ctk.CTkLabel(
        parent,
        text=text,
        font=t.font("label", 11),
        text_color=t.TEXT_TERTIARY,
        anchor="w",
    )


def hairline(parent, color: str = t.BORDER) -> ctk.CTkFrame:
    """A one-pixel rule."""
    return ctk.CTkFrame(parent, height=1, fg_color=color, corner_radius=0)
