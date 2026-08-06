"""
Meo Mic - design tokens.

The Android app is themed Catppuccin Mocha, so the desktop apps use the same
palette: one product, one identity. Nothing here invents a new colour.

Two rules give the interface its character:

    Chrome is achromatic. Saturated colour belongs to the signal.
    Type is the operating system's own UI face, in sentence case.

An idle Meo Mic is grey. The moment your voice arrives, the bar lights up.
That makes "is it working?" answerable from across the desk, out of focus,
without reading a word.
"""

from __future__ import annotations

import sys
from typing import Sequence

# --------------------------------------------------------------------------- #
# Colour - Catppuccin Mocha, addressed by role
# --------------------------------------------------------------------------- #

WINDOW = "#11111B"      # window ground
CARD = "#1E1E2E"        # raised card, control fill
CARD_HOVER = "#313244"  # control hover
BORDER = "#282839"      # hairlines, card outline

TEXT = "#CDD6F4"        # primary type
TEXT_SECONDARY = "#A6ADC8"
# Catppuccin Overlay2, not Overlay0. Labels and captions are set at 11px, and
# Overlay0 measures 3.4:1 against the card - under AA for small text.
TEXT_TERTIARY = "#9399B2"

ACCENT = "#CBA6F7"      # primary action, focus, brand. Never a status colour.
ACCENT_HOVER = "#B4BEFE"

LIVE = "#A6E3A1"        # connected, healthy level
WARN = "#F9E2AF"        # level getting hot
HOT = "#FAB387"         # level near clipping, soft warnings
ERROR = "#F38BA8"       # errors, clipping

# Legacy names. The setup wizard, QR and help windows still speak in these;
# they map onto the roles above rather than defining new colours.
CRUST = WINDOW
MANTLE = "#181825"
BASE = CARD
SURFACE0 = CARD_HOVER
SURFACE1 = "#45475A"
SURFACE2 = "#585B70"
SUBTEXT = TEXT_SECONDARY
OVERLAY = TEXT_TERTIARY
MAUVE = ACCENT
LAVENDER = ACCENT_HOVER
GREEN = LIVE
YELLOW = WARN
PEACH = HOT
RED = ERROR
LINE = BORDER


def mix(color_a: str, color_b: str, amount: float) -> str:
    """Blend two hex colours. Tk has no alpha, so blends are precomputed."""
    amount = max(0.0, min(1.0, amount))
    a = tuple(int(color_a[i:i + 2], 16) for i in (1, 3, 5))
    b = tuple(int(color_b[i:i + 2], 16) for i in (1, 3, 5))
    blended = tuple(round(x + (y - x) * amount) for x, y in zip(a, b))
    return "#%02x%02x%02x" % blended


def dim(color: str, amount: float = 0.7) -> str:
    """Push a colour towards the window ground."""
    return mix(color, WINDOW, amount)


# --------------------------------------------------------------------------- #
# Type
# --------------------------------------------------------------------------- #
#
# One family: whatever the operating system uses for its own interface. A
# utility window does not need a display face, and monospace here would be a
# costume - there is no code and no column of figures to align.
#
#   STATUS  19 bold     the one status sentence
#   TITLE   14 bold     card titles
#   BODY    12 regular  supporting sentences, controls
#   LABEL   11 regular  field labels, captions, footer

_UI_STACK = (
    "Segoe UI Variable Text",   # Windows 11
    "Segoe UI",                 # Windows 10
    "SF Pro Text",              # macOS, when running from source
    "Helvetica Neue",
    "DejaVu Sans",
)

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


def ui_family() -> str:
    return _resolve(_UI_STACK, "Segoe UI" if sys.platform == "win32" else "Helvetica")


# Kept so older call sites keep resolving; every role is now the same family.
def display() -> str:
    return ui_family()


def body() -> str:
    return ui_family()


def font(role: str = "body", size: int = 12, weight: str = "normal"):
    """Build a CTkFont. *role* is accepted for call-site readability only."""
    import customtkinter as ctk

    return ctk.CTkFont(family=ui_family(), size=size, weight=weight)


# --------------------------------------------------------------------------- #
# Spacing - a 4px base grid
# --------------------------------------------------------------------------- #

XS = 4
SM = 8
MD = 12
LG = 18
XL = 26

PAD = 22        # window side gutter
RADIUS = 8      # controls
RADIUS_LG = 10  # cards
