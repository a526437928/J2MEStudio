#!/usr/bin/env python3
"""Validate a device .app and package it for local re-signing. Does not sign."""
import argparse
import os
from pathlib import Path
import plistlib
import struct
import zipfile


def validate_app(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Only iPhoneOS device builds can be sideloaded")
    executable = app / info["CFBundleExecutable"]
    header = executable.read_bytes()[:32]
    if len(header) < 32 or struct.unpack_from("<II", header) != (0xFEEDFACF, 0x0100000C):
        raise ValueError("Expected a thin arm64 Mach-O executable")
    # arm64 simulators also use Mach-O arm64: the platform check above is essential.
    for name, required in {
        "minijvm_rt.jar": ["java/lang/Object.class", "org/mini/vm/RefNative.class"],
        "j2me_api.jar": ["javax/microedition/shell/MIDletRunner.class", "javax/microedition/rms/RecordStore.class"],
    }.items():
        files = list(app.rglob(name))
        if len(files) != 1 or files[0] != app / name:
            raise ValueError(f"Expected exactly one {name} in the bundle root, got {files}")
        with zipfile.ZipFile(files[0]) as archive:
            if archive.testzip() or not set(required).issubset(archive.namelist()):
                raise ValueError(f"Incomplete runtime: {name}")
    return info


def package(app, output):
    info = validate_app(app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_file():
                name = "Payload/" + app.name + "/" + path.relative_to(app).as_posix()
                entry = zipfile.ZipInfo.from_file(path, name)
                entry.compress_type = zipfile.ZIP_DEFLATED
                # Preserve executable permissions even if packaging on Windows.
                if path.name == info["CFBundleExecutable"]:
                    entry.create_system = 3
                    entry.external_attr = 0o100755 << 16
                archive.writestr(entry, path.read_bytes())
    print(f"Unsigned IPA: {output}; signing and device execution remain unverified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
