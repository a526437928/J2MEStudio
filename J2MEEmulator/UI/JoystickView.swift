//
//  JoystickView.swift
//  J2MEEmulator
//
//  Virtual joystick with per-game directional chords or legacy numeric mapping.
//  No fire/5 — that stays on the numpad.
//

import UIKit

class JoystickView: UIView {

    private let baseView = UIView()
    private let thumbView = UIView()

    private var keyState = JoystickKeyState()
    var directionMode: PlayPreferences.DirectionMode = .numericDirections {
        didSet { if oldValue != directionMode { cancelInput() } }
    }
    var isEditingLayout = false { didSet { if isEditingLayout { cancelInput() } } }

    /// Dead zone as fraction of base radius (no key press within this range)
    private let deadZoneRatio: CGFloat = 0.25

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false

        baseView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        baseView.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        baseView.layer.borderWidth = 1
        baseView.isUserInteractionEnabled = false
        addSubview(baseView)

        thumbView.backgroundColor = UIColor(white: 0.35, alpha: 1)
        thumbView.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        thumbView.layer.borderWidth = 1
        thumbView.isUserInteractionEnabled = false
        thumbView.alpha = 0
        addSubview(thumbView)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Small arrow indicators for the 4 cardinal directions
    private let arrowUp = UIImageView()
    private let arrowDown = UIImageView()
    private let arrowLeft = UIImageView()
    private let arrowRight = UIImageView()
    private var arrowsAdded = false

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.width, bounds.height)
        baseView.frame = CGRect(x: (bounds.width - size) / 2,
                                 y: (bounds.height - size) / 2,
                                 width: size, height: size)
        baseView.layer.cornerRadius = size / 2

        let thumbSize = size * 0.38
        thumbView.bounds = CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize)
        thumbView.layer.cornerRadius = thumbSize / 2
        thumbView.center = baseView.center

        layoutArrows(baseSize: size)
    }

    private func layoutArrows(baseSize: CGFloat) {
        if !arrowsAdded {
            arrowsAdded = true
            let cfg = UIImage.SymbolConfiguration(pointSize: baseSize * 0.08, weight: .semibold)
            let img = UIImage(systemName: "chevron.up", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 1, alpha: 0.3), renderingMode: .alwaysOriginal)
            for arrow in [arrowUp, arrowDown, arrowLeft, arrowRight] {
                arrow.image = img
                arrow.contentMode = .center
                arrow.isUserInteractionEnabled = false
                baseView.addSubview(arrow)
            }
            arrowDown.transform = CGAffineTransform(rotationAngle: .pi)
            arrowLeft.transform = CGAffineTransform(rotationAngle: -.pi / 2)
            arrowRight.transform = CGAffineTransform(rotationAngle: .pi / 2)
        }
        let r = baseSize / 2
        let inset = baseSize * 0.14
        let aSize: CGFloat = baseSize * 0.2
        arrowUp.frame    = CGRect(x: r - aSize / 2, y: inset - aSize / 2,            width: aSize, height: aSize)
        arrowDown.frame  = CGRect(x: r - aSize / 2, y: baseSize - inset - aSize / 2, width: aSize, height: aSize)
        arrowLeft.frame  = CGRect(x: inset - aSize / 2, y: r - aSize / 2,            width: aSize, height: aSize)
        arrowRight.frame = CGRect(x: baseSize - inset - aSize / 2, y: r - aSize / 2, width: aSize, height: aSize)
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditingLayout else { return }
        guard let pt = touches.first?.location(in: self) else { return }
        thumbView.alpha = 1
        update(at: pt)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditingLayout else { return }
        guard let pt = touches.first?.location(in: self) else { return }
        update(at: pt)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }

    // MARK: - Joystick logic

    /// CI drives the production direction calculation, not a hard-coded keycode.
    func diagnosticSetRight(pressed: Bool) {
        diagnosticSetSector(0, pressed: pressed)
    }

    func diagnosticSetSector(_ sector: Int, pressed: Bool) {
        guard !isEditingLayout else { return }
        if pressed {
            layoutIfNeeded()
            let angle = CGFloat(sector) * .pi / 4
            let distance = baseView.bounds.width * 0.4
            update(at: CGPoint(x: baseView.frame.midX + cos(angle) * distance,
                               y: baseView.frame.midY + sin(angle) * distance))
        } else { reset() }
    }

    func cancelInput() { reset() }

    private func update(at point: CGPoint) {
        let cx = baseView.center.x
        let cy = baseView.center.y
        let radius = baseView.bounds.width / 2

        let dx = point.x - cx
        let dy = point.y - cy
        let dist = hypot(dx, dy)
        let angle = atan2(dy, dx)

        // Clamp thumb to base circle
        let clamped = min(dist, radius * 0.85)
        thumbView.center = CGPoint(x: cx + cos(angle) * clamped,
                                    y: cy + sin(angle) * clamped)

        // Dead zone check
        if dist < radius * deadZoneRatio {
            setCodes([])
            return
        }

        // 8-way sector: each 45° wide, sector 0 centered on 0° (right)
        var a = angle
        if a < 0 { a += 2 * .pi }
        let sector = Int((a + .pi / 8) / (.pi / 4)) % 8
        setCodes(JoystickMapping.codes(sector: sector, mode: directionMode))
    }

    private func reset() {
        setCodes([])
        UIView.animate(withDuration: 0.15) { [weak self] in
            guard let self else { return }
            self.thumbView.center = self.baseView.center
            self.thumbView.alpha = 0
        }
    }

    private func setCodes(_ next: Set<Int32>) {
        let change = keyState.transition(to: next)
        for code in change.released { KeyInputController.shared.release(code) }
        for code in change.pressed { KeyInputController.shared.press(code) }
    }
}
