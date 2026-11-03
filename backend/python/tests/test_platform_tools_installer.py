import hashlib
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import droidlab.core.platform_tools_installer as installer
from droidlab.core.platform_tools_installer import (
    PLATFORM_TOOLS_VERSION,
    install_platform_tools,
    managed_platform_tools_dir,
)


def archive_bytes(platform_name="darwin"):
    suffix = ".exe" if platform_name == "win32" else ""
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as bundle:
        for name, content in (
            ("platform-tools/", ""),
            (f"platform-tools/adb{suffix}", b"adb-stub"),
            (f"platform-tools/fastboot{suffix}", b"fastboot-stub"),
        ):
            entry = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            bundle.writestr(entry, content)
    return output.getvalue()


class FakeResponse:
    def __init__(self, data):
        self._stream = io.BytesIO(data)
        self.headers = {"Content-Length": str(len(data))}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self._stream.close()

    def read(self, size=-1):
        return self._stream.read(size)

    def geturl(self):
        return "https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip"


class PlatformToolsInstallerTests(unittest.TestCase):
    def setUp(self):
        self._checksums = patch.dict(installer.PLATFORM_TOOLS_SHA256, {
            "darwin": hashlib.sha256(archive_bytes("darwin")).hexdigest(),
            "win32": hashlib.sha256(archive_bytes("win32")).hexdigest(),
        })
        self._checksums.start()
        self.addCleanup(self._checksums.stop)

    def test_release_archives_are_version_pinned_and_sha256_pinned(self):
        self.assertEqual(
            installer.DOWNLOAD_URLS["win32"],
            "https://dl.google.com/android/repository/platform-tools_r37.0.1-win.zip",
        )
        self.assertEqual(
            installer.DOWNLOAD_URLS["darwin"],
            "https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip",
        )
        for digest in installer.PLATFORM_TOOLS_SHA256.values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")

    def test_managed_paths_are_user_scoped_and_versioned(self):
        home = Path("/Users/example")
        self.assertEqual(
            managed_platform_tools_dir(platform_name="darwin", home=home),
            home / "Library/Application Support/DroidLab/platform-tools" / PLATFORM_TOOLS_VERSION,
        )
        self.assertEqual(
            managed_platform_tools_dir(
                platform_name="win32",
                home=home,
                environment={"LOCALAPPDATA": "C:/Users/example/AppData/Local"},
            ),
            Path("C:/Users/example/AppData/Local/DroidLab/platform-tools") / PLATFORM_TOOLS_VERSION,
        )

    def test_install_requires_explicit_license_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(PermissionError):
                install_platform_tools(
                    license_accepted=False,
                    platform_name="darwin",
                    install_dir=Path(directory) / "platform-tools",
                )

    def test_download_installs_only_after_both_tools_pass_version_probe(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "platform-tools" / PLATFORM_TOOLS_VERSION
            probe_calls = []

            def probe(path, args):
                probe_calls.append((path.name, args))
                return f"Android Debug Bridge version {PLATFORM_TOOLS_VERSION}"

            result = install_platform_tools(
                license_accepted=True,
                platform_name="darwin",
                install_dir=destination,
                opener=lambda *_args, **_kwargs: FakeResponse(archive_bytes()),
                version_probe=probe,
            )
            self.assertTrue(result["installed"])
            self.assertFalse(result["already_installed"])
            self.assertEqual(len(probe_calls), 2)
            self.assertTrue((destination / "adb").is_file())
            self.assertTrue((destination / "fastboot").is_file())

    def test_windows_archive_installs_executable_names(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "platform-tools" / PLATFORM_TOOLS_VERSION
            with patch("droidlab.core.platform_tools_installer.platform.machine", return_value="AMD64"):
                result = install_platform_tools(
                    license_accepted=True,
                    platform_name="win32",
                    install_dir=destination,
                    opener=lambda *_args, **_kwargs: FakeResponse(archive_bytes("win32")),
                    version_probe=lambda *_args: f"fastboot version {PLATFORM_TOOLS_VERSION}",
                )
            self.assertTrue(result["installed"])
            self.assertTrue((destination / "adb.exe").is_file())
            self.assertTrue((destination / "fastboot.exe").is_file())

    def test_invalid_version_does_not_publish_install(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "platform-tools" / PLATFORM_TOOLS_VERSION
            with self.assertRaisesRegex(RuntimeError, "expected Platform-Tools version"):
                install_platform_tools(
                    license_accepted=True,
                    platform_name="darwin",
                    install_dir=destination,
                    opener=lambda *_args, **_kwargs: FakeResponse(archive_bytes()),
                    version_probe=lambda *_args: "unexpected version",
                )
            self.assertFalse(destination.exists())

    def test_zip_slip_entries_are_rejected(self):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as bundle:
            bundle.writestr("platform-tools/adb", b"stub")
            bundle.writestr("platform-tools/../../outside", b"bad")
        payload = output.getvalue()

        class Response(FakeResponse):
            def geturl(self):
                return "https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip"

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "tools" / PLATFORM_TOOLS_VERSION
            with patch.dict(installer.PLATFORM_TOOLS_SHA256, {
                "darwin": hashlib.sha256(payload).hexdigest(),
            }):
                with self.assertRaisesRegex(RuntimeError, "path traversal"):
                    install_platform_tools(
                        license_accepted=True,
                        platform_name="darwin",
                        install_dir=destination,
                        opener=lambda *_args, **_kwargs: Response(payload),
                        version_probe=lambda *_args: PLATFORM_TOOLS_VERSION,
                    )
            self.assertFalse(destination.exists())

    def test_checksum_mismatch_rejects_archive_before_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "tools" / PLATFORM_TOOLS_VERSION
            with patch.dict(installer.PLATFORM_TOOLS_SHA256, {"darwin": "0" * 64}):
                with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                    install_platform_tools(
                        license_accepted=True,
                        platform_name="darwin",
                        install_dir=destination,
                        opener=lambda *_args, **_kwargs: FakeResponse(archive_bytes()),
                        version_probe=lambda *_args: PLATFORM_TOOLS_VERSION,
                    )
            self.assertFalse(destination.exists())

    def test_interrupted_install_backup_is_restored_before_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "tools"
            destination = parent / PLATFORM_TOOLS_VERSION
            backup = parent / f".{destination.name}.previous"
            backup.mkdir(parents=True)
            (backup / "adb").write_bytes(b"previous adb")
            (backup / "fastboot").write_bytes(b"previous fastboot")

            def fail_download(*_args, **_kwargs):
                raise OSError("network unavailable")

            with self.assertRaisesRegex(OSError, "network unavailable"):
                install_platform_tools(
                    license_accepted=True,
                    platform_name="darwin",
                    install_dir=destination,
                    opener=fail_download,
                    version_probe=lambda *_args: PLATFORM_TOOLS_VERSION,
                )

            self.assertTrue((destination / "adb").is_file())
            self.assertEqual((destination / "adb").read_bytes(), b"previous adb")
            self.assertEqual((destination / "fastboot").read_bytes(), b"previous fastboot")
            self.assertFalse(backup.exists())

    def test_existing_backup_and_install_are_both_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory) / "tools"
            destination = parent / PLATFORM_TOOLS_VERSION
            backup = parent / f".{destination.name}.previous"
            destination.mkdir(parents=True)
            backup.mkdir(parents=True)
            (destination / "adb").write_bytes(b"current adb")
            (backup / "adb").write_bytes(b"previous adb")
            (backup / "fastboot").write_bytes(b"previous fastboot")

            with self.assertRaisesRegex(RuntimeError, "both installations were preserved"):
                install_platform_tools(
                    license_accepted=True,
                    platform_name="darwin",
                    install_dir=destination,
                    opener=lambda *_args, **_kwargs: self.fail("must not download"),
                    version_probe=lambda *_args: PLATFORM_TOOLS_VERSION,
                )

            self.assertEqual((destination / "adb").read_bytes(), b"current adb")
            self.assertEqual((backup / "adb").read_bytes(), b"previous adb")
            self.assertEqual((backup / "fastboot").read_bytes(), b"previous fastboot")

    def test_installed_version_is_not_downloaded_again(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "tools" / PLATFORM_TOOLS_VERSION
            destination.mkdir(parents=True)
            (destination / "adb").write_bytes(b"adb")
            (destination / "fastboot").write_bytes(b"fastboot")
            calls = []
            result = install_platform_tools(
                license_accepted=True,
                platform_name="darwin",
                install_dir=destination,
                opener=lambda *_args, **_kwargs: calls.append(True),
                version_probe=lambda *_args: PLATFORM_TOOLS_VERSION,
            )
            self.assertTrue(result["already_installed"])
            self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
