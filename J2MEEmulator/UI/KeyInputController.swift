import UIKit

/// One repeat timer per held key; releasing one key cannot cancel another.
@MainActor final class KeyInputController {
    static let shared = KeyInputController()
    private var holders: [Int32: Int] = [:]
    private var timers: [Int32: Timer] = [:]

    func press(_ code: Int32) {
        holders[code, default: 0] += 1
        guard holders[code] == 1 else { return }
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code)
        timers[code] = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.holders[code] != nil else { return }
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                guard self?.holders[code] != nil else { return }
                j2me_input_post_key(Int32(J2ME_INPUT_KEY_REPEATED), code)
            }
            self.timers[code] = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        if let timer = timers[code] { RunLoop.main.add(timer, forMode: .common) }
    }

    func release(_ code: Int32) {
        guard let count = holders[code] else { return }
        if count > 1 { holders[code] = count - 1; return }
        holders.removeValue(forKey: code)
        timers.removeValue(forKey: code)?.invalidate()
        j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code)
    }

    func releaseAll() {
        for code in holders.keys { j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code) }
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        holders.removeAll()
    }
}
