"""Backward-compatible module alias for :mod:`droidlab.core.payload_dumper`."""
from __future__ import annotations

import sys as _sys

from droidlab.core import payload_dumper as _implementation
from droidlab.core.payload_dumper import *  # noqa: F401,F403

# Preserve legacy private helper access and unittest.mock patch targets.
_sys.modules[__name__] = _implementation
