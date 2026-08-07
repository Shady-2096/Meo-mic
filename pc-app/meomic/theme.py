"""
Meo Mic - design tokens for the Windows app.

Every colour is a ``(light, dark)`` pair, which is what CustomTkinter widgets
take directly, and the app runs in ``System`` appearance mode so it follows the
Windows light/dark setting. That mirrors the Mac app's move to AppKit semantic
colours: a hand-rolled dark-only palette is the most reliable tell that an app
is not really a native app.

Values are Windows 11's own layer and text colours rather than Catppuccin,
which the Android app still uses. Sharing a product does not mean sharing a
palette across operating systems that disagree about what a window looks like.

Raw ``tkinter`` widgets - the waveform canvas - cannot take a pair, so pass
them through :func:`resolve` first.
"""

from __future__ import annotations

import sys
from typing import Sequence

Color = tuple  # (light, dark)

# --------------------------------------------------------------------------- #
# Colour
# --------------------------------------------------------------------------- #

# Grounds and layers, following Windows 11's layering model: the window sits
# lowest, cards sit one layer above it, controls one above that.
WINDOW = ("#F3F3F3", "#202024")
CARD = ("#FFFFFF", "#2A2A30")
CARD_HOVER = ("#F0F0F0", "#33333A")
BORDER = ("#E1E1E4", "#38383F")
SEPARATOR = ("#EAEAED", "#313138")

CONTROL = ("#FBFBFB", "#313138")
CONTROL_HOVER = ("#F0F0F0", "#3B3B43")

TEXT = ("#1B1B1F", "#F3F3F6")
TEXT_SECONDARY = ("#5C5C63", "#A9A9B2")
TEXT_TERTIARY = ("#7A7A83", "#8B8B94")

# Windows' own status colours, each side of the pair chosen to clear 4.5:1 on
# its own ground.
LIVE = ("#0F7B0F", "#6CCB5F")
WARN = ("#9A5B00", "#FCC934")
HOT = ("#9A5B00", "#FFB959")
ERROR = ("#C42B1C", "#FF99A4")


def _windows_accent() -> Color:
    """The user's own Windows accent colour, or the system default.

    Windows stores it as an ABGR DWORD. Reading it is the closest equivalent to
    the Mac app taking ``Color.accentColor``, and it is what makes the window
    look like it belongs to this particular desktop rather than to us.
    """
    default = ("#0067C0", "#4CC2FF")
    if sys.platform != "win32":
        return default
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\DWM") as key:
            raw, _ = winreg.QueryValueEx(key, "ColorizationColor")
        red = (raw >> 16) & 0xFF
        green = (raw >> 8) & 0xFF
        blue = raw & 0xFF
        # The stored colour is tuned for a dark ground; darken it for light
        # mode so text on top of it keeps its contrast.
        light = "#%02x%02x%02x" % (int(red * 0.72), int(green * 0.72), int(blue * 0.72))
        dark = "#%02x%02x%02x" % (red, green, blue)
        return (light, dark)
    except Exception:
        return default


ACCENT = _windows_accent()
ACCENT_HOVER = ACCENT

# Legacy role names. The setup wizard still speaks in these; they map onto the
# roles above rather than defining new colours.
CRUST = WINDOW
MANTLE = WINDOW
BASE = CARD
SURFACE = CARD_HOVER
SURFACE0 = CARD_HOVER
SURFACE1 = CONTROL_HOVER
SURFACE2 = BORDER
SUBTEXT = TEXT_SECONDARY
OVERLAY = TEXT_TERTIARY
MAUVE = ACCENT
LAVENDER = ACCENT_HOVER
GREEN = LIVE
YELLOW = WARN
PEACH = HOT
RED = ERROR
LINE = BORDER


def resolve(color, mode: str | None = None) -> str:
    """Flatten a ``(light, dark)`` pair to one hex string.

    Needed wherever a raw ``tkinter`` widget is involved, since only
    CustomTkinter understands pairs.
    """
    if not isinstance(color, (tuple, list)):
        return color
    if mode is None:
        try:
            import customtkinter as ctk

            mode = ctk.get_appearance_mode()
        except Exception:
            mode = "Dark"
    return color[1] if str(mode).lower() == "dark" else color[0]


def mix(color_a, color_b, amount: float) -> str:
    """Blend two colours. Tk has no alpha, so blends are precomputed."""
    amount = max(0.0, min(1.0, amount))
    a_hex, b_hex = resolve(color_a), resolve(color_b)
    a = tuple(int(a_hex[i:i + 2], 16) for i in (1, 3, 5))
    b = tuple(int(b_hex[i:i + 2], 16) for i in (1, 3, 5))
    blended = tuple(round(x + (y - x) * amount) for x, y in zip(a, b))
    return "#%02x%02x%02x" % blended


def dim(color, amount: float = 0.7) -> str:
    """Push a colour towards the window ground."""
    return mix(color, WINDOW, amount)


# --------------------------------------------------------------------------- #
# Type
# --------------------------------------------------------------------------- #
#
# One family: whatever Windows uses for its own interface. A utility window
# does not need a display face, and monospace here would be a costume.
#
#   STATUS  18 bold     the one status line
#   ADDRESS 17 bold     the address while waiting
#   BODY    13 regular  row labels, supporting sentences
#   LABEL   11 regular  captions, footer

_UI_STACK = (
    "Segoe UI Variable Display",  # Windows 11
    "Segoe UI Variable Text",
    "Segoe UI",                   # Windows 10
    "SF Pro Text",                # macOS, when running from source
    "Helvetica Neue",
    "DejaVu Sans",
)

_resolved: dict = {}


def _resolve_family(stack: Sequence[str], fallback: str) -> str:
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
    return _resolve_family(_UI_STACK, "Segoe UI" if sys.platform == "win32" else "Helvetica")


# Kept so older call sites keep resolving; every role is the same family.
def display() -> str:
    return ui_family()


def body() -> str:
    return ui_family()


def font(role: str = "body", size: int = 13, weight: str = "normal"):
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
XL = 24

PAD = 20        # window side gutter
RADIUS = 6      # controls
RADIUS_LG = 8   # cards, following Windows 11's corner radius
