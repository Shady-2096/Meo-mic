"""
Meo Mic - Design tokens.

The Android app is themed Catppuccin Mocha, so the desktop app uses the same
palette: one product, one identity. Nothing here invents a new colour.

The rule that gives the interface its character:

    Chrome is achromatic. Saturated colour belongs to the signal.

An idle Meo Mic is grey. The moment your voice arrives, the meter lights up.
That makes "is it working?" answerable from across the desk, out of focus,
without reading a word.
"""

from __future__ import annotations

import sys
from typing import Optional, Sequence

# --------------------------------------------------------------------------- #
# Colour - Catppuccin Mocha
# --------------------------------------------------------------------------- #

CRUST = "#11111B"       # window base
MANTLE = "#181825"      # recessed wells (meter trough)
BASE = "#1E1E2E"        # raised panels
SURFACE0 = "#313244"    # control fill, unlit meter segment
SURFACE1 = "#45475A"    # control fill (hover), hairlines on raised panels
SURFACE2 = "#585B70"

TEXT = "#CDD6F4"        # primary type
SUBTEXT = "#A6ADC8"     # secondary type
OVERLAY = "#6C7086"     # labels, ticks, disabled

MAUVE = "#CBA6F7"       # brand accent - wordmark and focus only, never status
LAVENDER = "#B4BEFE"

# The signal ramp. Segment colour follows headroom, the way a real meter reads.
GREEN = "#A6E3A1"       # plenty of headroom
YELLOW = "#F9E2AF"      # getting warm
PEACH = "#FAB387"       # hot
RED = "#F38BA8"         # clipping

LINE = "#282839"        # hairline rules on the window base


def mix(color_a: str, color_b: str, amount: float) -> str:
    """Blend two hex colours. Tk has no alpha, so blends are precomputed."""
    amount = max(0.0, min(1.0, amount))
    a = tuple(int(color_a[i:i + 2], 16) for i in (1, 3, 5))
    b = tuple(int(color_b[i:i + 2], 16) for i in (1, 3, 5))
    blended = tuple(round(x + (y - x) * amount) for x, y in zip(a, b))
    return "#%02x%02x%02x" % blended


def dim(color: str, amount: float = 0.7) -> str:
    """Push a colour towards the window base."""
    return mix(color, CRUST, amount)


# --------------------------------------------------------------------------- #
# Type
# --------------------------------------------------------------------------- #
#
# Three roles, resolved against what the OS actually has installed:
#
#   DISPLAY  Bahnschrift - the condensed DIN-descended signage face Microsoft
#            ships with Windows. Used all-caps, tracked out, for the wordmark
#            and section labels. It reads as equipment panel lettering, which
#            is exactly what this window is.
#   DATA     Consolas / Menlo - tabular figures. IP addresses, dB values and
#            percentages change constantly; monospaced digits keep the layout
#            from twitching as they do.
#   BODY     Segoe UI / SF Pro - sentence-case prose, nothing more.

_DISPLAY_STACK = ("Bahnschrift", "Bahnschrift SemiCondensed", "Avenir Next Condensed",
                  "Oswald", "Segoe UI Semibold", "Helvetica Neue", "DejaVu Sans")
_DATA_STACK = ("Cascadia Mono", "Consolas", "SF Mono", "Menlo", "DejaVu Sans Mono", "Courier New")
_BODY_STACK = ("Segoe UI Variable Text", "Segoe UI", "SF Pro Text", "Helvetica Neue", "DejaVu Sans")

_resolved: dict = {}


def _resolve(stack: Sequence[str], fallback: str) -> str:
    """Return the first installed family in *stack*."""
    key = id(stack)
    if key in _resolved:
        return _resolved[key]

    chosen = fallback
    try:
        from tkinter import font as tkfont

        available = {name.lower() for name in tkfont.families()}
        for family in stack:
            if family.lower() in available:
                chosen = family
                break
    except Exception:
        pass

    _resolved[key] = chosen
    return chosen


def display() -> str:
    return _resolve(_DISPLAY_STACK, "Segoe UI" if sys.platform == "win32" else "Helvetica")


def data() -> str:
    return _resolve(_DATA_STACK, "Courier New")


def body() -> str:
    return _resolve(_BODY_STACK, "Segoe UI" if sys.platform == "win32" else "Helvetica")


def font(role: str = "body", size: int = 12, weight: str = "normal"):
    """Build a CTkFont for a role."""
    import customtkinter as ctk

    family = {"display": display, "data": data, "body": body}[role]()
    return ctk.CTkFont(family=family, size=size, weight=weight)


def track(text: str, spaces: int = 1) -> str:
    """Fake letter-spacing.

    Tk fonts have no tracking, so tracked labels are built by inserting
    spaces. Only for short all-caps eyebrows - never for prose.
    """
    gap = " " * spaces
    return gap.join(text)


# --------------------------------------------------------------------------- #
# Spacing - a 4px base grid
# --------------------------------------------------------------------------- #

XS = 4
SM = 8
MD = 12
LG = 18
XL = 26

PAD = 22        # window side gutter
RADIUS = 8      # default corner radius
RADIUS_LG = 12
