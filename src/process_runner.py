"""Backward-compatible module alias for :mod:`droidlab.core.process_runner`."""
from __future__ import annotations
import sys as _sys
from droidlab.core import process_runner as _implementation
from droidlab.core.process_runner import *  # noqa: F401,F403

# Preserve legacy private helper access and unittest.mock patch targets.
_sys.modules[__name__] = _implementation
