// J2ME Studio additions, Apache-2.0.
import Foundation

nonisolated struct FrameDeliveryStatistics: Codable, Sendable {
    var received = 0
    var replaced = 0
    var discarded = 0
    var presented = 0
    var wakeups = 0
    var maxPendingFrames = 0
}

/// A single latest frame, shared by the JVM producer and the main-thread presenter.
/// Replacing a pending image releases it rather than adding another main-queue task.
nonisolated final class LatestFrameBuffer<Frame>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Frame?
    private var active = true
    private var wakePending = false
    private var statistics = FrameDeliveryStatistics()

    func offer(_ frame: Frame) -> Bool {
        lock.lock(); defer { lock.unlock() }
        statistics.received += 1
        guard active else { statistics.discarded += 1; return false }
        if pending != nil { statistics.replaced += 1 }
        pending = frame
        statistics.maxPendingFrames = 1
        guard !wakePending else { return false }
        wakePending = true
        statistics.wakeups += 1
        return true
    }

    func take() -> Frame? {
        lock.lock(); defer { lock.unlock() }
        let frame = pending
        pending = nil
        // Keep the display link awake across consecutive frames. An empty
        // consume disarms the wakeup before the main thread pauses its link.
        if frame == nil { wakePending = false }
        if frame != nil { statistics.presented += 1 }
        return frame
    }

    func setActive(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        active = value
        if !value {
            if pending != nil { statistics.discarded += 1 }
            pending = nil
            wakePending = false
        }
    }

    var hasPendingFrame: Bool {
        lock.lock(); defer { lock.unlock() }
        return active && pending != nil
    }

    var snapshot: FrameDeliveryStatistics {
        lock.lock(); defer { lock.unlock() }
        return statistics
    }
}
