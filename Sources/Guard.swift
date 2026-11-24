// When another app becomes the default for a managed extension (usually after
// the user OKs an app's "make me the default" prompt, or changes it in Get Info):
// keep Choose With, ask the user, or do nothing, per Settings.

import AppKit

final class TakeoverGuard {
    static let shared = TakeoverGuard()

    /// In Keep mode, after this many take-backs of one extension within `window`,
    /// stop fighting and leave it to the user.
    private let maxTakeBacks = 3
    private let window: TimeInterval = 60 * 60
    private var takeBacks: [String: [Date]] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var asking = false

    func start() {
        guard timer == nil else { return }
        // Default run-loop mode only: never fires while the popup menu or a modal
        // dialog is open, so an alert can't appear on top of them.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .default)
        timer = t
        // Freshly installed or updated apps often ask to become the default on first run.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.check() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.check()
        })
    }

    struct Claim {
        let ext: String
        let taker: String   // app name
    }

    /// Extensions another app has claimed that the user hasn't already settled.
    private func claims() -> [Claim] {
        Registry.tracked.compactMap { ext in
            guard !Registry.isActive(ext), let id = Registry.currentHandler(forExtension: ext) else { return nil }
            let taker = Registry.appName(forBundleID: id)
            if Registry.leftTo(ext) == taker || Registry.gaveUpTo(ext) == taker { return nil }
            return Claim(ext: ext, taker: taker)
        }
    }

    /// Cheap to call often: it only reads the current defaults unless something changed.
    func check() {
        guard !asking else { return }
        switch Prefs.takeoverPolicy {
        case .nothing:
            return
        case .keep:
            takeBack(claims(), limitRepeats: true)
        case .ask:
            let found = claims()
            if !found.isEmpty { ask(about: found) }
        }
    }

    private func takeBack(_ claims: [Claim], limitRepeats: Bool) {
        guard !claims.isEmpty else { return }
        for claim in claims {
            let recent = (takeBacks[claim.ext] ?? []).filter { Date().timeIntervalSince($0) < window }
            if limitRepeats && recent.count >= maxTakeBacks {
                Registry.setGaveUp(claim.ext, takerName: claim.taker)
                continue
            }
            // setDefault (not register) keeps the user's original app on record,
            // so removing the extension later still hands it back to that app.
            if Registry.setDefault(bundleID: selfBundleID, forExtension: claim.ext) == nil {
                takeBacks[claim.ext] = recent + [Date()]
                Registry.setTakenBackNote(claim.ext, from: claim.taker)
            }
        }
        NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
    }

    private func ask(about claims: [Claim]) {
        asking = true
        defer { asking = false }

        let alert = NSAlert()
        if claims.count == 1, let c = claims.first {
            alert.messageText = "\(c.taker) is now the default for .\(c.ext)"
            alert.informativeText = "Take .\(c.ext) back so Choose With shows its menu again?"
        } else {
            alert.messageText = "Other apps are now the default for \(claims.count) extensions"
            let list = claims.map { "  .\($0.ext) → \($0.taker)" }.joined(separator: "\n")
            alert.informativeText = list + "\n\nTake them back so Choose With shows its menu again?"
        }
        alert.addButton(withTitle: "Take Back")
        alert.addButton(withTitle: claims.count == 1 ? "Leave It" : "Leave Them")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Always take back without asking"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            Prefs.takeoverPolicy = .keep
        }
        if response == .alertFirstButtonReturn {
            takeBack(claims, limitRepeats: false)
        } else {
            for claim in claims { Registry.setLeftTo(claim.ext, app: claim.taker) }
            NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
        }
    }
}
