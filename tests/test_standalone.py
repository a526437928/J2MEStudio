import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('standalone', Path(__file__).resolve().parents[1] / 'scripts/prepare_standalone.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class StandaloneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.jar = self.root / 'sample.jar'
        with zipfile.ZipFile(self.jar, 'w') as archive:
            archive.writestr('META-INF/MANIFEST.MF', 'MIDlet-1: Test, , Example\n')
            archive.writestr('Example.class', b'\xca\xfe\xba\xbe\x00\x00\x00\x34fixture only')
    def tearDown(self): self.temp.cleanup()

    def test_prepare_separate_source_profile_and_icon(self):
        target = self.root / 'output'
        module.prepare(self.jar, target, '诊断独立版', 'org.example.standalone', True)
        profile = json.loads((target / 'J2MEEmulator/Resources/Standalone/standalone.json').read_text(encoding='utf-8'))
        self.assertEqual(profile['name'], '诊断独立版')
        self.assertEqual(profile['jarResource'], 'embedded.jar')
        self.assertEqual((target / 'J2MEEmulator/Resources/Standalone/embedded.jar').read_bytes(), self.jar.read_bytes())
        icon = target / 'J2MEEmulator/Resources/Assets.xcassets/AppIcon.appiconset/icon.png'
        self.assertEqual(icon.read_bytes()[:8], b'\x89PNG\r\n\x1a\n')
        self.assertFalse((target / '.git').exists())
        self.assertFalse((module.ROOT / 'J2MEEmulator/Resources/Standalone/standalone.json').exists())

    def test_refuse_emulator_identity_and_unconfirmed_resources(self):
        with self.assertRaises(ValueError): module.prepare(self.jar, self.root/'a', 'Test', 'org.j2mestudio.emulator', True)
        with self.assertRaises(ValueError): module.prepare(self.jar, self.root/'b', 'Test', 'org.example.game', False)

    def test_refuse_to_overwrite_existing_directory(self):
        target = self.root / 'existing'; target.mkdir(); (target/'sentinel').write_text('keep')
        with self.assertRaises(ValueError): module.prepare(self.jar, target, 'Test', 'org.example.game', True)
        self.assertEqual((target/'sentinel').read_text(), 'keep')
