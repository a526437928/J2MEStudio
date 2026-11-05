import UIKit

@MainActor enum DiagnosticExport {
    static func present(saveRoot: URL, from controller: UIViewController) {
        do {
            studio_log_flush()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("J2ME-Logs-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files: [URL] = []
            for name in ["last-session.json", "last-run.log"] {
                let source = saveRoot.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) {
                    let copy = folder.appendingPathComponent(name)
                    try FileManager.default.copyItem(at: source, to: copy); files.append(copy)
                }
            }
            let history = saveRoot.appendingPathComponent("Sessions")
            let recent = (try? FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            func modified(_ url: URL) -> Date {
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }
            for source in recent.sorted(by: { modified($0) > modified($1) }).prefix(6) {
                let copy = folder.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: copy); files.append(copy)
            }
            let info: [String: String] = ["system": UIDevice.current.systemVersion,
                "device": UIDevice.current.model, "app": Bundle.main.bundleIdentifier ?? "",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""]
            let environment = folder.appendingPathComponent("environment.json")
            try JSONSerialization.data(withJSONObject: info, options: .prettyPrinted).write(to: environment)
            files.append(environment)
            let share = UIActivityViewController(activityItems: files, applicationActivities: nil)
            share.popoverPresentationController?.sourceView = controller.view
            share.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: 40, width: 1, height: 1)
            controller.present(share, animated: true)
        } catch {
            let alert = UIAlertController(title: "无法导出日志", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default)); controller.present(alert, animated: true)
        }
    }
}
