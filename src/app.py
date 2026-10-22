#!/usr/bin/env python3
"""Backward-compatible bootstrap for the DroidLab desktop application."""

from droidlab.ui.main_window import *  # noqa: F403
from droidlab.ui.main_window import (
    PayloadDumperApp,  # noqa: F401
    _configure_logging,  # noqa: F401
    _log_directory,  # noqa: F401
    _log_uncaught_exception,  # noqa: F401
    _windows_process_options,  # noqa: F401
    main,
)

if __name__ == "__main__":
    main()
