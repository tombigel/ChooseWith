// Command-line interface (run the app's binary, or the ./choosewith wrapper, with
// an option). Every option maps to something in the app's UI.

import AppKit

let cliUsage = """
usage: choosewith <option>

Extensions
  --register ext [ext ...]       use the Choose With menu for these extensions
  --unregister ext [ext ...]     give them back to the app that opened them before
  --restore ext=bundle.id ...    hand an extension to a specific app
  --status                       extensions, their state, and all settings

Apps in the menu (app = bundle ID or app name)
  --list ext                     apps for ext, in menu order, hidden ones marked
  --order ext app[,app ...]      put these apps first, in this order
  --hide ext app [app ...]       move apps under "More Apps"
  --show ext app [app ...]       show hidden apps again
  --reset ext                    default order, all apps shown

Takeovers
  --take-back on|off             take extensions back automatically
  --take-back-now                take back every extension another app claimed

Settings
  --login on|off                 start at login
  --menubar on|off               menu bar icon
  --splash on|off                splash screen when opening Choose With
  --help-on-launch on|off        Help window when opening Choose With
"""

/// Name of the cross-process notice the CLI sends so a running copy of the app
/// refreshes its menu bar icon and Settings.
let cliChangedNotice = Notification.Name("com.tombigel.ChooseWith.changed")

private func report(_ ext: String, _ err: String?, _ okText: String) -> Bool {
    print(err.map { "✗ \($0)" } ?? "✓ .\(Registry.normalize(ext)) \(okText)")
    return err == nil
}

private func onOff(_ args: [String], _ option: String, now: Bool) -> Bool? {
    guard let arg = args.first, ["on", "off"].contains(arg) else {
        print("usage: \(option) on|off   (now \(now ? "on" : "off"))")
        return nil
    }
    return arg == "on"
}

/// Finds an app for an extension by bundle ID or (case-insensitive) name.
private func resolveApp(_ token: String, in apps: [URL]) -> URL? {
    apps.first { AppLists.key($0).caseInsensitiveCompare(token) == .orderedSame }
        ?? apps.first { AppLists.name($0).caseInsensitiveCompare(token) == .orderedSame }
}

private func extAndApps(_ rest: [String], _ usage: String) -> (String, [URL], [URL])? {
    guard rest.count >= 2, Registry.validationError(rest[0]) == nil else { print("usage: \(usage)"); return nil }
    let ext = Registry.normalize(rest[0])
    let all = AppLists.apps(forExtension: ext)
    var picked: [URL] = []
    for token in rest.dropFirst().flatMap({ $0.split(separator: ",").map(String.init) }) {
        guard let app = resolveApp(token.trimmingCharacters(in: .whitespaces), in: all) else {
            print("✗ no app “\(token)” can open .\(ext) (see --list \(ext))"); return nil
        }
        picked.append(app)
    }
    return (ext, all, picked)
}

private func printList(_ ext: String) {
    let all = AppLists.apps(forExtension: ext)
    let (shown, hidden) = AppLists.arrange(all, ext: ext)
    for (i, app) in shown.enumerated() {
        print(String(format: "%2d  ", i + 1) + AppLists.name(app) + "\t" + AppLists.key(app))
    }
    for app in hidden { print("  -  " + AppLists.name(app) + "\t" + AppLists.key(app) + "\t(hidden)") }
    if !AppLists.isCustomized(ext) { print("(default order; last-used app goes first)") }
}

