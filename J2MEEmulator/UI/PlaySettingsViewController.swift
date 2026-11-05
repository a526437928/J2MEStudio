import UIKit

final class PlaySettingsViewController: UIViewController {
    var value: PlayPreferences
    var onChange: ((PlayPreferences) -> Void)?
    var onEdit: ((Bool) -> Void)?
    var onExport: (() -> Void)?
    init(value: PlayPreferences) { self.value = value; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "显示与按键"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)])
        func label(_ text: String) { let l = UILabel(); l.text = text; l.numberOfLines = 0; stack.addArrangedSubview(l) }
        label("屏幕方向")
        let orientation = UISegmentedControl(items: ["自动旋转", "竖屏", "横屏"])
        orientation.selectedSegmentIndex = PlayPreferences.Orientation.allCases.firstIndex(of: value.orientation) ?? 0
        orientation.addAction(UIAction { [weak self, weak orientation] _ in
            guard let orientation else { return }
            self?.value.orientation = PlayPreferences.Orientation.allCases[orientation.selectedSegmentIndex]; self?.changed()
        }, for: .valueChanged)
        stack.addArrangedSubview(orientation)
        label("画面缩放")
        let scaling = UISegmentedControl(items: ["保持比例适应", "整数倍像素", "原始像素"])
        scaling.selectedSegmentIndex = PlayPreferences.Scaling.allCases.firstIndex(of: value.scaling) ?? 0
        scaling.addAction(UIAction { [weak self, weak scaling] _ in
            guard let scaling else { return }
            self?.value.scaling = PlayPreferences.Scaling.allCases[scaling.selectedSegmentIndex]; self?.changed()
        }, for: .valueChanged)
        stack.addArrangedSubview(scaling)
        label("原始像素：1 个游戏像素对应 1 个屏幕物理像素。画面过大时会等比例缩小以完整显示。")
        for (title, minimum, maximum, initial, opacity) in [("按键整体大小", Float(0.65), Float(1.25), Float(value.keyScale), false), ("按键透明度", Float(0.3), Float(1), Float(value.opacity), true)] {
            label(title)
            let slider = UISlider(); slider.minimumValue = minimum; slider.maximumValue = maximum; slider.value = initial
            slider.addAction(UIAction { [weak self, weak slider] _ in
                guard let slider else { return }
                if opacity { self?.value.opacity = Double(slider.value) } else { self?.value.keyScale = Double(slider.value) }
                self?.changed()
            }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
            stack.addArrangedSubview(slider)
        }
        for (title, individual) in [("拖动方向盘、键盘和软键", false), ("逐个编辑数字键（拖动、双指缩放）", true)] {
            let button = UIButton(type: .system); button.setTitle(title, for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) { self?.onEdit?(individual) } }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let reset = UIButton(type: .system); reset.setTitle("恢复此游戏的默认显示与按键", for: .normal)
        reset.addAction(UIAction { [weak self] _ in self?.value = PlayPreferences(); self?.changed(); self?.dismiss(animated: true) }, for: .touchUpInside)
        stack.addArrangedSubview(reset)
        let export = UIButton(type: .system); export.setTitle("导出此游戏的按键配置", for: .normal)
        export.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) { self?.onExport?() } }, for: .touchUpInside)
        stack.addArrangedSubview(export)
    }
    private func changed() { value.normalize(); onChange?(value) }
}
