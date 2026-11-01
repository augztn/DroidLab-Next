import errno
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from droidlab.core.file_transfer import (
    ensure_pull_target_is_new,
    publish_file_no_replace,
    validate_android_path,
    validate_pull_directory,
    validate_push_source,
)


class FileTransferValidationTests(unittest.TestCase):
    def test_android_path_requires_absolute_non_traversal_path(self):
        self.assertEqual(validate_android_path("/sdcard/Download/file.zip", "remote"), "/sdcard/Download/file.zip")
        for value in ("relative/file", "/sdcard/../data", "/", "-s"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_android_path(value, "remote")

    def test_push_source_must_be_a_regular_file(self):
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "payload.bin"
            file_path.write_bytes(b"payload")
            self.assertEqual(validate_push_source(str(file_path)), file_path.resolve())
            with self.assertRaises(ValueError):
                validate_push_source(directory)

    def test_pull_publication_falls_back_when_hard_links_are_unsupported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            staged = root / "staged.bin"
            published = root / "published.bin"
            staged.write_bytes(b"payload")
            with patch(
                "droidlab.core.file_transfer.os.link",
                side_effect=OSError(errno.EOPNOTSUPP, "hard links unsupported"),
            ):
                publish_file_no_replace(staged, published)
            self.assertEqual(published.read_bytes(), b"payload")

    def test_pull_publication_never_overwrites_existing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            staged = root / "staged.bin"
            published = root / "published.bin"
            staged.write_bytes(b"new")
            published.write_bytes(b"old")
            with self.assertRaises(FileExistsError):
                publish_file_no_replace(staged, published)
            self.assertEqual(published.read_bytes(), b"old")

    def test_pull_directory_refuses_existing_target(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = validate_pull_directory(directory)
            ensure_pull_target_is_new("/sdcard/Download/new.zip", destination)
            (destination / "existing.zip").write_bytes(b"old")
            with self.assertRaises(FileExistsError):
                ensure_pull_target_is_new("/sdcard/Download/existing.zip", destination)


if __name__ == "__main__":
    unittest.main()
