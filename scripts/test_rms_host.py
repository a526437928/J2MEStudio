#!/usr/bin/env python3
"""Exercise the real Java RMS implementation across independent host JVM runs.

This does not establish miniJVM or iPhone runtime compatibility.
"""
import os
from pathlib import Path
import subprocess
import tempfile
from build_java import ROOT, JARS, javac


def main():
    compiler = Path(javac())
    java = compiler.with_name("java.exe" if os.name == "nt" else "java")
    with tempfile.TemporaryDirectory(prefix="j2me-rms-") as temp:
        temp = Path(temp)
        subprocess.run([str(compiler), "-J-Duser.language=en", "--release", "8", "-encoding", "UTF-8", "-cp",
                        str(JARS / "j2me_api.jar"), "-d", str(temp),
                        str(ROOT / "tests/HostRmsSmoke.java"), str(ROOT / "tests/HostLifecycleSmoke.java"),
                        str(ROOT / "fixtures/studio_diagnostics/src/StudioDiagnosticsMIDlet.java"),
                        str(ROOT / "tests/HostDiagnosticInputSmoke.java")], check=True)
        classpath = os.pathsep.join([str(temp), str(JARS / "j2me_api.jar")])
        # Same RMS store name in different save roots; reopen in fresh processes.
        for mode, game, value in [("write", "A", "中文存档甲"), ("write", "B", "中文存档乙"),
                                  ("read", "A", "中文存档甲"), ("read", "B", "中文存档乙")]:
            subprocess.run([str(java), "-Dfile.encoding=UTF-8", "-Dapp.save.root=" + str(temp / game),
                            "-cp", classpath, "HostRmsSmoke", mode, value], check=True)
        subprocess.run([str(java), "-cp", classpath, "HostLifecycleSmoke"], check=True)
        subprocess.run([str(java), "-cp", classpath, "HostDiagnosticInputSmoke"], check=True)
    print("PASS: host-JDK RMS persistence and separate save roots; iOS runtime remains unverified")


if __name__ == "__main__":
    main()
