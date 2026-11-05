#!/usr/bin/env python3
"""Run the actual C miniJVM + Java MIDlet in an iOS simulator twice.

Synthetic input verifies the event pipeline; this is not an iPhone touch test.
"""
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "org.j2mestudio.emulator"


def run(*args, **kwargs):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True, **kwargs).strip()


def main():
    os.chdir(ROOT)
    devices = json.loads(run("list", "devices", "available", "--json"))["devices"]
    candidates = [d for runtime, items in devices.items() if runtime.endswith("iOS-26-2")
                  for d in items if d["name"] == "iPhone 17" and d.get("isAvailable")]
    if not candidates:
        raise RuntimeError("The selected Xcode requires the installed iOS 26.2 / iPhone 17 simulator")
    device = candidates[0]
    udid = device["udid"]
    if device["state"] != "Booted":
        run("boot", udid)
    run("bootstatus", udid, "-b", timeout=180)
    app = ROOT / "build/SimulatorData/Build/Products/Release-iphonesimulator/J2MEStudio.app"
    run("install", udid, str(app))
    container = Path(run("get_app_container", udid, BUNDLE, "data"))
    documents = container / "Documents"
    results = []
    for iteration in [1, 2]:
        if (documents / "library.json").exists():
            index = json.loads((documents / "library.json").read_text())
            for game in index["games"]:
                save = documents / "Saves" / str(uuid.UUID(game["id"])).upper()
                (save / "diagnostic-result.json").unlink(missing_ok=True)
                (save / "diagnostic-frame-ready").unlink(missing_ok=True)
                (save / "diagnostic-input-layout.json").unlink(missing_ok=True)
        env = {**os.environ, "SIMCTL_CHILD_J2ME_STUDIO_SMOKE_TEST": "1"}
        logpath = ROOT / f"build/logs/simulator-launch-{iteration}.log"
        with logpath.open("w") as log:
            process = subprocess.Popen(["xcrun", "simctl", "launch", "--terminate-running-process", "--console-pty",
                udid, BUNDLE, "--studio-smoke-test"], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                start = time.monotonic()
                screenshot = False
                frame_ready_at = None
                while time.monotonic() - start < 75:
                    if frame_ready_at is None and list(documents.glob("Saves/*/diagnostic-frame-ready")):
                        frame_ready_at = time.monotonic()
                    if not screenshot and frame_ready_at is not None and time.monotonic() - frame_ready_at > 0.8:
                        run("io", udid, "screenshot", str(ROOT / f"build/artifacts/diagnostics-{iteration}.png"))
                        screenshot = True
                    files = list(documents.glob("Saves/*/diagnostic-result.json"))
                    if files:
                        result = json.loads(files[0].read_text())
                        journal = files[0].with_name("last-session.json")
                        if journal.exists() and json.loads(journal.read_text()).get("status") == "finished":
                            assert result["pass"], result
                            assert result["launches"] == iteration, result
                            assert screenshot, "No screenshot of a displayed game frame"
                            geometry = json.loads(files[0].with_name("diagnostic-input-layout.json").read_text())
                            assert geometry["valid"], "UIKit key geometry overlaps or extends outside the keypad"
                            results.append(result)
                            print(f"PASS simulator launch {iteration}: {result}", flush=True)
                            break
                    time.sleep(0.5)
                else:
                    raise RuntimeError(f"No completed miniJVM diagnostic result. Inspect {logpath}")
            finally:
                subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], check=False)
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill()
    (ROOT / "build/logs/simulator-status.json").write_text(json.dumps({
        "simulator": device["name"], "runtime": "iOS 26.2", "passes": results,
        "iphone_tested": False, "input": "synthetic native input using the production repeat controller"
    }, indent=2))
    print("PASS: real iOS-simulator miniJVM execution, Canvas, input, pause/resume and persistent RMS")


if __name__ == "__main__":
    main()
