//
//  NumpadView.swift
//  J2MEEmulator
//
//  Reusable numpad control: 0-9, *, # + soft keys + command buttons.
//

import UIKit

class NumpadView: UIView {

    static let KEY_SOFT_LEFT: Int32  = -6
    static let KEY_SOFT_RIGHT: Int32 = -7

    private var commandButtons: [UIButton] = []
    private let commandScroll = UIScrollView()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        commandScroll.showsHorizontalScrollIndicator = false
        commandScroll.accessibilityLabel = "游戏命令，左右滑动查看更多"
        addSubview(commandScroll)
        let numpad: [(String, Int32)] = [
            ("1", 49), ("2", 50), ("3", 51),
            ("4", 52), ("5", 53), ("6", 54),
            ("7", 55), ("8", 56), ("9", 57),
            ("*", 42), ("0", 48), ("#", 35),
        ]
        for (title, code) in numpad {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = UIColor(white: 0.12, alpha: 1)
            btn.layer.cornerRadius = 10
            btn.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
            btn.layer.borderWidth = 1
            btn.tag = Int(code)
            btn.addTarget(self, action: #selector(down(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(up(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addSubview(btn)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height

        let cols: CGFloat = 3
        let numRows: CGFloat = 4
        let gap: CGFloat = 3

        let btnW = (w - gap * (cols - 1)) / cols
        let commandHeight: CGFloat = commandButtons.isEmpty ? 0 : 34
        let btnH = (h - commandHeight - gap * (numRows - 1)) / numRows

        for sub in subviews {
            guard let btn = sub as? UIButton else { continue }
            let code = Int32(btn.tag)

            let (col, row): (Int, Int)
            switch code {
            case 49: (col, row) = (0, 0)
            case 50: (col, row) = (1, 0)
            case 51: (col, row) = (2, 0)
            case 52: (col, row) = (0, 1)
            case 53: (col, row) = (1, 1)
            case 54: (col, row) = (2, 1)
            case 55: (col, row) = (0, 2)
            case 56: (col, row) = (1, 2)
            case 57: (col, row) = (2, 2)
            case 42: (col, row) = (0, 3) // *
            case 48: (col, row) = (1, 3) // 0
            case 35: (col, row) = (2, 3) // #
            default: continue
            }
            btn.frame = CGRect(
                x: CGFloat(col) * (btnW + gap),
                y: commandHeight + CGFloat(row) * (btnH + gap),
                width: btnW, height: btnH)
        }

        layoutCommands()
    }

    // MARK: - Key events with repeat

    @objc private func down(_ sender: UIButton) {
        let code = Int32(sender.tag)
        haptic.impactOccurred(intensity: 0.6)
        KeyInputController.shared.press(code)
        sender.backgroundColor = UIColor(white: 0.30, alpha: 1)
    }

    @objc private func up(_ sender: UIButton) {
        KeyInputController.shared.release(Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.12, alpha: 1)
    }

    // MARK: - Canvas command buttons

    func updateCommands() {
        commandButtons.forEach { $0.removeFromSuperview() }
        commandButtons.removeAll()

        let cmdCount = j2me_ui_get_command_count()
        guard cmdCount > 0 else {
            commandScroll.isHidden = true
            setNeedsLayout()
            return
        }

        for i in 0..<cmdCount {
            let label = String(cString: j2me_ui_get_command_label(Int32(i)))
            let cmdId = j2me_ui_get_command_id(Int32(i))

            let btn = UIButton(type: .system)
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = .boldSystemFont(ofSize: 12)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = .systemBlue
            btn.layer.cornerRadius = 10
            btn.tag = 1000 + Int(cmdId)
            btn.addTarget(self, action: #selector(commandTapped(_:)), for: .touchUpInside)
            commandScroll.addSubview(btn)
            commandButtons.append(btn)
        }
        setNeedsLayout()
    }

    private func layoutCommands() {
        commandScroll.isHidden = commandButtons.isEmpty
        guard !commandButtons.isEmpty else { return }
        let w = bounds.width
        commandScroll.frame = CGRect(x: 0, y: 0, width: w, height: 30)
        var x: CGFloat = 0
        for btn in commandButtons {
            let width = min(w, max(64, btn.intrinsicContentSize.width + 16))
            btn.frame = CGRect(x: x, y: 0, width: width, height: 30)
            x += width + 4
        }
        commandScroll.contentSize = CGSize(width: max(w, x), height: 30)
    }

    /// Used by the simulator harness to assert real UIKit geometry, not a mock.
    func diagnosticLayoutIsValid() -> Bool {
        layoutIfNeeded()
        let keys = subviews.compactMap { $0 as? UIButton }
        let tolerance = bounds.insetBy(dx: -0.5, dy: -0.5)
        guard keys.count == 12, keys.allSatisfy({ !$0.frame.isEmpty && tolerance.contains($0.frame) }) else { return false }
        for (index, key) in keys.enumerated() {
            if keys.dropFirst(index + 1).contains(where: { $0.frame.intersects(key.frame) }) { return false }
            if !commandScroll.isHidden && key.frame.intersects(commandScroll.frame) { return false }
        }
        return true
    }

    @objc private func commandTapped(_ sender: UIButton) {
        j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), Int32(sender.tag - 1000))
    }
}
