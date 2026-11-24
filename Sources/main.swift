// ChooseWith — when set as the default app for a file type, opening such a
// file (double-click, Return, `open file.ext`) shows an "Open With" menu at the
// mouse pointer instead of launching a fixed app.
//
// Command-line options: see CLI.swift (or run with --help).
//
// Launched with no files (double-click the app), it opens the Settings window.

import AppKit
import SwiftUI

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
    private var menuBar: MenuBarController?
    private var help: HelpWindowController?
    private var splash: SplashController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        menuBar = MenuBarController { [weak self] in self?.showSettings() }
        TakeoverGuard.shared.start()
        // Changes made from the command line while the app is running.
        DistributedNotificationCenter.default().addObserver(forName: cliChangedNotice, object: nil, queue: .main) { _ in
            NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(showHelp), name: .owpShowHelp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showSettings), name: .owpShowSettings, object: nil)
        // Started at login: stay quietly in the background so the popup is instant.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        if launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return
        }
        // Launched by opening files, the open event usually arrives first; give it a
        // moment anyway. Launched directly (no files): splash, then Settings and Help
        // (each can be turned off).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.receivedFiles else { return }
            let next = { [weak self] in
                guard let self else { return }
                self.splash = nil
                self.showSettings()
                if Prefs.showHelpOnLaunch { self.showHelp() }
            }
            guard Prefs.showSplash else { next(); return }
            let splash = SplashController()
            self.splash = splash
            splash.show(completion: next)
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

    @objc func showAbout() { Credits.showAboutPanel() }
    @objc func openRepo() { Credits.openRepo() }
    @objc func reportBug() { Credits.reportBug() }

    @objc func showHelp() {
        if help == nil {
            help = HelpWindowController()
            help?.window?.delegate = self
        }
        NSApp.setActivationPolicy(.regular)
        help?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a background app (no Dock icon) once no window of ours is left open.
        let closing = notification.object as? NSWindow
        let othersOpen = [settings?.window, help?.window].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Choose With", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Choose With", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Choose With Help", action: #selector(showHelp), keyEquivalent: "?").target = self
        helpMenu.addItem(.separator())
        helpMenu.addItem(withTitle: "GitHub", action: #selector(openRepo), keyEquivalent: "").target = self
        helpMenu.addItem(withTitle: "Report a Bug…", action: #selector(reportBug), keyEquivalent: "").target = self
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu
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
        // One lookup per distinct extension, not per file: selecting a thousand
        // .jpg files asks LaunchServices once.
        var result: [URL]? = nil
        var seenExtensions = Set<String>()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            // Files without an extension may differ in type, so check each one.
            if !ext.isEmpty, !seenExtensions.insert(ext).inserted { continue }
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            if let current = result {
                let set = Set(apps.map(\.standardizedFileURL))
                result = current.filter { set.contains($0.standardizedFileURL) }
            } else {
                result = apps
            }
        }
        return AppLists.unique(result ?? [])
    }

    private func lastUsedKey(for urls: [URL]) -> String {
        "lastApp." + (urls.first?.pathExtension.lowercased() ?? "")
    }

    private func showMenu() {
        let urls = pending
        pending.removeAll()
        guard !urls.isEmpty else { return }

        let ext = urls[0].pathExtension
        var apps = candidateApps(for: urls)
        var hiddenApps: [URL] = []
        if AppLists.isCustomized(ext) {
            // The user's own order and hidden apps for this extension.
            (apps, hiddenApps) = AppLists.arrange(apps, ext: ext)
        } else if let last = UserDefaults.standard.string(forKey: lastUsedKey(for: urls)),
                  let idx = apps.firstIndex(where: { $0.path == last }) {
            // Otherwise the last app chosen for this extension goes first.
            apps.insert(apps.remove(at: idx), at: 0)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let title = urls.count == 1 ? MenuText.safeFileName(urls[0].lastPathComponent) : "\(urls.count) files"
        menu.addItem(MenuText.header("Open “\(title)” with"))

        for (i, app) in apps.enumerated() {
            menu.addItem(appItem(app, urls: urls, key: i < 9 ? String(i + 1) : ""))
        }
        if !hiddenApps.isEmpty {
            let more = NSMenuItem(title: "More Apps", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.autoenablesItems = false
            hiddenApps.forEach { sub.addItem(appItem($0, urls: urls, key: "")) }
            more.submenu = sub
            menu.addItem(more)
        }
        if apps.isEmpty && hiddenApps.isEmpty {
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
        let prefs = NSMenuItem(title: "Choose With Settings…", action: #selector(showSettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        NSApp.activate(ignoringOtherApps: true)
        menuOpen = true
        // Start with the first app highlighted so Return picks it: once the menu is
        // tracking, a Down Arrow moves the highlight onto the first selectable row
        // (the header isn't selectable). The timer runs inside menu tracking.
        if menu.items.contains(where: { $0.action == #selector(openWith(_:)) }) {
            let highlightFirst = Timer(timeInterval: 0.01, repeats: false) { _ in
                let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: 0, context: nil, characters: down, charactersIgnoringModifiers: down,
                        isARepeat: false, keyCode: 125) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            RunLoop.main.add(highlightFirst, forMode: .common)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // popUp blocks until the menu closes; actions have already run by now.
        menuOpen = false
    }

    private func appItem(_ app: URL, urls: [URL], key: String) -> NSMenuItem {
        let item = NSMenuItem(title: AppLists.name(app), action: #selector(openWith(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = []
        item.target = self
        item.representedObject = (app, urls)
        item.image = AppLists.icon(app)
        // macOS 27 hides menu item images unless an item asks to show them.
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        item.toolTip = app.path
        return item
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
        panel.message = "Choose an app to open " + (urls.count == 1 ? "“" + MenuText.safeFileName(urls[0].lastPathComponent) + "”" : "\(urls.count) files") + " with"
        panel.prompt = "Choose"
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
