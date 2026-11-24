// OpenWithPopup — when set as the default app for a file type, opening such a
// file (double-click, Return, `open file.ext`) shows an "Open With" menu at the
// mouse pointer instead of launching a fixed app.
//
// CLI:
//   OpenWithPopup --register ext [ext ...]    make this app the default for these extensions
//   OpenWithPopup --unregister ext [ext ...]  give these extensions back to their previous default
//   OpenWithPopup --restore ext=bundle.id ... hand an extension to a specific app
//   OpenWithPopup --status                    show each managed extension and its current default
//   OpenWithPopup --list ext                  print the apps that can open an extension
//
// Launched with no files (double-click the app), it opens the Settings window.

import AppKit
import SwiftUI

// MARK: - CLI

func report(_ ext: String, _ err: String?, _ okText: String) -> Bool {
    print(err.map { "✗ \($0)" } ?? "✓ .\(Registry.normalize(ext)) \(okText)")
    return err == nil
}

func runCLI(_ args: [String]) -> Int32? {
    guard let cmd = args.first, cmd.hasPrefix("--") else { return nil }
    let rest = Array(args.dropFirst())
    switch cmd {
    case "--register":
        guard !rest.isEmpty else { print("usage: --register ext [ext ...]"); return 2 }
        return rest.map { report($0, Registry.register($0), "→ popup") }.allSatisfy { $0 } ? 0 : 1
    case "--unregister":
        guard !rest.isEmpty else { print("usage: --unregister ext [ext ...]"); return 2 }
        return rest.map { report($0, Registry.unregister($0), "→ previous app") }.allSatisfy { $0 } ? 0 : 1
    case "--restore":
        guard !rest.isEmpty else { print("usage: --restore ext=bundle.id [...]"); return 2 }
        var ok = true
        for pair in rest {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { print("✗ bad pair: \(pair)"); ok = false; continue }
            ok = report(parts[0], Registry.setDefault(bundleID: parts[1], forExtension: parts[0]), "→ \(parts[1])") && ok
        }
        return ok ? 0 : 1
    case "--status":
        for ext in Registry.tracked {
            let h = Registry.currentHandler(forExtension: ext) ?? "none"
            print(".\(ext)\t\(Registry.isActive(ext) ? "popup" : "→ " + h)")
        }
        return 0
    case "--list":
        guard let ext = rest.first, let type = Registry.utType(forExtension: ext) else { print("usage: --list ext"); return 2 }
        for url in NSWorkspace.shared.urlsForApplications(toOpen: type) {
            print("\(Bundle(url: url)?.bundleIdentifier ?? "?")\t\(url.path)")
        }
        return 0
    default:
        print("unknown option \(cmd)"); return 2
    }
}

// Skip -psn_ style args macOS may pass when launched by LaunchServices.
let cliArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") && !$0.hasPrefix("-NS") }
if let code = runCLI(Array(cliArgs)) { exit(code) }

// MARK: - Popup app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var pending: [URL] = []
    private var flushScheduled = false
    private var menuOpen = false
    private var receivedFiles = false
    private var settings: SettingsWindowController?


    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        // Started at login: stay quietly in the background so the popup is instant.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        if launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return
        }
        // Launched by opening files, the open event usually arrives first; give it a
        // moment anyway. Launched directly (no files): show Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.receivedFiles else { return }
            self.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc func showSettings() {
        if settings == nil {
            settings = SettingsWindowController()
            settings?.window?.delegate = self
        }
        NSApp.setActivationPolicy(.regular)
        settings?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Open With Popup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        pending.append(contentsOf: urls)
        // Finder sends a multi-file selection as one event; waiting a single run-loop
        // turn still merges any back-to-back events without a visible delay.
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushScheduled = false
            self?.showMenu()
        }
    }

    // The app stays running in the background (no Dock icon) after first use, so later
    // opens skip app startup and the menu appears immediately.

    private func candidateApps(for urls: [URL]) -> [URL] {
        // Apps that can open every file in the selection, in LaunchServices order.
        var result: [URL]? = nil
        for url in urls {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            if let current = result {
                let set = Set(apps.map(\.standardizedFileURL))
                result = current.filter { set.contains($0.standardizedFileURL) }
            } else {
                result = apps
            }
        }
        var seen = Set<String>()
        return (result ?? []).filter { app in
            let id = Bundle(url: app)?.bundleIdentifier ?? app.path
            guard id != selfBundleID, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private func lastUsedKey(for urls: [URL]) -> String {
        "lastApp." + (urls.first?.pathExtension.lowercased() ?? "")
    }

    private func showMenu() {
        let urls = pending
        pending.removeAll()
        guard !urls.isEmpty else { return }

        var apps = candidateApps(for: urls)
        // Put the last app chosen for this extension first.
        if let last = UserDefaults.standard.string(forKey: lastUsedKey(for: urls)),
           let idx = apps.firstIndex(where: { $0.path == last }) {
            apps.insert(apps.remove(at: idx), at: 0)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        let header = NSMenuItem(title: "Open “\(title)” with", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for (i, app) in apps.enumerated() {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            let key = i < 9 ? String(i + 1) : ""
            let item = NSMenuItem(title: name, action: #selector(openWith(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = (app, urls)
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if apps.isEmpty {
            let none = NSMenuItem(title: "No apps found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }

        menu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(chooseOther(_:)), keyEquivalent: "")
        other.target = self
        other.representedObject = urls
        menu.addItem(other)
        let reveal = NSMenuItem(title: "Show in Finder", action: #selector(reveal(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = urls
        menu.addItem(reveal)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Open With Popup Settings…", action: #selector(showSettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        NSApp.activate(ignoringOtherApps: true)
        menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // popUp blocks until the menu closes; actions have already run by now.
        menuOpen = false
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let (app, urls) = sender.representedObject as? (URL, [URL]) else { return }
        UserDefaults.standard.set(app.path, forKey: lastUsedKey(for: urls))
        open(urls, with: app)
    }

    @objc private func chooseOther(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        menuOpen = true
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application, .applicationBundle]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let app = panel.url {
            UserDefaults.standard.set(app.path, forKey: lastUsedKey(for: urls))
            open(urls, with: app)
        }
        menuOpen = false
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func open(_ urls: [URL], with app: URL) {
        menuOpen = true
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { NSAlert(error: error).runModal() }
                self?.menuOpen = false
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
