"""Application logging configuration and uncaught-exception hooks."""

from __future__ import annotations

import logging
import platform
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path

from .constants import APP_NAME


def log_directory():
    """Keep logs in a clearly visible DroidLab folder inside the user's home directory."""
    return Path.home() / "DroidLab" / "logs"


def configure_logging():
    directory = log_directory()
    log_file = directory / "droidlab.log"
    logger = logging.getLogger()
    try:
        directory.mkdir(parents=True, exist_ok=True)
        # Keep exactly one file handler for this path, even if an earlier
        # startup path or packaged runtime installed duplicate handlers.
        matching = [
            handler
            for handler in logger.handlers
            if isinstance(handler, RotatingFileHandler)
            and Path(getattr(handler, "baseFilename", "")).resolve() == log_file.resolve()
        ]
        marked = [handler for handler in matching if getattr(handler, "_droidlab_handler", False)]
        keep = marked[0] if marked else (matching[0] if matching else None)
        for handler in matching:
            if handler is not keep:
                logger.removeHandler(handler)
                try:
                    handler.close()
                except OSError:
                    pass
        if keep is None:
            keep = RotatingFileHandler(
                log_file, maxBytes=2 * 1024 * 1024, backupCount=4, encoding="utf-8"
            )
            logger.addHandler(keep)
        keep._droidlab_handler = True
        keep.setFormatter(
            logging.Formatter(
                "%(asctime)s | %(levelname)s | %(threadName)s | %(name)s | %(message)s"
            )
        )
        logger.setLevel(logging.INFO)
        if not getattr(logger, "_droidlab_started", False):
            logger._droidlab_started = True
            logging.info("==== %s starting ====", APP_NAME)
            logging.info(
                "Platform: %s | Python: %s | frozen: %s",
                platform.platform(),
                sys.version.replace("\n", " "),
                bool(getattr(sys, "frozen", False)),
            )
        return log_file
    except OSError:
        logging.basicConfig(level=logging.INFO)
        logging.exception("Could not initialize file logging at %s", directory)
        return None


def log_uncaught_exception(exc_type, exc_value, exc_traceback):
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return
    logging.critical(
        "Uncaught application exception", exc_info=(exc_type, exc_value, exc_traceback)
    )
