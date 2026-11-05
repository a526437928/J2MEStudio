//
//  GameViewController.swift
//  J2MEEmulator
//
//  Runs a single J2ME MIDlet. Presented modally with zoom transition.
//  Layout mode determines the arrangement of screen and controls.
//

import UIKit
import Darwin

// MARK: - Layout mode (extensible for future layouts)

enum GameLayoutMode {
    case ngage      // Landscape: D-pad left, screen center, numpad right
    case adaptive
}

// MARK: - GameViewController

class GameViewController: UIViewController {

    let jarPath: String
    let appName: String
    let appIcon: UIImage
    let saveRoot: String
    let canvasWidth: Int
    let canvasHeight: Int
    let render3dScale: Int
    let fpsLimit: Int
    let layoutMode: GameLayoutMode

    private let emulatorView = EmulatorView()
    private let glowContainer = UIView()
    private let glowContentView = UIView()
    private lazy var formView = FormView()
    private lazy var listView = J2MEListView()
    private let backButton = UIButton(type: .system)
    private let lskButton = UIButton(type: .system)
    private let rskButton = UIButton(type: .system)
    private let softKeyHaptic = UIImpactFeedbackGenerator(style: .light)
    private(set) var placeholderIconView: UIImageView?

    // Controls — created based on layoutMode
    private var joystickView: JoystickView?
    private var numpadView: NumpadView?
    private var hasStarted = false
    private var preferences = PlayPreferences()
    private let settingsButton = UIButton(type: .system)
    private let editorHint = UILabel()
    private var editingLayout = false
    private var editingIndividualKeys = false
    private var controlPans: [UIPanGestureRecognizer] = []
    private var dragStart: CGPoint = .zero
    private var lastSize: CGSize = .zero
    private var preferenceStore: PlayPreferenceStore {
        PlayPreferenceStore(url: URL(fileURLWithPath: saveRoot).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Configurations").appendingPathComponent(URL(fileURLWithPath: jarPath).deletingPathExtension().lastPathComponent + ".json"))
    }
    private var layoutPrefix: String { view.bounds.width > view.bounds.height ? "landscape." : "portrait." }

    init(jarPath: String, appName: String, appIcon: UIImage,
         saveRoot: String,
         canvasWidth: Int = 240, canvasHeight: Int = 320,
         render3dScale: Int = 3, fpsLimit: Int = 0,
         layoutMode: GameLayoutMode = .adaptive) {
        self.jarPath = jarPath
        self.appName = appName
        self.appIcon = appIcon
        self.saveRoot = saveRoot
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.render3dScale = render3dScale
        self.fpsLimit = fpsLimit
        self.layoutMode = layoutMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        setGlobalEmulatorView(nil)
        alertTimeoutWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private var alertTimeoutWork: DispatchWorkItem?

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch preferences.orientation {
        case .automatic: return .allButUpsideDown
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        emulatorView.canvasWidth = canvasWidth
        emulatorView.canvasHeight = canvasHeight

        do { preferences = try preferenceStore.load() }
        catch { print("[Settings] Preserved unreadable configuration: \(error)") }
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("--play-orientation="), let v = PlayPreferences.Orientation(rawValue: String(arg.dropFirst(19))) { preferences.orientation = v }
            if arg.hasPrefix("--play-scaling="), let v = PlayPreferences.Scaling(rawValue: String(arg.dropFirst(15))) { preferences.scaling = v }
        }
        setupAdaptiveLayout()

        // Placeholder icon — visible until first game frame
        let iconIV = UIImageView(image: appIcon)
        iconIV.contentMode = .center
        view.addSubview(iconIV)
        placeholderIconView = iconIV
        view.bringSubviewToFront(backButton)

        // Fade out placeholder on first rendered frame
        emulatorView.onFirstFrame = { [weak self] in
            guard let icon = self?.placeholderIconView else { return }
            UIView.animate(withDuration: 0.2) {
                icon.alpha = 0
            } completion: { _ in
                icon.removeFromSuperview()
                self?.placeholderIconView = nil
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--studio-smoke-test") {
            emulatorView.onFirstFrame = { [weak self] in
                self?.placeholderIconView?.isHidden = true
                if let root = self?.saveRoot {
                    self?.writeDiagnosticGeometry()
                    // CI screenshot timing follows a displayed frame, not app-launch time.
                    try? Data([1]).write(to: URL(fileURLWithPath: root).appendingPathComponent("diagnostic-frame-ready"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    KeyInputController.shared.press(-4)
                    KeyInputController.shared.press(53)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    KeyInputController.shared.release(53)
                    // The direction key must continue repeating after releasing 5.
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    KeyInputController.shared.release(-4)
                    j2me_input_post_key(20, 0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { j2me_input_post_key(21, 0) }
                if ProcessInfo.processInfo.arguments.contains("--studio-crash-test") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { raise(SIGABRT) }
                }
            }
        }

        // Mirror game frames to glow layer
        emulatorView.onFrame = { [weak self] cgImage in
            self?.glowContentView.layer.contents = cgImage
        }

        // Register native callbacks
        setGlobalEmulatorView(emulatorView)
        j2me_render_set_flush_callback(flushCallback)
        j2me_ui_set_callback(gameUICallback)
        activeGameViewController = self
        NotificationCenter.default.addObserver(self, selector: #selector(platformPause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(platformResume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestOrientation()
        startGame()
    }

    // ============================================================
    // MARK: - N-Gage layout
    // ============================================================
    //
    //  ┌──────────────────────────────────────────────────────┐
    //  │ [X]                                                   │
    //  │  ┌─────────┐  ┌──────────────┐  ┌───────────────┐  │
    //  │  │         │  │              │  │ [LSK]   [RSK] │  │
    //  │  │  ╭───╮  │  │  J2ME Canvas │  │ [1] [2] [3]  │  │
    //  │  │  │ ○ │  │  │   240×320    │  │ [4] [5] [6]  │  │
    //  │  │  ╰───╯  │  │              │  │ [7] [8] [9]  │  │
    //  │  │joystick │  │              │  │ [*] [0] [#]  │  │
    //  │  └─────────┘  └──────────────┘  └───────────────┘  │
    //  └──────────────────────────────────────────────────────┘

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        preferences.orientation == .landscape ? .landscapeRight : .portrait
    }

    private func setupAdaptiveLayout() {
        let joystick = JoystickView(); let numpad = NumpadView()
        joystickView = joystick; numpadView = numpad
        glowContainer.isUserInteractionEnabled = false
        glowContentView.isUserInteractionEnabled = false
        glowContainer.addSubview(glowContentView)
        glowContentView.alpha = 0.18
        for child: UIView in [glowContainer, emulatorView, joystick, numpad, lskButton, rskButton, formView, listView, backButton, settingsButton, editorHint] { view.addSubview(child) }
        formView.isHidden = true; listView.isHidden = true
        emulatorView.clipsToBounds = true
        for (button, title, code) in [(lskButton, "左软键", -6), (rskButton, "右软键", -7)] {
            button.tag = code; button.setTitle(title, for: .normal)
            button.addTarget(self, action: #selector(softKeyDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(softKeyUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        backButton.setTitle("退出", for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        settingsButton.setTitle("设置", for: .normal)
        settingsButton.showsMenuAsPrimaryAction = true
        settingsButton.menu = UIMenu(children: [
            UIAction(title: "显示与按键", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.showPlaySettings() },
            UIAction(title: "导出运行日志", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }; DiagnosticExport.present(saveRoot: URL(fileURLWithPath: self.saveRoot), from: self)
            }
        ])
        for button in [lskButton, rskButton, backButton, settingsButton] {
            button.backgroundColor = UIColor(white: 0.14, alpha: 0.95)
            button.setTitleColor(.white, for: .normal); button.layer.cornerRadius = 8
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        }
        for (name, child) in [("joystick", joystick as UIView), ("numpad", numpad as UIView), ("left", lskButton as UIView), ("right", rskButton as UIView)] {
            child.accessibilityIdentifier = name
            let pan = UIPanGestureRecognizer(target: self, action: #selector(moveControl(_:)))
            pan.isEnabled = false; child.addGestureRecognizer(pan); controlPans.append(pan)
        }
        numpad.onKeyLayoutChange = { [weak self] keys in
            guard let self else { return }
            self.preferences.keys = self.preferences.keys.filter { !$0.key.hasPrefix(self.layoutPrefix) }
            for (code, placement) in keys { self.preferences.keys[self.layoutPrefix + code] = placement }
        }
        editorHint.font = .systemFont(ofSize: 11); editorHint.textColor = .systemYellow
        editorHint.numberOfLines = 2; editorHint.isHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size { KeyInputController.shared.releaseAll(); lastSize = view.bounds.size }
        layoutControls()
    }

    private func layoutControls() {
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 8, dy: 4)
        guard safe.width > 0, safe.height > 100 else { return }
        let landscape = view.bounds.width > view.bounds.height
        let content: CGRect
        var defaults: [String: CGRect] = [:]
        let scale = CGFloat(preferences.keyScale)
        if landscape {
            let side = min(safe.width * 0.25, safe.height * 0.52)
            content = CGRect(x: safe.minX + side + 8, y: safe.minY + 42, width: safe.width - 2 * side - 16, height: safe.height - 48)
            let controlsHeight = safe.height - 94
            let joy = min(side * 0.9, controlsHeight) * scale
            let padWidth = side * 0.94 * scale; let padHeight = min(side * 1.42, controlsHeight) * scale
            defaults["joystick"] = CGRect(x: safe.minX + (side - joy)/2, y: safe.minY + 46 + (controlsHeight - joy)/2, width: joy, height: joy)
            defaults["numpad"] = CGRect(x: safe.maxX - side + (side - padWidth)/2, y: safe.minY + 46 + (controlsHeight - padHeight)/2, width: padWidth, height: padHeight)
            defaults["left"] = CGRect(x: safe.minX + (side - 72)/2, y: safe.maxY - 40, width: 72, height: 36)
            defaults["right"] = CGRect(x: safe.maxX - side + (side - 72)/2, y: safe.maxY - 40, width: 72, height: 36)
        } else {
            let controlsHeight = min(250, max(208, safe.height * 0.32))
            content = CGRect(x: safe.minX, y: safe.minY + 42, width: safe.width, height: safe.height - controlsHeight - 90)
            let top = safe.maxY - controlsHeight
            let joy = min(safe.width * 0.36, controlsHeight * 0.78) * scale
            let padWidth = safe.width * 0.47 * scale; let padHeight = (controlsHeight - 8) * scale
            defaults["joystick"] = CGRect(x: safe.minX + 4, y: top + (controlsHeight - joy)/2, width: joy, height: joy)
            defaults["numpad"] = CGRect(x: safe.maxX - padWidth, y: top, width: padWidth, height: padHeight)
            defaults["left"] = CGRect(x: safe.minX, y: content.maxY + 4, width: 72, height: 36)
            defaults["right"] = CGRect(x: safe.maxX - 72, y: content.maxY + 4, width: 72, height: 36)
        }
        emulatorView.frame = PlayGeometry.screen(in: content, canvas: CGSize(width: canvasWidth, height: canvasHeight), displayScale: view.window?.screen.scale ?? 3, mode: preferences.scaling)
        emulatorView.layer.cornerRadius = preferences.scaling == .fit ? 6 : 0
        glowContainer.frame = emulatorView.frame; glowContentView.frame = glowContainer.bounds
        for (name, child) in [("joystick", joystickView as UIView?), ("numpad", numpadView as UIView?), ("left", lskButton as UIView?), ("right", rskButton as UIView?)] {
            guard let child, var frame = defaults[name] else { continue }
            if let custom = preferences.controls[layoutPrefix + name] {
                frame.origin = CGPoint(x: safe.minX + safe.width * custom.x - frame.width/2, y: safe.minY + safe.height * custom.y - frame.height/2)
            }
            child.frame = PlayGeometry.clamp(frame, to: safe)
            child.alpha = CGFloat(preferences.opacity)
        }
        numpadView?.editedKeys = Dictionary(uniqueKeysWithValues: preferences.keys.filter { $0.key.hasPrefix(layoutPrefix) }.map { (String($0.key.dropFirst(layoutPrefix.count)), $0.value) })
        backButton.frame = CGRect(x: safe.minX, y: safe.minY, width: 64, height: 36)
        settingsButton.frame = CGRect(x: safe.maxX - 64, y: safe.minY, width: 64, height: 36)
        editorHint.frame = CGRect(x: safe.minX + 70, y: safe.minY, width: max(10, safe.width - 140), height: 38)
        formView.frame = safe; listView.frame = safe
        placeholderIconView?.frame = emulatorView.frame
        for top in [backButton, settingsButton, editorHint] { view.bringSubviewToFront(top) }
    }

    private func requestOrientation() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        let mask: UIInterfaceOrientationMask
        switch preferences.orientation { case .automatic: return; case .portrait: mask = .portrait; case .landscape: mask = .landscape }
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in print("[Orientation] \(error)") }
    }

    private func showPlaySettings() {
        let controller = PlaySettingsViewController(value: preferences)
        controller.onChange = { [weak self] value in self?.preferences = value; self?.savePreferences(); self?.view.setNeedsLayout() }
        controller.onEdit = { [weak self] individual in self?.startLayoutEditing(individual: individual) }
        controller.onExport = { [weak self] in
            guard let self else { return }; self.savePreferences()
            let share = UIActivityViewController(activityItems: [self.preferenceStore.url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = self.settingsButton
            self.present(share, animated: true)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    private func savePreferences() {
        do { try preferenceStore.save(preferences) }
        catch { showConfigurationError(error.localizedDescription) }
    }

    private func showConfigurationError(_ message: String) {
        let alert = UIAlertController(title: "配置未保存", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }

    private func startLayoutEditing(individual: Bool) {
        platformPause(); editingLayout = true; editingIndividualKeys = individual
        joystickView?.isEditingLayout = true; numpadView?.isEditingLayout = true; numpadView?.editingKeys = individual
        for pan in controlPans { pan.isEnabled = !(individual && pan.view === numpadView) }
        backButton.setTitle("完成", for: .normal)
        editorHint.text = individual ? "拖动数字键，双指缩放单键；不要重叠" : "拖动方向盘、键盘或软键；横竖屏分别保存"
        editorHint.isHidden = false
    }

    private func finishLayoutEditing() {
        if editingIndividualKeys && numpadView?.diagnosticLayoutIsValid() != true {
            showConfigurationError("数字键重叠或超出键盘区域。请调整，或在设置中恢复默认布局。")
            return
        }
        editingLayout = false; editingIndividualKeys = false
        joystickView?.isEditingLayout = false; numpadView?.isEditingLayout = false; numpadView?.editingKeys = false
        controlPans.forEach { $0.isEnabled = false }
        editorHint.isHidden = true; backButton.setTitle("退出", for: .normal)
        savePreferences(); platformResume()
    }

    @objc private func moveControl(_ gesture: UIPanGestureRecognizer) {
        guard editingLayout, let child = gesture.view, let name = child.accessibilityIdentifier else { return }
        if gesture.state == .began { dragStart = child.center }
        let shift = gesture.translation(in: view)
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 8, dy: 4)
        child.frame = PlayGeometry.clamp(CGRect(x: dragStart.x + shift.x - child.bounds.width/2, y: dragStart.y + shift.y - child.bounds.height/2, width: child.bounds.width, height: child.bounds.height), to: safe)
        preferences.controls[layoutPrefix + name] = ControlPlacement(x: Double((child.center.x - safe.minX)/safe.width), y: Double((child.center.y - safe.minY)/safe.height))
    }

    private func writeDiagnosticGeometry() {
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 7, dy: 3)
        let frame = emulatorView.frame
        let ratio = frame.width * (view.window?.screen.scale ?? 3) / CGFloat(canvasWidth)
        let integerOK = preferences.scaling != .integer || ratio < 1 || abs(ratio.rounded() - ratio) < 0.001
        let originalOK = preferences.scaling != .original || ratio <= 1.001
        let correctRatio = abs(frame.width / frame.height - CGFloat(canvasWidth)/CGFloat(canvasHeight)) < 0.001
        let valid = numpadView?.diagnosticLayoutIsValid() == true && safe.contains(frame) && integerOK && originalOK && correctRatio
        let payload: [String: Any] = ["valid": valid, "orientation": layoutPrefix, "scaling": preferences.scaling.rawValue,
            "physicalPixelScale": ratio, "aspectRatio": frame.width/frame.height, "safeArea": safe.debugDescription, "screen": frame.debugDescription]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: saveRoot).appendingPathComponent("diagnostic-input-layout.json"))
        }
    }

    // MARK: - Soft keys

    @objc private func softKeyDown(_ sender: UIButton) {
        guard !editingLayout else { return }
        softKeyHaptic.impactOccurred(intensity: 0.6)
        KeyInputController.shared.press(Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.30, alpha: 1)
    }

    @objc private func softKeyUp(_ sender: UIButton) {
        guard !editingLayout else { return }
        KeyInputController.shared.release(Int32(sender.tag))
        sender.backgroundColor = UIColor(white: 0.12, alpha: 1)
    }

    // ============================================================
    // MARK: - Game lifecycle
    // ============================================================

    private func startGame() {
        guard !hasStarted else { return }
        hasStarted = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = self?.runMIDlet()
            DispatchQueue.main.async {
                KeyInputController.shared.releaseAll()
                let parent = self?.presentingViewController
                self?.dismiss(animated: true) {
                    if let error {
                        let alert = UIAlertController(title: "游戏未正常启动", message: error, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        parent?.present(alert, animated: true)
                    }
                }
            }
        }
    }

    private func runMIDlet() -> String? {
        guard let resRoot = Bundle.main.resourcePath else { return "运行库资源目录缺失。" }
        do { try JARMetadata.validate(URL(fileURLWithPath: jarPath)) }
        catch { return "无法启动这个 JAR：" + error.localizedDescription }
        do {
            try FileManager.default.createDirectory(atPath: saveRoot, withIntermediateDirectories: true)
            try SessionJournal.write(saveRoot: saveRoot, status: "running", detail: "正在初始化 JVM")
        } catch { return "无法创建独立存档目录：" + error.localizedDescription }

        do { _ = try RMSSnapshots(saveRoot: URL(fileURLWithPath: saveRoot)).create() }
        catch { return "无法备份 RMS：" + error.localizedDescription }
        let logResult = (saveRoot + "/last-run.log").withCString { studio_log_begin($0) }
        guard logResult == 0 else { return "无法写入游戏日志，错误码 \(logResult)。" }
        defer { studio_log_end() }
        let initResult = jvm_bridge_init(resRoot, saveRoot, jarPath,
                                         Int32(canvasWidth),
                                         Int32(canvasHeight),
                                         Int32(render3dScale),
                                         Int32(fpsLimit))
        guard initResult == 0 else {
            print("[Swift] ERROR: JVM init failed with code \(initResult)")
            jvm_bridge_destroy()
            try? SessionJournal.write(saveRoot: saveRoot, status: "failed", detail: "JVM init \(initResult)")
            return "JVM 初始化失败，错误码 \(initResult)。"
        }

        let runResult = jvm_bridge_run_midlet(jarPath)
        print("[Swift] MIDlet run result: \(runResult)")
        jvm_bridge_destroy()
        studio_log_end()
        try? SessionJournal.write(saveRoot: saveRoot, status: runResult == 0 ? "finished" : "failed", detail: "MIDlet result \(runResult)")
        return runResult == 0 ? nil : "MIDlet 退出码 \(runResult)，请备份 last-session.json 和系统崩溃报告。"
    }

    @objc private func backTapped() {
        if editingLayout { finishLayoutEditing(); return }
        backButton.isEnabled = false
        KeyInputController.shared.releaseAll()
        jvm_bridge_request_stop()
    }

    @objc private func platformPause() {
        KeyInputController.shared.releaseAll()
        j2me_input_post_key(20, 0)
    }

    @objc private func platformResume() { j2me_input_post_key(21, 0) }

    // ============================================================
    // MARK: - View switching
    // ============================================================

    func showCanvasView() {
        emulatorView.isHidden = false
        joystickView?.isHidden = false
        numpadView?.isHidden = false
        formView.isHidden = true
        listView.isHidden = true
        numpadView?.updateCommands()
    }

    func showFormView() {
        formView.buildFromNativeData()
        formView.isHidden = false
        emulatorView.isHidden = true
        joystickView?.isHidden = true
        numpadView?.isHidden = true
        listView.isHidden = true
    }

    func showListView() {
        listView.buildFromNativeData()
        listView.isHidden = false
        emulatorView.isHidden = true
        joystickView?.isHidden = true
        numpadView?.isHidden = true
        formView.isHidden = true
    }

    func showAlert() {
        let title = String(cString: j2me_ui_get_form_title())
        let text = String(cString: j2me_ui_get_alert_text())

        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)

        alertTimeoutWork?.cancel()
        alertTimeoutWork = nil

        let cmdCount = j2me_ui_get_command_count()
        if cmdCount == 0 {
            alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
                self?.alertTimeoutWork?.cancel()
                j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
            })
        } else {
            for i in 0..<cmdCount {
                let label = String(cString: j2me_ui_get_command_label(Int32(i)))
                let cmdId = j2me_ui_get_command_id(Int32(i))
                alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    self?.alertTimeoutWork?.cancel()
                    j2me_input_post_key(Int32(J2ME_UI_COMMAND_ACTION), cmdId)
                })
            }
        }

        present(alert, animated: true)

        let timeout = j2me_ui_get_alert_timeout()
        if timeout > 0 {
            let work = DispatchWorkItem { [weak alert] in
                alert?.dismiss(animated: true) {
                    j2me_input_post_key(Int32(J2ME_UI_ALERT_DISMISSED), 0)
                }
            }
            alertTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeout) / 1000.0, execute: work)
        }
    }
}

// MARK: - Game UI callback (global)

private(set) weak var activeGameViewController: GameViewController?

let gameUICallback: @convention(c) (Int32, UnsafePointer<CChar>?) -> Void = { action, data in
    DispatchQueue.main.async {
        guard let vc = activeGameViewController else { return }
        switch action {
        case Int32(J2ME_UI_ACTION_SHOW_CANVAS):  vc.showCanvasView()
        case Int32(J2ME_UI_ACTION_SHOW_FORM):    vc.showFormView()
        case Int32(J2ME_UI_ACTION_SHOW_LIST):    vc.showListView()
        case Int32(J2ME_UI_ACTION_SHOW_ALERT):   vc.showAlert()
        default: break
        }
    }
}
