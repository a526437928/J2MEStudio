import UIKit

/// A second launch mode using the same GameViewController, bridge and JVM.
final class StandaloneLauncherViewController: UIViewController {
    private let profileURL: URL
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private var firstAppearance = true
    private var loading = false
    init(profileURL: URL) { self.profileURL = profileURL; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        message.text = "正在启动游戏…"; message.numberOfLines = 0; message.textAlignment = .center
        retry.setTitle("再次启动", for: .normal)
        retry.addAction(UIAction { [weak self] _ in self?.start() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, retry]); stack.axis = .vertical; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if firstAppearance { firstAppearance = false; start() }
    }
    private func start() {
        guard !loading else { return }; loading = true; retry.isEnabled = false
        let configuration = profileURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let profile = try StandaloneProfile.read(from: configuration)
                let file = URL(fileURLWithPath: profile.jarResource)
                guard let jar = Bundle.main.url(forResource: file.deletingPathExtension().lastPathComponent, withExtension: file.pathExtension) else { throw GameLibraryError.missingGame }
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let library = GameLibrary(documents: documents)
                let game = try library.importGame(from: jar, validate: JARMetadata.validate)
                let save = library.saveURL(for: game)
                let store = PlayPreferenceStore(url: documents.appendingPathComponent("Configurations").appendingPathComponent(game.id.uuidString + ".json"))
                if !FileManager.default.fileExists(atPath: store.url.path) { try store.save(profile.controls) }
                try JSONSerialization.data(withJSONObject: ["mode": "standalone", "bundle": Bundle.main.bundleIdentifier ?? "", "game": game.id.uuidString]).write(to: documents.appendingPathComponent("launch-mode.json"), options: .atomic)
                let path = library.jarURL(for: game).path
                DispatchQueue.main.async {
                    guard let self else { return }; self.loading = false; self.retry.isEnabled = true
                    let icon = UIImage(systemName: "gamecontroller.fill") ?? UIImage()
                    let controller = GameViewController(jarPath: path, appName: profile.name, appIcon: icon,
                        saveRoot: save.path, canvasWidth: profile.screenWidth, canvasHeight: profile.screenHeight,
                        render3dScale: profile.render3dScale, fpsLimit: profile.fps)
                    controller.modalPresentationStyle = .fullScreen
                    self.message.text = "游戏已结束，可再次启动。"
                    self.present(controller, animated: false)
                }
            } catch {
                let text = error.localizedDescription
                DispatchQueue.main.async { self?.loading = false; self?.retry.isEnabled = true; self?.message.text = "无法启动内置游戏：\n" + text }
            }
        }
    }
}
