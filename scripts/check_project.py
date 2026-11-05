#!/usr/bin/env python3
"""Offline, cross-platform checks. Passing does not imply an iOS build passed."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def check_jar(path, required):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError(f"Corrupt JAR: {path}")
        missing = set(required) - set(archive.namelist())
        if missing:
            raise ValueError(f"Missing classes in {path}: {sorted(missing)}")
        for name in archive.namelist():
            if name.endswith(".class"):
                header = archive.read(name)[:8]
                magic, minor, major = struct.unpack(">IHH", header)
                if magic != 0xCAFEBABE or major > 52:
                    raise ValueError(f"Unsupported bytecode: {path}:{name} major={major}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--built-java", action="store_true")
    args = parser.parse_args()
    lock = json.loads((ROOT / "dependencies.lock.json").read_text(encoding="utf-8"))
    runtime = ROOT / lock["runtime"]["path"]
    if hashlib.sha256(runtime.read_bytes()).hexdigest() != lock["runtime"]["sha256"]:
        raise ValueError("Vendored runtime checksum mismatch; do not silently replace the JVM class library")
    required_paths = [
        "J2MEEmulator/minijvm/jvm/jvm.c", "J2MEEmulator/minijvm/jvm/jvm.h",
        "J2MEEmulator/minijvm/utils/tinycthread.c", "J2MEEmulator/NativeBridge/jvm_bridge.c",
        "J2MEEmulator/NativeBridge/m3g/src/m3g_core.c",
        "J2MEEmulator/NativeBridge/j2me_micro3d_gl.m",
        "j2me_api/src/javax/microedition/shell/MIDletRunner.java",
        "j2me_api/src/javax/microedition/rms/RecordStore.java", "test_midlet/src/TestMIDlet.java",
        "J2MEEmulator/Resources/sound_fonts/gs_instruments.sf2",
    ]
    for name in required_paths:
        if not (ROOT / name).is_file():
            raise FileNotFoundError(name)
    project = (ROOT / "J2MEEmulator.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    if "miniJVM-2.0.0" in project:
        raise ValueError("Xcode references a nonexistent external miniJVM folder")
    scheme = ET.parse(ROOT / "J2MEEmulator.xcodeproj/xcshareddata/xcschemes/J2MEEmulator.xcscheme")
    if not scheme.findall(".//BuildActionEntry"):
        raise ValueError("No shared build scheme")
    with (ROOT / "J2MEEmulator/SupportingFiles/Info.plist").open("rb") as f:
        plistlib.load(f)
    check_jar(runtime, ["java/lang/Object.class", "org/mini/vm/RefNative.class"])
    check_jar(ROOT / "J2MEEmulator/Resources/jars/j2me_api.jar", [
        "javax/microedition/shell/MIDletRunner.class", "javax/microedition/rms/RecordStore.class",
        "javax/microedition/lcdui/Canvas.class", "javax/microedition/m3g/Graphics3D.class",
        "com/mascotcapsule/micro3d/v3/Graphics3D.class"])
    if args.built_java:
        check_jar(ROOT / "J2MEEmulator/Resources/apps/test_midlet.jar", ["TestMIDlet.class"])
    print("PASS: source layout, pinned runtime, Java bytecode, shared scheme and plist checks")
    print("iOS compilation, signing and device execution are separate checks")


if __name__ == "__main__":
    main()
