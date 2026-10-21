"""Backward-compatible module alias for :mod:`droidlab.core.command_guards`."""
from __future__ import annotations

import sys as _sys

from droidlab.core import command_guards as _implementation
from droidlab.core.command_guards import *  # noqa: F401,F403

# Preserve legacy private helper access and unittest.mock patch targets.
_sys.modules[__name__] = _implementation
