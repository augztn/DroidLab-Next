#!/usr/bin/env python3
"""Backward-compatible bootstrap for the DroidLab desktop application."""
from droidlab.ui.main_window import PayloadDumperApp, main
from droidlab.ui.main_window import *  # noqa: F403
from droidlab.ui.main_window import (
    _configure_logging, _log_directory, _log_uncaught_exception, _windows_process_options
)

if __name__ == "__main__":
    main()