func runCLI(_ args: [String]) -> Int32? {
    // Only "--option" or -h: macOS can pass other "-Key value" launch arguments.
    guard let cmd = args.first, cmd.hasPrefix("--") || cmd == "-h" else { return nil }
    let rest = Array(args.dropFirst())
    let code: Int32
    switch cmd {
    case "--help", "-h":
        print(cliUsage); return 0

    case "--register":
        guard !rest.isEmpty else { print("usage: --register ext [ext ...]"); return 2 }
        code = rest.map { report($0, Registry.register($0), "→ Choose With") }.allSatisfy { $0 } ? 0 : 1
    case "--unregister":
        guard !rest.isEmpty else { print("usage: --unregister ext [ext ...]"); return 2 }
        code = rest.map { report($0, Registry.unregister($0), "→ previous app") }.allSatisfy { $0 } ? 0 : 1
    case "--restore":
        guard !rest.isEmpty else { print("usage: --restore ext=bundle.id [...]"); return 2 }
        var ok = true
        for pair in rest {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { print("✗ bad pair: \(pair)"); ok = false; continue }
            ok = report(parts[0], Registry.setDefault(bundleID: parts[1], forExtension: parts[0]), "→ \(parts[1])") && ok
        }
        code = ok ? 0 : 1

    case "--status":
        for ext in Registry.tracked {
            let state: String
            if Registry.isActive(ext) {
                state = "Choose With"
            } else {
                state = "taken by " + (Registry.currentHandler(forExtension: ext).map(Registry.appName) ?? "no app")
            }
            var extra = ""
            if AppLists.isCustomized(ext) {
                let (s, h) = AppLists.arrange(AppLists.apps(forExtension: ext), ext: ext)
                extra = "\t\(s.count) of \(s.count + h.count) apps"
            }
            print(".\(ext)\t\(state)\(extra)")
        }
        if Registry.tracked.isEmpty { print("(no extensions)") }
        print("")
        print("take-back      \(Prefs.takeBackExtensions ? "on" : "off")")
        print("login          \(LoginItem.isEnabled ? "on" : "off")")
        print("menubar        \(Prefs.showMenuBarIcon ? "on" : "off")")
        print("splash         \(Prefs.showSplash ? "on" : "off")")
        print("help-on-launch \(Prefs.showHelpOnLaunch ? "on" : "off")")
        return 0

    case "--list":
        guard let raw = rest.first, Registry.validationError(raw) == nil else { print("usage: --list ext"); return 2 }
        printList(Registry.normalize(raw)); return 0
    case "--order":
        guard let (ext, all, picked) = extAndApps(rest, "--order ext app[,app ...]") else { return 2 }
        let pickedIDs = picked.map(AppLists.key)
        let others = AppLists.ordered(all, ext: ext).map(AppLists.key).filter { !pickedIDs.contains($0) }
        AppLists.save(ext, order: pickedIDs + others, hidden: AppLists.hidden(ext))
        printList(ext); code = 0
    case "--hide", "--show":
        guard let (ext, all, picked) = extAndApps(rest, "\(cmd) ext app [app ...]") else { return 2 }
        var hidden = AppLists.hidden(ext)
        for id in picked.map(AppLists.key) {
            if cmd == "--hide" { hidden.insert(id) } else { hidden.remove(id) }
        }
        AppLists.save(ext, order: AppLists.ordered(all, ext: ext).map(AppLists.key), hidden: hidden)
        printList(ext); code = 0
    case "--reset":
        guard let raw = rest.first, Registry.validationError(raw) == nil else { print("usage: --reset ext"); return 2 }
        AppLists.reset(raw)
        printList(Registry.normalize(raw)); code = 0

    case "--take-back":
        guard let on = onOff(rest, cmd, now: Prefs.takeBackExtensions) else { return 2 }
        Prefs.takeBackExtensions = on
        print("take-back " + (on ? "on" : "off")); code = 0
    case "--take-back-now":
        let taken = TakeoverGuard.takenExtensions()
        guard !taken.isEmpty else { print("Nothing to take back."); return 0 }
        code = taken.map { report($0, Registry.register($0), "taken back") }.allSatisfy { $0 } ? 0 : 1

    case "--login":
        guard let on = onOff(rest, cmd, now: LoginItem.isEnabled) else { return 2 }
        print(LoginItem.set(on))
        code = LoginItem.isEnabled == on ? 0 : 1
    case "--menubar":
        guard let on = onOff(rest, cmd, now: Prefs.showMenuBarIcon) else { return 2 }
        Prefs.showMenuBarIcon = on; print("menubar " + (on ? "on" : "off")); code = 0
    case "--splash":
        guard let on = onOff(rest, cmd, now: Prefs.showSplash) else { return 2 }
        Prefs.showSplash = on; print("splash " + (on ? "on" : "off")); code = 0
    case "--help-on-launch":
        guard let on = onOff(rest, cmd, now: Prefs.showHelpOnLaunch) else { return 2 }
        Prefs.showHelpOnLaunch = on; print("help-on-launch " + (on ? "on" : "off")); code = 0

    default:
        print("unknown option \(cmd)\n\n" + cliUsage); return 2
    }
    // Tell a running copy of the app to pick up the change.
    UserDefaults.standard.synchronize()
    DistributedNotificationCenter.default().postNotificationName(cliChangedNotice, object: nil, userInfo: nil, deliverImmediately: true)
    return code
}
