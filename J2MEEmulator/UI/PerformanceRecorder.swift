// J2ME Studio additions, Apache-2.0.
import UIKit
import Darwin

/// Process observations for diagnosis; thermalState is not a thermometer or a
/// measurement of the CPU/GPU workload attributable to a particular game thread.
@MainActor final class PerformanceRecorder {
    private let destination: URL
    private let configuredFPS: Int
    private let presentationFPS: () -> Int
    private let frames: () -> FrameDeliveryStatistics
    private var timer: Timer?
    private var finished = false
    private var samples: [[String: Any]] = []
    private var previousWall = ProcessInfo.processInfo.systemUptime
    private var previousCPU = PerformanceRecorder.cpuSeconds()

    init(saveRoot: String, configuredFPS: Int, presentationFPS: @escaping () -> Int, frames: @escaping () -> FrameDeliveryStatistics) {
        destination = URL(fileURLWithPath: saveRoot).appendingPathComponent("last-performance.json")
        self.configuredFPS = configuredFPS
        self.presentationFPS = presentationFPS
        self.frames = frames
    }

    func resume() {
        guard !finished else { return }
        timer?.invalidate()
        previousWall = ProcessInfo.processInfo.systemUptime
        previousCPU = Self.cpuSeconds()
        let next = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(status: "running") }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    func pause() {
        guard !finished else { return }
        timer?.invalidate(); timer = nil
        sample(status: "paused")
    }

    func finish() {
        guard !finished else { return }
        timer?.invalidate(); timer = nil
        sample(status: "finished")
        finished = true
    }

    private static func cpuSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func sample(status: String) {
        let wall = ProcessInfo.processInfo.systemUptime
        let cpu = Self.cpuSeconds()
        let interval = wall - previousWall
        var entry: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: Date()),
            "status": status, "intervalSeconds": interval,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled]
        if let cpu, let previousCPU, interval > 0 {
            entry["cpuPercentOfOneCore"] = max(0, (cpu - previousCPU) / interval * 100)
        }
        previousWall = wall; previousCPU = cpu
        samples.append(entry)
        if samples.count > 30 { samples.removeFirst(samples.count - 30) }
        do {
            let delivery = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frames()))
            let report: [String: Any] = ["version": 1, "status": status, "configuredFpsLimit": configuredFPS,
                "presentationFps": presentationFPS(),
                "frameDelivery": delivery, "samples": samples,
                "cpuAccounting": "Process user + system time; one CPU core = 100%; not device temperature",
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""]
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
        } catch { print("[Performance] Could not write observations: \(error)") }
    }
}
