#!/usr/bin/env python3
"""Execute the actual UIKit app, C miniJVM, logs and Java diagnostics on iOS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", default="org.j2mestudio.emulator")
    parser.add_argument("--app", type=Path, default=ROOT / "build/SimulatorData/Build/Products/Release-iphonesimulator/J2MEStudio.app")
    parser.add_argument("--standalone", action="store_true")
    args = parser.parse_args()
    prefix = "standalone" if args.standalone else "emulator"
    os.chdir(ROOT)
    devices = json.loads(run("list", "devices", "available", "--json"))["devices"]
    candidates = [d for runtime, items in devices.items() if runtime.endswith("iOS-26-2")
                  for d in items if d["name"] in ["iPhone 17 Pro", "iPhone 17"] and d.get("isAvailable")]
    if not candidates:
        raise RuntimeError("An installed iOS 26.2 iPhone simulator is required")
    device = sorted(candidates, key=lambda d: d["name"] != "iPhone 17 Pro")[0]
    udid = device["udid"]
    # Bring up the simulator's display frontend as well as CoreSimulator. The
    # display link needs a live display; a pre-created device may also stall on
    # its first cold boot on a hosted runner. Retain every boot attempt.
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    for attempt in [1, 2]:
        subprocess.run(["open", "-a", str(developer / "Applications/Simulator.app"),
                        "--args", "-CurrentDeviceUDID", udid], check=True)
        boot_log = ROOT / f"build/logs/{prefix}-boot-{attempt}.log"
        try:
            output = run("bootstatus", udid, "-b", timeout=180)
            boot_log.write_text(output)
            print(f"PASS {prefix} simulator boot attempt {attempt}", flush=True)
            break
        except subprocess.TimeoutExpired as error:
            output = error.output or b""
            if isinstance(output, bytes): output = output.decode(errors="replace")
            boot_log.write_text(output + "\nBOOT TIMEOUT after 180 seconds\n")
            (ROOT / f"build/logs/{prefix}-boot-{attempt}-devices.json").write_text(run("list", "devices", "--json"))
            print(f"Simulator boot attempt {attempt} timed out; original output retained", flush=True)
            if attempt == 2: raise
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False, timeout=30)
    run("install", udid, str(args.app.resolve()))
    documents = Path(run("get_app_container", udid, args.bundle, "data")) / "Documents"
    if args.standalone:
        cases = [("embedded", 1, "portrait", "integer", "normal"), ("embedded", 2, "landscape", "original", "normal")]
    else:
        cases = [("studio_diagnostics", 1, "landscape", "fit", "normal"),
                 ("studio_diagnostics", 2, "portrait", "integer", "normal"),
                 ("studio_diagnostics", 3, "landscape", "original", "normal"),
                 ("studio_diagnostics_secondary", 1, "portrait", "fit", "normal"),
                 ("studio_diagnostics", 4, "landscape", "fit", "crash"),
                 ("studio_diagnostics", 5, "portrait", "integer", "normal"),
                 ("studio_diagnostics_secondary", 2, "landscape", "fit", "normal"),
                 ("studio_diagnostics", 5, "portrait", "fit", "restore")]
    results = []

    def saves():
        index = documents / "library.json"
        if not index.exists(): return {}
        return {game["fileName"]: documents / "Saves" / str(uuid.UUID(game["id"])).upper()
                for game in json.loads(index.read_text())["games"]}

    def rms_hashes(folder):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob("rms/*") if p.is_file()}

    for number, (resource, expected, orientation, scaling, kind) in enumerate(cases, 1):
        save = saves().get(resource + ".jar")
        if save:
            for name in ["diagnostic-result.json", "diagnostic-frame-ready", "diagnostic-input-layout.json", "diagnostic-capture-done", "last-performance.json"]:
                (save / name).unlink(missing_ok=True)
        other = saves().get("studio_diagnostics_secondary.jar")
        other_hashes = rms_hashes(other) if other else {}
        env = {**os.environ, "SIMCTL_CHILD_J2ME_STUDIO_SMOKE_TEST": "1"}
        fps_limit = 30 if number in [2, 8] else 60
        options = ["--studio-smoke-test", "--studio-fixture=" + resource,
                   "--play-orientation=" + orientation, "--play-scaling=" + scaling, "--play-fps-limit=" + str(fps_limit)]
        if kind == "crash": options.append("--studio-crash-test")
        if kind == "restore": options.append("--studio-restore-latest")
        logpath = ROOT / f"build/logs/{prefix}-launch-{number}.log"
        with logpath.open("w") as log:
            process = subprocess.Popen(["xcrun", "simctl", "launch", "--terminate-running-process", "--console-pty",
                udid, args.bundle, *options], env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                start = time.monotonic(); frame_ready_at = None; screenshot = False
                while time.monotonic() - start < 75:
                    save = saves().get(resource + ".jar")
                    if save:
                        if frame_ready_at is None and (save / "diagnostic-frame-ready").exists(): frame_ready_at = time.monotonic()
                        if kind != "crash" and not screenshot and frame_ready_at is not None and time.monotonic() - frame_ready_at > 0.8:
                            # The test MIDlet stays on its real Canvas until this
                            # acknowledgement, even on a cold/slow simulator.
                            run("io", udid, "screenshot", str(ROOT / f"build/artifacts/{prefix}-{number}-{orientation}-{scaling}.png"), timeout=25)
                            (save / "diagnostic-capture-done").write_text("captured")
                            screenshot = True
                        native = save / "last-run.log"
                        if kind == "crash" and native.exists() and "[SIGNAL]" in native.read_text(errors="replace"):
                            assert other is not None and rms_hashes(other) == other_hashes, "Crash changed another game's RMS"
                            assert json.loads((save / "last-session.json").read_text())["status"] == "running"
                            shutil.copyfile(native, ROOT / f"build/logs/{prefix}-native-{number}.log")
                            results.append({"fatal_signal_logged": True, "other_game_preserved": True})
                            print("PASS native fatal signal captured; other game's real RMS unchanged", flush=True)
                            break
                        result_file = save / "diagnostic-result.json"
                        journal = save / "last-session.json"
                        performance_file = save / "last-performance.json"
                        if (result_file.exists() and journal.exists() and json.loads(journal.read_text()).get("status") == "finished"
                                and performance_file.exists() and json.loads(performance_file.read_text()).get("status") == "finished"):
                            result = json.loads(result_file.read_text())
                            assert result["pass"] and result["launches"] == expected, result
                            assert result["rightKeyCode"] == 54, "Exercise the actual numeric-6 joystick mapping"
                            assert result["diagonalPairs"] == 15 and result["skillKeyPresses"] == 0 and result["heldDirections"] == 0, result
                            performance = json.loads(performance_file.read_text())
                            assert performance["configuredFpsLimit"] == fps_limit and performance["presentationFps"] == fps_limit, performance
                            delivery = performance["frameDelivery"]
                            assert delivery["maxPendingFrames"] == 1 and delivery["received"] >= 1_000 and delivery["replaced"] >= 999, delivery
                            assert 0 < delivery["presented"] < delivery["received"] and delivery["wakeups"] < delivery["received"], delivery
                            assert performance["samples"] and all(s["thermalState"] in range(4) and s.get("cpuPercentOfOneCore", 0) >= 0 for s in performance["samples"]), performance
                            shutil.copyfile(performance_file, ROOT / f"build/logs/{prefix}-performance-{number}.json")
                            geometry = json.loads((save / "diagnostic-input-layout.json").read_text())
                            assert geometry["valid"] and geometry["scaling"] == scaling, geometry
                            assert geometry["orientation"] == orientation + ".", geometry
                            assert screenshot, "No screenshot of a displayed frame"
                            text = native.read_text(errors="replace")
                            assert "MIDlet lifecycle complete" in text and "[Studio diagnostics]" in text, "Missing captured JVM logs"
                            shutil.copyfile(native, ROOT / f"build/logs/{prefix}-native-{number}.log")
                            result.update({"geometry": geometry, "case": kind, "resource": resource, "frameDelivery": delivery, "fpsLimit": fps_limit})
                            results.append(result)
                            print(f"PASS {prefix} case {number}: {result}", flush=True)
                            break
                    time.sleep(0.5)
                else: raise RuntimeError(f"No completed diagnostic result; inspect {logpath}")
            finally:
                # Preserve the app's redirected JVM output and state even when
                # the diagnostic never finishes. A timeout must be diagnosable.
                failed_save = saves().get(resource + ".jar")
                if failed_save:
                    for name in ["last-run.log", "last-session.json", "last-performance.json", "diagnostic-result.json", "diagnostic-input-layout.json"]:
                        source = failed_save / name
                        if source.exists():
                            shutil.copyfile(source, ROOT / f"build/logs/{prefix}-case-{number}-{name}")
                if (documents / "library.json").exists():
                    shutil.copyfile(documents / "library.json", ROOT / f"build/logs/{prefix}-library.json")
                subprocess.run(["xcrun", "simctl", "terminate", udid, args.bundle], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill()
    if args.standalone:
        assert json.loads((documents / "launch-mode.json").read_text())["mode"] == "standalone"
        assert len(saves()) == 1, "Standalone app should launch only its embedded game"
    (ROOT / f"build/logs/{prefix}-status.json").write_text(json.dumps({
        "simulator": device["name"], "runtime": "iOS 26.2", "bundle": args.bundle,
        "cases": results, "iphone_tested": False, "input": "synthetic joystick geometry and UIButton target/action; no physical touch claim"
    }, indent=2))
    print(f"PASS: {prefix} actual miniJVM runtime, display modes, input, persistence and captured logs")


if __name__ == "__main__": main()
