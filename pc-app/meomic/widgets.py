"""
Meo Mic - custom widgets.

The waveform is the centre of this app. Everything else on screen is a setting
you touch once; the waveform is the only thing that answers the question you
opened the window to ask - "can they hear me?"

It has been a segmented dBFS meter and then a single level bar. The ballistics
underneath have never changed, because instant attack and timed release are
what make a level readable at a glance. What changed is that it now keeps the
last two seconds on screen instead of only the present instant: a flat line
means silence and a moving one means your voice is arriving, which nobody has
to be taught to read.

Matches the Mac app's waveform deliberately - same sample count, same
ballistics, same fade toward the older edge.
"""

from __future__ import annotations

import tkinter as tk
from typing import Optional

import customtkinter as ctk

from . import theme as t


class Waveform(ctk.CTkFrame):
    """A rolling level history with meter ballistics and a plain-English caption.

    Feed it dBFS with :meth:`set_db`; it handles its own animation.
    """

    MIN_DB = -60.0
    MAX_DB = 0.0

    RELEASE_DB_PER_SEC = 26.0     # how fast the level falls once you stop talking
    FRAME_MS = 33                 # ~30 fps

    SAMPLES = 58
    BAR_W = 3
    GAP = 2
    HEIGHT = 40
    FLOOR_PX = 2                  # silence is a hairline, not an empty box

    def __init__(self, parent, width: int = 320, **kwargs):
        super().__init__(parent, fg_color="transparent", **kwargs)

        self._width = width
        self._connected = False
        self._level_db = self.MIN_DB
        self._target_db = self.MIN_DB
        self._running = False
        # Derived from the width rather than fixed, so the bars fill the panel
        # exactly instead of leaving a dead strip at the right.
        self._count = max(24, int(width // (self.BAR_W + self.GAP)))
        self._samples = [0.0] * self._count

        ground = t.resolve(t.WINDOW)
        self.canvas = tk.Canvas(
            self, width=width, height=self.HEIGHT, bg=ground,
            highlightthickness=0, bd=0,
        )
        self.canvas.pack(fill="x")

        # One rectangle per sample, created once and then only moved. Recreating
        # canvas items 30 times a second is what makes Tk animations stutter.
        self._bars = []
        for index in range(self._count):
            x = index * (self.BAR_W + self.GAP)
            mid = self.HEIGHT / 2
            self._bars.append(
                self.canvas.create_rectangle(
                    x, mid - 1, x + self.BAR_W, mid + 1,
                    fill=t.resolve(t.TEXT_TERTIARY), outline="",
                )
            )

        self.caption = ctk.CTkLabel(
            self,
            text="No sound yet",
            font=t.font("label", 11),
            text_color=t.TEXT_SECONDARY,
            anchor="w",
        )
        self.caption.pack(fill="x", pady=(t.SM, 0))

    # -- appearance -------------------------------------------------------- #

    def refresh_theme(self):
        """Re-resolve colours after the appearance mode changes."""
        self.canvas.configure(bg=t.resolve(t.WINDOW))
        self._redraw()

    def _bar_color(self) -> str:
        if not self._connected:
            return t.resolve(t.TEXT_TERTIARY)
        if self._level_db >= -3:
            return t.resolve(t.WARN)
        return t.resolve(t.ACCENT)

    def _caption_for(self, db: float) -> tuple:
        """What the level means, in the words of someone about to join a call."""
        if not self._connected:
            return "No sound yet", t.TEXT_SECONDARY
        if db < -50:
            return "Very quiet - say something", t.TEXT_SECONDARY
        if db < -30:
            return "A little quiet", t.TEXT_SECONDARY
        if db < -6:
            return "Sounds good", t.TEXT_SECONDARY
        if db < -3:
            return "Getting loud", t.TEXT_SECONDARY
        return "Too loud - turn it down on your phone", t.WARN

    # -- animation --------------------------------------------------------- #

    def start(self):
        if not self._running:
            self._running = True
            self._tick()

    def stop(self):
        self._running = False

    def set_db(self, db: float):
        """Feed the waveform a dBFS value. Safe to call from any thread."""
        self._target_db = max(self.MIN_DB, min(self.MAX_DB, db))

    def set_connected(self, connected: bool):
        self._connected = connected
        if not connected:
            self._target_db = self.MIN_DB
            self._level_db = self.MIN_DB
        self._redraw()

    def _tick(self):
        if not self._running:
            return

        step = self.FRAME_MS / 1000.0

        # Attack is instant, release is timed. That asymmetry is what makes a
        # level readable: you catch every transient, but it does not flicker on
        # every syllable.
        if self._target_db >= self._level_db:
            self._level_db = self._target_db
        else:
            self._level_db = max(
                self._target_db,
                self._level_db - self.RELEASE_DB_PER_SEC * step,
            )

        span = self.MAX_DB - self.MIN_DB
        sample = (self._level_db - self.MIN_DB) / span if self._connected else 0.0

        self._samples.pop(0)
        self._samples.append(max(0.0, min(1.0, sample)))

        self._redraw()

        try:
            self.after(self.FRAME_MS, self._tick)
        except Exception:
            self._running = False

    def _redraw(self):
        color = self._bar_color()
        mid = self.HEIGHT / 2

        for index, item in enumerate(self._bars):
            height = max(self.FLOOR_PX, self._samples[index] * self.HEIGHT)
            x = index * (self.BAR_W + self.GAP)
            self.canvas.coords(item, x, mid - height / 2, x + self.BAR_W, mid + height / 2)
            self.canvas.itemconfigure(item, fill=color)

        text, text_color = self._caption_for(self._level_db)
        if self.caption.cget("text") != text:
            self.caption.configure(text=text, text_color=text_color)

    def resize(self, width: int):
        self._width = width
        self.canvas.configure(width=width)

    @property
    def level_db(self) -> float:
        return self._level_db


# Older call sites imported the level bar under its previous name.
VoiceBar = Waveform


class StatusGlyph(ctk.CTkFrame):
    """A round tinted badge holding the connection state. Green when live."""

    SIZE = 30

    def __init__(self, parent, **kwargs):
        super().__init__(
            parent,
            width=self.SIZE,
            height=self.SIZE,
            corner_radius=self.SIZE // 2,
            fg_color=t.CONTROL,
            **kwargs,
        )
        self.pack_propagate(False)

        self._label = ctk.CTkLabel(
            self,
            text="○",
            font=t.font("label", 13, "bold"),
            text_color=t.TEXT_SECONDARY,
        )
        self._label.pack(expand=True)

    def set_live(self, live: bool):
        # Tk has no alpha, so the tinted badge is a precomputed blend.
        self.configure(fg_color=t.mix(t.LIVE, t.WINDOW, 0.82) if live else t.CONTROL)
        self._label.configure(
            text="●" if live else "○",
            text_color=t.LIVE if live else t.TEXT_SECONDARY,
        )


# Older call sites imported the dot under its previous name.
StatusDot = StatusGlyph


def card(parent) -> ctk.CTkFrame:
    """An inset grouped container - the only box in the window."""
    return ctk.CTkFrame(
        parent,
        fg_color=t.CARD,
        corner_radius=t.RADIUS_LG,
        border_width=1,
        border_color=t.BORDER,
    )


def separator(parent) -> ctk.CTkFrame:
    """A row separator inside a grouped card."""
    return ctk.CTkFrame(parent, height=1, fg_color=t.SEPARATOR, corner_radius=0)


def field_label(parent, text: str) -> ctk.CTkLabel:
    """A quiet, sentence-case label."""
    return ctk.CTkLabel(
        parent,
        text=text,
        font=t.font("label", 11),
        text_color=t.TEXT_TERTIARY,
        anchor="w",
    )


def hairline(parent, color=None) -> ctk.CTkFrame:
    """A one-pixel rule."""
    return ctk.CTkFrame(parent, height=1, fg_color=color or t.BORDER, corner_radius=0)


def inline_note(parent, text: str, tint=None, wraplength: Optional[int] = None) -> ctk.CTkLabel:
    """An advisory line, in the flow, where the problem is."""
    return ctk.CTkLabel(
        parent,
        text=text,
        font=t.font("label", 11),
        text_color=tint or t.TEXT_SECONDARY,
        anchor="w",
        justify="left",
        wraplength=wraplength or 300,
    )
