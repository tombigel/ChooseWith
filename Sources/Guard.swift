// Watches for another app becoming the default for a managed extension. With
// "Take extensions back" on, it switches them back; either way, a change in the
// number of taken extensions is announced so the menu bar icon and Settings
// can flag it.

import AppKit

final class TakeoverGuard {
    static let shared = TakeoverGuard()

    /// After this many take-backs of one extension within `window`, stop fighting
    /// and leave it to the user (it then shows as taken).
    private let maxTakeBacks = 3
    private let window: TimeInterval = 60 * 60
    private var takeBacks: [String: [Date]] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTakenCount = -1

    func start() {
        guard timer == nil else { return }
        // Default run-loop mode only: never fires while the popup menu is open.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .default)
        timer = t
        // Apps sometimes make themselves the default when they launch.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.check() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
        })
        check()
    }

    /// Managed extensions another app is now the default for.
    static func takenExtensions() -> [String] {
        Registry.tracked.filter { !Registry.isActive($0) }
    }

    /// Cheap to call often: it only reads the current defaults unless something changed.
    func check() {
        var changed = false
        var tookBack: [(ext: String, app: String)] = []
        if Prefs.takeBackExtensions {
            for ext in Self.takenExtensions() {
                guard let id = Registry.currentHandler(forExtension: ext) else { continue }
                let taker = Registry.appName(forBundleID: id)
                if Registry.gaveUpTo(ext) == taker { continue }
                let recent = (takeBacks[ext] ?? []).filter { Date().timeIntervalSince($0) < window }
                if recent.count >= maxTakeBacks {
                    Registry.setGaveUp(ext, takerName: taker)
                    changed = true
                    continue
                }
                // setDefault (not register) keeps the user's original app on record,
                // so removing the extension later still hands it back to that app.
                if Registry.setDefault(bundleID: selfBundleID, forExtension: ext) == nil {
                    takeBacks[ext] = recent + [Date()]
                    Registry.setTakenBackNote(ext, from: taker)
                    tookBack.append((ext, taker))
                    changed = true
                }
            }
        }
        if !tookBack.isEmpty { Notifier.tookBack(tookBack) }
        let taken = Self.takenExtensions().count
        if taken != lastTakenCount { lastTakenCount = taken; changed = true }
        if changed { NotificationCenter.default.post(name: .owpPrefsChanged, object: nil) }
    }

    /// Takes back every taken extension now (menu bar "Take Back All", Settings banner).
    func takeBackAll() {
        for ext in Self.takenExtensions() { _ = Registry.register(ext) }
        lastTakenCount = -1
        check()
    }
}
