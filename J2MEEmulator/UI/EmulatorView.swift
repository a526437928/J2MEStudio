//
//  EmulatorView.swift
//  J2MEEmulator
//
//  Displays the J2ME Canvas framebuffer on screen.
//  Handles touch events and converts to J2ME pointer events.
//

import UIKit

class EmulatorView: UIView {

    private nonisolated let frames = LatestFrameBuffer<CGImage>()
    private var displayLink: CADisplayLink?
    private var lastPresentedFrame: CGImage?
    var presentationFPS = 60 { didSet { updatePresentationRate() } }
    var currentPresentationFPS: Int { displayLink?.preferredFramesPerSecond ?? 0 }
    nonisolated var frameStatistics: FrameDeliveryStatistics { frames.snapshot }

    // J2ME virtual canvas size
    var canvasWidth: Int = 240
    var canvasHeight: Int = 320

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        contentMode = .scaleAspectFit
        layer.contentsGravity = .resizeAspect
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
    }

    /// Called once when the first frame is rendered, then nilled out.
    var onFirstFrame: (() -> Void)?

    /// Called every frame with the CGImage (for glow mirror etc.)
    var onFrame: ((CGImage) -> Void)?

    /// Update the displayed image from a CGImage.
    nonisolated func displayImage(_ cgImage: CGImage) {
        guard frames.offer(cgImage) else { return }
        DispatchQueue.main.async { [weak self] in self?.schedulePresentation() }
    }

    private func schedulePresentation() {
        guard frames.hasPendingFrame else { return }
        if displayLink == nil {
            let target = FrameDisplayTarget(view: self)
            let link = CADisplayLink(target: target, selector: #selector(FrameDisplayTarget.tick(_:)))
            displayLink = link
            updatePresentationRate()
            link.add(to: .main, forMode: .common)
        }
        displayLink?.isPaused = false
    }

    private func updatePresentationRate() {
        let maximum = window?.screen.maximumFramesPerSecond ?? 60
        displayLink?.preferredFramesPerSecond = min(maximum, presentationFPS > 0 ? presentationFPS : maximum)
    }

    fileprivate func presentLatestFrame(_ link: CADisplayLink) {
        // Continuous frames share the active display link. Empty take() disarms
        // its wakeup; a concurrent new offer queues resume after this callback.
        guard let image = frames.take() else { link.isPaused = true; return }
        lastPresentedFrame = image
        layer.contents = image
        onFrame?(image)
        if let cb = onFirstFrame {
            onFirstFrame = nil
            cb()
        }
    }

    func setPresentationActive(_ active: Bool) {
        frames.setActive(active)
        if !active { displayLink?.isPaused = true }
    }

    func stopPresentation() {
        frames.setActive(false)
        displayLink?.invalidate()
        displayLink = nil
    }

    func diagnosticBurst() {
        guard let image = lastPresentedFrame else { return }
        for _ in 0..<1_000 { displayImage(image) }
    }

    // ============================================================
    // Touch handling
    // ============================================================

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            if let (vx, vy) = convertToVirtual(pt) {
                j2me_input_post_touch(Int32(J2ME_INPUT_POINTER_PRESSED), Int32(vx), Int32(vy))
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            if let (vx, vy) = convertToVirtual(pt) {
                j2me_input_post_touch(Int32(J2ME_INPUT_POINTER_DRAGGED), Int32(vx), Int32(vy))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            if let (vx, vy) = convertToVirtual(pt) {
                j2me_input_post_touch(Int32(J2ME_INPUT_POINTER_RELEASED), Int32(vx), Int32(vy))
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    /// Convert screen point to J2ME virtual canvas coordinates.
    /// Returns nil if the touch is outside the canvas area.
    private func convertToVirtual(_ point: CGPoint) -> (Int, Int)? {
        let viewW = bounds.width
        let viewH = bounds.height
        guard viewW > 0 && viewH > 0 else { return nil }

        let cw = CGFloat(canvasWidth)
        let ch = CGFloat(canvasHeight)

        // Calculate aspect-fit layout (same as CALayer's .resizeAspect)
        let scaleX = viewW / cw
        let scaleY = viewH / ch
        let scale = min(scaleX, scaleY)

        let displayW = cw * scale
        let displayH = ch * scale
        let offsetX = (viewW - displayW) / 2
        let offsetY = (viewH - displayH) / 2

        // Convert screen coords to virtual coords
        let vx = (point.x - offsetX) * cw / displayW
        let vy = (point.y - offsetY) * ch / displayH

        // Clamp to canvas bounds
        let cx = max(0, min(cw - 1, vx))
        let cy = max(0, min(ch - 1, vy))

        return (Int(cx), Int(cy))
    }
}

@MainActor private final class FrameDisplayTarget: NSObject {
    weak var view: EmulatorView?
    init(view: EmulatorView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.presentLatestFrame(link)
    }
}

// ============================================================
// Global flush callback
// ============================================================

private weak var globalEmulatorView: EmulatorView?

func setGlobalEmulatorView(_ view: EmulatorView?) {
    globalEmulatorView = view
}

let flushCallback: @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Void = { cgImagePtr, width, height in
    guard let ptr = cgImagePtr else { return }
    let cgImage = Unmanaged<CGImage>.fromOpaque(ptr).takeRetainedValue()
    globalEmulatorView?.displayImage(cgImage)
}
