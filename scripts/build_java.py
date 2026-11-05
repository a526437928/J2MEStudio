#!/usr/bin/env python3
"""Build the existing Java API and test MIDlet on Windows, Linux and macOS."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
JARS = ROOT / "J2MEEmulator/Resources/jars"


def javac():
    home = os.environ.get("JAVA_HOME")
    executable = Path(home) / "bin" / ("javac.exe" if os.name == "nt" else "javac") if home else None
    if executable and executable.is_file():
        return str(executable)
    executable = shutil.which("javac")
    if not executable:
        raise RuntimeError("JDK 17+ required; set JAVA_HOME to your JDK directory")
    return executable


def compile_jar(source, destination, classpath, manifest=None):
    sources = sorted(source.rglob("*.java"))
    if not sources:
        raise RuntimeError(f"No Java sources: {source}")
    for dependency in classpath:
        if not dependency.is_file():
            raise FileNotFoundError(dependency)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="j2me-java-") as temp:
        temp = Path(temp)
        classes = temp / "classes"
        classes.mkdir()
        # javac argfiles need quoted paths, including when the checkout has spaces.
        args = temp / "sources.txt"
        args.write_text("\n".join('"' + p.as_posix() + '"' for p in sources), encoding="utf-8")
        subprocess.run([javac(), "-J-Duser.language=en", "--release", "8", "-encoding", "UTF-8",
                        "-cp", os.pathsep.join(str(p) for p in classpath),
                        "-d", str(classes), "@" + str(args)], check=True, cwd=ROOT)
        # Reproducible ZIP timestamps/order; no separate `jar` executable needed.
        candidate = temp / "output.jar"
        with zipfile.ZipFile(candidate, "w", zipfile.ZIP_DEFLATED) as archive:
            entries = {p.relative_to(classes).as_posix(): p.read_bytes() for p in classes.rglob("*.class")}
            entries["META-INF/MANIFEST.MF"] = manifest.read_bytes() if manifest else b"Manifest-Version: 1.0\r\n\r\n"
            for name, data in sorted(entries.items()):
                info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data)
        shutil.copyfile(candidate, destination)
    print(f"Built {destination.relative_to(ROOT)} ({len(sources)} Java sources)", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=["api", "test", "all"], default="all", nargs="?")
    args = parser.parse_args()
    runtime = JARS / "minijvm_rt.jar"
    if args.target in ("api", "all"):
        compile_jar(ROOT / "j2me_api/src", JARS / "j2me_api.jar", [runtime])
    if args.target in ("test", "all"):
        compile_jar(ROOT / "test_midlet/src", ROOT / "J2MEEmulator/Resources/apps/test_midlet.jar",
                    [runtime, JARS / "j2me_api.jar"], ROOT / "test_midlet/MANIFEST.MF")
        compile_jar(ROOT / "fixtures/studio_diagnostics/src", ROOT / "J2MEEmulator/Resources/apps/studio_diagnostics.jar",
                    [runtime, JARS / "j2me_api.jar"], ROOT / "fixtures/studio_diagnostics/MANIFEST.MF")


if __name__ == "__main__":
    main()
