//
//  AppsListViewController.swift
//  J2MEEmulator
//
//  Springboard-style home screen with app grid.
//

import UIKit
import UniformTypeIdentifiers

class AppsListViewController: UIViewController,
                      UICollectionViewDataSource,
                      UICollectionViewDelegate,
                      UISearchResultsUpdating,
                      UIDocumentPickerDelegate {

    private var springboardCollectionView: UICollectionView!
    private let emptyStateLabel = UILabel()
    private var lastLayoutWidth: CGFloat = 0
    private let searchController = UISearchController(searchResultsController: nil)
    private let library = GameLibrary(documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    private let libraryQueue = DispatchQueue(label: "org.j2mestudio.library", qos: .userInitiated)
    private var allApps: [AppInfo] = []
    private var scanning = false
    private var smokeStarted = false
    private var pendingMessage: (String, String)?

    /// Directory where imported JARs are stored
    private static var gamesDirectory: String {
        documentsDirectory + "/games"
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "游戏库"
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索游戏名称、厂商或文件名"
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        definesPresentationContext = true

        // Animated blob background
        let bg = AnimatedBackgroundView()
        bg.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: view.topAnchor),
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bg.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // "+" button — import JAR from Files
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add, primaryAction: UIAction { [weak self] _ in
                self?.addAppTapped()
            })
        navigationItem.rightBarButtonItem?.accessibilityLabel = "导入 JAR 游戏"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "测试 MIDlet", primaryAction: UIAction { [weak self] _ in
            self?.installDiagnostics()
        })

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 10

        springboardCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        springboardCollectionView.dataSource = self
        springboardCollectionView.delegate = self
        springboardCollectionView.backgroundColor = .clear
        springboardCollectionView.alwaysBounceVertical = true
        springboardCollectionView.showsVerticalScrollIndicator = false
        springboardCollectionView.register(SpringboardCell.self,
                                           forCellWithReuseIdentifier: SpringboardCell.reuseID)
        springboardCollectionView.contentInsetAdjustmentBehavior = .always
        springboardCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(springboardCollectionView)

        NSLayoutConstraint.activate([
            springboardCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
            springboardCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            springboardCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            springboardCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Empty state
        emptyStateLabel.text = "还没有游戏\n点右上角 + 导入 JAR 文件\n或安装左上角的免费测试 MIDlet"
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.font = .systemFont(ofSize: 17)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.isHidden = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])

        // Ensure games directory exists
        try? FileManager.default.createDirectory(atPath: Self.gamesDirectory,
                                                  withIntermediateDirectories: true)
        scanApps()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let message = pendingMessage {
            pendingMessage = nil
            showMessage(message.0, message.1)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        scanApps()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = springboardCollectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width

        let columns: CGFloat = 4
        let iconSize = SpringboardCell.iconSize
        let cellWidth = (width + iconSize) / (columns + 1)
        let horizontalInset = (cellWidth - iconSize) / 2

        guard let layout = springboardCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        layout.itemSize = CGSize(width: cellWidth, height: 96)
        layout.sectionInset = UIEdgeInsets(top: 20, left: horizontalInset,
                                            bottom: 20, right: horizontalInset)
    }

    // ============================================================
    // MARK: - Import JAR from Files
    // ============================================================

    private func addAppTapped() {
        let jarType = UTType(filenameExtension: "jar") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [jarType], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) { [weak self] in self?.importGames(urls) }
    }

    func importGames(_ urls: [URL]) {
        navigationItem.rightBarButtonItem?.isEnabled = false
        let store = library
        libraryQueue.async { [weak self] in
            var errors: [String] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { try store.importGame(from: url, validate: JARMetadata.validate) }
                catch { errors.append(url.lastPathComponent + "：" + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                self?.navigationItem.rightBarButtonItem?.isEnabled = true
                self?.scanApps()
                if !errors.isEmpty { self?.showMessage("部分文件未导入", errors.joined(separator: "\n")) }
            }
        }
    }

    private func installDiagnostics() {
        guard let url = Bundle.main.url(forResource: "studio_diagnostics", withExtension: "jar") else {
            showMessage("测试文件缺失", "此构建未包含测试 MIDlet，请重新下载完整构建。")
            return
        }
        importGames([url])
    }

    struct AppInfo {
        let record: GameRecord
        let name: String
        let path: String
        let fileName: String
        let version: String?
        let vendor: String?
        let icon: UIImage
        let saveRoot: String
    }
    private var apps: [AppInfo] = []

    private func scanApps() {
        guard !scanning else { return }
        scanning = true
        let store = library
        libraryQueue.async { [weak self] in
            do {
                try store.load()
                let notices = try store.adoptLegacyFiles(validate: JARMetadata.validate)
                let records = store.games.map { game in
                    (game, store.jarURL(for: game), store.saveURL(for: game))
                }
                let metadata = records.map { item in
                    let meta = JARMetadata.read(from: item.1.path)
                    return (item, meta, meta?.readIcon(from: item.1.path))
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.scanning = false
                    self.allApps = metadata.enumerated().map { index, item in
                        let ((game, jar, save), meta, jarIcon) = item
                        self.migrateSettings(for: game)
                        let name = meta?.midletName ?? URL(fileURLWithPath: game.fileName).deletingPathExtension().lastPathComponent
                        return AppInfo(record: game, name: name, path: jar.path, fileName: game.fileName,
                            version: meta?.version, vendor: meta?.vendor,
                            icon: Self.springboardIcon(jarIcon, name: name, index: index),
                            saveRoot: save.path)
                    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    self.updateSearchResults(for: self.searchController)
                    if !notices.isEmpty { self.showMessage("导入与迁移提示", notices.joined(separator: "\n")) }
                    self.startSmokeTestIfRequested()
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self?.scanning = false
                    self?.showMessage("无法读取游戏库", message)
                }
            }
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        apps = allApps.filter { query.isEmpty || [$0.name, $0.fileName, $0.vendor ?? ""].contains {
            $0.localizedCaseInsensitiveContains(query)
        } }
        springboardCollectionView.reloadData()
        emptyStateLabel.text = allApps.isEmpty ? "还没有游戏\n点右上角 + 导入 JAR 文件\n或安装左上角的免费测试 MIDlet" : "没有匹配的游戏"
        emptyStateLabel.isHidden = !apps.isEmpty
    }

    private func migrateSettings(for game: GameRecord) {
        guard let old = game.legacySettingsKey else { return }
        let defaults = UserDefaults.standard
        let marker = "migrated_" + game.id.uuidString
        guard !defaults.bool(forKey: marker) else { return }
        for prefix in ["ss3d_", "resW_", "resH_", "fpsLimit_"] {
            if let value = defaults.object(forKey: prefix + old) {
                defaults.set(value, forKey: prefix + game.id.uuidString)
            }
        }
        defaults.set(true, forKey: marker)
    }

    private func showMessage(_ title: String, _ message: String) {
        guard presentedViewController == nil else { pendingMessage = (title, message); return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func startSmokeTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--studio-smoke-test"), !smokeStarted else { return }
        smokeStarted = true
        if let app = allApps.first(where: { $0.fileName == "studio_diagnostics.jar" }) {
            launch(app)
        } else {
            smokeStarted = false
            installDiagnostics()
        }
    }

    // ============================================================
    // MARK: - Icon generation
    // ============================================================

    private static let iconSize: CGFloat = SpringboardCell.iconSize

    private static let placeholderGradients: [(UIColor, UIColor)] = [
        (UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1),
         UIColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.00, green: 0.68, blue: 0.63, alpha: 1),
         UIColor(red: 0.20, green: 0.85, blue: 0.60, alpha: 1)),
        (UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
         UIColor(red: 1.00, green: 0.75, blue: 0.28, alpha: 1)),
        (UIColor(red: 0.88, green: 0.22, blue: 0.28, alpha: 1),
         UIColor(red: 1.00, green: 0.42, blue: 0.48, alpha: 1)),
        (UIColor(red: 0.58, green: 0.28, blue: 0.85, alpha: 1),
         UIColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.22, green: 0.30, blue: 0.80, alpha: 1),
         UIColor(red: 0.38, green: 0.48, blue: 0.95, alpha: 1)),
        (UIColor(red: 0.90, green: 0.28, blue: 0.52, alpha: 1),
         UIColor(red: 1.00, green: 0.48, blue: 0.68, alpha: 1)),
        (UIColor(red: 0.15, green: 0.65, blue: 0.42, alpha: 1),
         UIColor(red: 0.28, green: 0.82, blue: 0.55, alpha: 1)),
    ]

    private static func springboardIcon(_ jarIcon: UIImage?, name: String, index: Int) -> UIImage {
        let size = CGSize(width: iconSize, height: iconSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            UIBezierPath(roundedRect: rect, cornerRadius: SpringboardCell.iconCornerRadius).addClip()

            if let img = jarIcon {
                UIColor(white: 0.22, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                img.draw(in: rect)
            } else {
                let pair = placeholderGradients[index % placeholderGradients.count]
                let cgCtx = ctx.cgContext
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace,
                                              colors: [pair.0.cgColor, pair.1.cgColor] as CFArray,
                                              locations: [0, 1]) {
                    cgCtx.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: iconSize, y: iconSize), options: [])
                }
                let letter = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .font: UIFont.systemFont(ofSize: iconSize * 0.42, weight: .semibold)
                ]
                let strSize = (letter as NSString).size(withAttributes: attrs)
                (letter as NSString).draw(
                    at: CGPoint(x: (iconSize - strSize.width) / 2,
                                y: (iconSize - strSize.height) / 2),
                    withAttributes: attrs)
            }

            let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                           cornerRadius: SpringboardCell.iconCornerRadius - 0.5)
            UIColor(white: 1.0, alpha: 0.12).setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()
        }
    }

    // ============================================================
    // MARK: - UICollectionView
    // ============================================================

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        apps.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SpringboardCell.reuseID, for: indexPath) as! SpringboardCell
        let app = apps[indexPath.item]
        cell.configure(name: app.name, icon: app.icon)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }
        let app = apps[indexPath.item]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            let ssEnabled = Self.is3DSupersampling(for: app)
            let toggle3D = UIAction(title: ssEnabled ? "关闭 3D 增强" : "开启 3D 增强",
                                    subtitle: ssEnabled ? "更接近原始画面" : "提升平滑度，兼容性需逐款验证",
                                    image: UIImage(systemName: "cube"),
                                    state: ssEnabled ? .on : .off) { _ in
                Self.set3DSupersampling(!ssEnabled, for: app)
            }
            let clearData = UIAction(title: "清除游戏数据",
                                     image: UIImage(systemName: "eraser")) { _ in
                self?.confirmClearGameData(for: app)
            }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self?.confirmDeleteApp(app)
            }
            let currentRes = Self.resolution(for: app)
            let resActions = Self.resolutionOptions.map { opt in
                UIAction(title: opt.label,
                         state: (opt.w == currentRes.w && opt.h == currentRes.h) ? .on : .off) { _ in
                    Self.setResolution(w: opt.w, h: opt.h, for: app)
                }
            }
            let resMenu = UIMenu(title: "游戏分辨率",
                                  image: UIImage(systemName: "aspectratio"),
                                  children: resActions)

            let currentFps = Self.fpsLimit(for: app)
            let fpsActions = Self.fpsLimitOptions.map { opt in
                UIAction(title: opt.label,
                         state: opt.value == currentFps ? .on : .off) { _ in
                    Self.setFpsLimit(opt.value, for: app)
                }
            }
            let fpsMenu = UIMenu(title: "帧率上限",
                                  subtitle: "过高帧率可能影响部分游戏",
                                  image: UIImage(systemName: "gauge.with.needle"),
                                  children: fpsActions)

            let settings = UIMenu(options: .displayInline, children: [toggle3D, resMenu, fpsMenu])
            let actions = UIMenu(options: .displayInline, children: [clearData, delete])
            let journal = UIAction(title: "查看运行记录", image: UIImage(systemName: "doc.text")) { _ in
                let url = URL(fileURLWithPath: app.saveRoot).appendingPathComponent("last-session.json")
                let message = (try? String(contentsOf: url, encoding: .utf8)) ?? "尚无运行记录。"
                self?.showMessage("运行记录", message + "\n\nrunning 表示未记录正常结束，可能是系统终止或崩溃；这不是完整系统崩溃报告。")
            }
            var children: [UIMenuElement] = [settings, journal, actions]
            if let message = app.record.migrationNotice {
                children.append(UIAction(title: "旧存档迁移提示", image: UIImage(systemName: "exclamationmark.triangle")) { _ in
                    self?.showMessage("旧存档迁移提示", message)
                })
            }
            return UIMenu(children: children)
        })
    }

    // MARK: - Per-game settings

    private static func gameId(for app: AppInfo) -> String {
        app.record.id.uuidString
    }

    static func is3DSupersampling(for app: AppInfo) -> Bool {
        UserDefaults.standard.object(forKey: "ss3d_\(gameId(for: app))") as? Bool ?? true
    }

    static func set3DSupersampling(_ enabled: Bool, for app: AppInfo) {
        UserDefaults.standard.set(enabled, forKey: "ss3d_\(gameId(for: app))")
    }

    private static let resolutionOptions: [(label: String, w: Int, h: Int)] = [
        // Common J2ME resolutions (portrait / square only)
        ("101×80",   101,  80),
        ("128×128",  128, 128),
        ("128×160",  128, 160),
        ("132×176",  132, 176),
        ("160×128",  160, 128),
        ("176×208",  176, 208),
        ("176×220",  176, 220),
        ("208×208",  208, 208),
        ("220×220",  220, 220),
        ("240×266",  240, 266),
        ("240×320",  240, 320),
        ("240×400",  240, 400),
        ("320×480",  320, 480),
        ("352×416",  352, 416),
        ("360×640",  360, 640),
        ("480×800",  480, 800),
    ]

    static func resolution(for app: AppInfo) -> (w: Int, h: Int) {
        let gid = gameId(for: app)
        let w = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 240
        let h = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 320
        return (w, h)
    }

    private static func setResolution(w: Int, h: Int, for app: AppInfo) {
        let gid = gameId(for: app)
        UserDefaults.standard.set(w, forKey: "resW_\(gid)")
        UserDefaults.standard.set(h, forKey: "resH_\(gid)")
    }

    private static let fpsLimitOptions: [(label: String, value: Int)] = [
        ("不限制", 0),
        ("15 FPS",   15),
        ("20 FPS",   20),
        ("30 FPS",   30),
        ("60 FPS",   60),
    ]

    static func fpsLimit(for app: AppInfo) -> Int {
        UserDefaults.standard.object(forKey: "fpsLimit_\(gameId(for: app))") as? Int ?? 60
    }

    private static func setFpsLimit(_ fps: Int, for app: AppInfo) {
        UserDefaults.standard.set(fps, forKey: "fpsLimit_\(gameId(for: app))")
    }

    private static var documentsDirectory: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
    }

    private func performLibraryAction(_ action: @escaping (GameLibrary) throws -> Void) {
        let store = library
        libraryQueue.async { [weak self] in
            do {
                try action(store)
                DispatchQueue.main.async { self?.scanApps() }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self?.scanApps(); self?.showMessage("操作未完成", message) }
            }
        }
    }

    private func confirmClearGameData(for app: AppInfo) {
        let alert = UIAlertController(title: "清除游戏数据", message: "清除“\(app.name)”的当前存档？建议先备份。旧版迁移备份会保留。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.performLibraryAction { try $0.clearData(for: app.record) }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteApp(_ app: AppInfo) {
        let alert = UIAlertController(title: "删除游戏", message: "删除“\(app.name)”及其当前存档？导入与旧版迁移备份会保留。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            self?.performLibraryAction { try $0.delete(app.record) }
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        launch(apps[indexPath.item])
    }

    private func launch(_ app: AppInfo) {
        guard FileManager.default.fileExists(atPath: app.path) else {
            showMessage("游戏文件缺失", "请重新导入这个 JAR，原存档仍然保留。")
            return
        }
        let res = Self.resolution(for: app)
        let gameVC = GameViewController(jarPath: app.path, appName: app.name, appIcon: app.icon,
            saveRoot: app.saveRoot, canvasWidth: res.w, canvasHeight: res.h,
            render3dScale: Self.is3DSupersampling(for: app) ? 3 : 1, fpsLimit: Self.fpsLimit(for: app))
        gameVC.modalPresentationStyle = .fullScreen

        let gameID = app.record.id
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { _ in false }
        // Zoom lands on the placeholder icon centered in the game screen
        options.alignmentRectProvider = { context in
            guard let gvc = context.zoomedViewController as? GameViewController,
                  let placeholder = gvc.placeholderIconView else {
                return .null
            }
            return placeholder.frame
        }

        gameVC.preferredTransition = .zoom(options: options) {
            [weak self] _ in
            guard let self, let itemIndex = self.apps.firstIndex(where: { $0.record.id == gameID }),
                  let cell = self.springboardCollectionView.cellForItem(
                      at: IndexPath(item: itemIndex, section: 0)) as? SpringboardCell else {
                return nil
            }
            return cell.iconView
        }

        present(gameVC, animated: true)
    }
}
