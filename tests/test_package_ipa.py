import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_ipa", Path(__file__).resolve().parents[1] / "scripts/package_ipa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackagingTests(unittest.TestCase):
    """Synthetic fixtures test packaging only; they are never distributed as builds."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.app = self.root / "Example.app"
        self.app.mkdir()
        self.info = {"CFBundleExecutable": "Example", "CFBundleIdentifier": "org.example.test",
                     "CFBundleSupportedPlatforms": ["iPhoneOS"]}
        self.write_info()
        (self.app / "Example").write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + bytes(24))
        for name, classes in {
            "minijvm_rt.jar": ["java/lang/Object.class", "org/mini/vm/RefNative.class"],
            "j2me_api.jar": ["javax/microedition/shell/MIDletRunner.class", "javax/microedition/rms/RecordStore.class"],
        }.items():
            with zipfile.ZipFile(self.app / name, "w") as z:
                for cls in classes:
                    z.writestr(cls, b"fixture")

    def tearDown(self):
        self.temp.cleanup()

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_payload_and_executable_mode(self):
        output = self.root / "result.ipa"
        module.package(self.app, output)
        with zipfile.ZipFile(output) as z:
            executable = z.getinfo("Payload/Example.app/Example")
            self.assertEqual((executable.external_attr >> 16) & 0o777, 0o755)
            self.assertIsNone(z.testzip())

    def test_reject_arm64_simulator(self):
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.write_info()
        with self.assertRaisesRegex(ValueError, "device"):
            module.validate_app(self.app)

    def test_reject_missing_runtime(self):
        (self.app / "minijvm_rt.jar").unlink()
        with self.assertRaisesRegex(ValueError, "minijvm_rt.jar"):
            module.validate_app(self.app)

    def test_reject_non_arm64(self):
        (self.app / "Example").write_bytes(bytes(32))
        with self.assertRaisesRegex(ValueError, "arm64"):
            module.validate_app(self.app)


if __name__ == "__main__":
    unittest.main()
