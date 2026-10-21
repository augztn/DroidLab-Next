#!/usr/bin/env python3
"""Backward-compatible bootstrap for the DroidLab desktop application."""
from droidlab.ui.main_window import *  # noqa: F403
from droidlab.ui.main_window import _windows_process_options

if __name__ == "__main__":
    main()
