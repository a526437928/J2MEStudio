import Foundation
import Dispatch

nonisolated final class FrameProbe {
    let value: Int
    init(_ value: Int) { self.value = value }
}

@main enum FrameDeliveryTests {
    static func main() throws {
        var checks = 0
        func require(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: label, code: 1) }
            checks += 1
        }
        let frames = LatestFrameBuffer<Int>()
        try require(frames.offer(1), "First frame requests a display wakeup")
        try require(!frames.offer(2), "A burst shares its pending wakeup")
        try require(frames.snapshot.maxPendingFrames == 1 && frames.snapshot.replaced == 1, "Bounded pending storage")
        try require(frames.take() == 2, "Present the latest image rather than stale work")
        try require(!frames.offer(6), "A continuous producer reuses the active display link")
        try require(frames.take() == 6, "Active delivery needs no redundant wakeup task")
        try require(frames.take() == nil, "An idle presenter has no repeated frame")
        try require(frames.offer(3), "A frame after consumption schedules another wakeup")
        frames.setActive(false)
        try require(!frames.hasPendingFrame && frames.take() == nil, "Pausing clears the pending image")
        try require(!frames.offer(4), "A hidden view does not schedule presentation")
        try require(frames.snapshot.discarded == 2, "Count paused pending and incoming frames")
        frames.setActive(true)
        try require(frames.offer(5) && frames.take() == 5, "Resume without a stale frame or lost wakeup")

        let parallel = LatestFrameBuffer<Int>()
        DispatchQueue.concurrentPerform(iterations: 10_000) { _ = parallel.offer($0) }
        let stats = parallel.snapshot
        try require(stats.received == 10_000 && stats.replaced == 9_999, "Concurrent producers preserve all accounting")
        try require(stats.wakeups == 1 && stats.maxPendingFrames == 1, "A blocked presenter receives one wakeup, not ten thousand tasks")
        try require((0..<10_000).contains(parallel.take() ?? -1), "Concurrent latest image remains valid")
        try require(parallel.snapshot.presented == 1, "Only one image was consumed")

        let images = LatestFrameBuffer<FrameProbe>()
        var first: FrameProbe? = FrameProbe(1)
        weak var retained = first
        _ = images.offer(first!)
        first = nil
        try require(retained != nil, "Pending image stays alive")
        _ = images.offer(FrameProbe(2))
        try require(retained == nil, "Superseded image is released before presentation")
        let current = images.take()
        try require(current?.value == 2 && !images.hasPendingFrame, "Consumer receives ownership of the newest image")
        images.setActive(false)
        try require(!images.offer(FrameProbe(3)) && images.snapshot.discarded == 1, "Inactive delivery retains no image")
        print("PASS: \(checks) frame delivery concurrency, lifetime and pause checks")
    }
}
