#!/usr/bin/env python3
"""Prepare an isolated source tree for one authorized JAR; never alter the original."""
import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import zlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def diagnostic_icon(path):
    # Code-native diagnostic icon; no downloaded or proprietary artwork.
    width = 1024
    rows = []
    for y in range(width):
        row = bytearray()
        for x in range(width):
            controller = (160 < x < 864 and 320 < y < 730)
            cross = (280 < x < 440 and 490 < y < 545) or (330 < x < 385 and 440 < y < 595)
            buttons = (x-690)**2+(y-470)**2 < 48**2 or (x-780)**2+(y-560)**2 < 48**2
            color = (250, 204, 50) if cross or buttons else (230, 240, 255) if controller else (14, 70, 85)
            row.extend(color)
        rows.append(b'\0' + bytes(row))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, width, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b''))


def prepare(jar, output, name, bundle, confirm_rights, icon=None, profile=None):
    if not confirm_rights:
        raise ValueError('Confirm that you own or may redistribute the selected JAR before packaging')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}', bundle):
        raise ValueError('A distinct reverse-DNS Bundle ID is required')
    if bundle == 'org.j2mestudio.emulator':
        raise ValueError('Standalone builds must use a different Bundle ID')
    if not name.strip() or '\n' in name:
        raise ValueError('A nonempty one-line app name is required')
    controls = {'orientation': 'automatic', 'scaling': 'integer', 'directionMode': 'numericDirections', 'keyScale': 1, 'opacity': 0.9, 'controls': {}, 'keys': {}}
    configuration = {'name': name, 'jarResource': 'embedded.jar', 'screenWidth': 240, 'screenHeight': 320, 'fps': 60, 'render3dScale': 1, 'controls': controls}
    if profile:
        custom = json.loads(profile.read_text(encoding='utf-8'))
        for key in ['screenWidth', 'screenHeight', 'fps', 'render3dScale']:
            if key in custom: configuration[key] = custom[key]
        controls.update(custom.get('controls', {}))
    if any(type(configuration[k]) is not int or not 1 <= configuration[k] <= 2048 for k in ['screenWidth', 'screenHeight']):
        raise ValueError('Screen dimensions must be integers in 1...2048')
    if configuration['fps'] not in [0, 15, 20, 30, 60] or configuration['render3dScale'] not in [1, 2, 3]:
        raise ValueError('Unsupported FPS or 3D scale')
    if controls['orientation'] not in ['automatic', 'portrait', 'landscape'] or controls['scaling'] not in ['fit', 'integer', 'original']:
        raise ValueError('Invalid orientation or pixel scaling mode')
    if controls['directionMode'] not in ['numericDirections', 'navigation', 'legacyNumeric']:
        raise ValueError('Invalid joystick direction mode')
    if not 0.65 <= controls['keyScale'] <= 1.25 or not 0.3 <= controls['opacity'] <= 1:
        raise ValueError('Invalid control size or opacity')
    with zipfile.ZipFile(jar) as archive:
        if archive.testzip() or 'META-INF/MANIFEST.MF' not in archive.namelist():
            raise ValueError('Invalid JAR manifest/CRC')
        lines = []
        for line in archive.read('META-INF/MANIFEST.MF').decode('utf-8').splitlines():
            if line.startswith(' ') and lines: lines[-1] += line[1:]
            else: lines.append(line)
        attrs = dict(line.split(':', 1) for line in lines if ':' in line)
        parts = attrs.get('MIDlet-1', '').split(',')
        if len(parts) < 3 or not parts[2].strip():
            raise ValueError('MIDlet-1 must specify an entry class')
        entry = parts[2].strip().replace('.', '/') + '.class'
        if entry not in archive.namelist(): raise ValueError('MIDlet entry class missing')
        header = archive.read(entry)[:8]
        if len(header) != 8 or header[:4] != b'\xca\xfe\xba\xbe' or struct.unpack('>H', header[6:8])[0] > 52:
            raise ValueError('Unsupported or invalid MIDlet bytecode')
    output = output.resolve()
    if output == ROOT or output in ROOT.parents or output.exists():
        raise ValueError('Use a new output directory, never overwrite a source tree')
    if ROOT in output.parents and (ROOT / 'build') not in output.parents:
        raise ValueError('An output inside this project must be under build/ to prevent recursive copies')
    shutil.copytree(ROOT, output, ignore=shutil.ignore_patterns('.git', 'build', 'DerivedData', '__pycache__', '*.pyc'))
    destination = output / 'J2MEEmulator/Resources/Standalone'
    destination.mkdir(parents=True)
    shutil.copyfile(jar, destination / 'embedded.jar')
    (destination / 'standalone.json').write_text(json.dumps(configuration, ensure_ascii=False, indent=2), encoding='utf-8')
    asset = output / 'J2MEEmulator/Resources/Assets.xcassets/AppIcon.appiconset/icon.png'
    if icon:
        header = icon.read_bytes()[:24]
        if len(header) < 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', header[16:24]) != (1024, 1024):
            raise ValueError('App icon must be a 1024 x 1024 PNG')
        shutil.copyfile(icon, asset)
    else:
        diagnostic_icon(asset)
    (output / 'standalone-build.json').write_text(json.dumps({'bundle': bundle, 'displayName': name}), encoding='utf-8')
    print(f'Prepared independent app source at {output}; no signing performed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--bundle-id', required=True)
    parser.add_argument('--icon', type=Path)
    parser.add_argument('--profile', type=Path)
    parser.add_argument('--confirm-rights', action='store_true')
    args = parser.parse_args()
    prepare(args.jar.resolve(), args.output, args.name, args.bundle_id, args.confirm_rights, args.icon, args.profile)
