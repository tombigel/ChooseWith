// Menu bar icon, its menu, and the preferences it shares with the Settings window.

import AppKit
import ServiceManagement

extension Notification.Name {
    static let owpPrefsChanged = Notification.Name("ChooseWithPrefsChanged")
}

enum Prefs {
    private static let menuBarKey = "showMenuBarIcon"

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
    private static func setFlag(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
    }

    /// Splash screen when the app is opened directly. On by default.
    static var showSplash: Bool {
        get { flag("showSplash") }
        set { setFlag("showSplash", newValue) }
    }

    /// Help window after the splash when the app is opened directly. On by default.
    static var showHelpOnLaunch: Bool {
        get { flag("showHelpOnLaunch") }
        set { setFlag("showHelpOnLaunch", newValue) }
    }

    /// Shown by default; hidden only when the user turns it off.
    static var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: menuBarKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: menuBarKey)
            NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns Start at login on or off and returns a message for the user.
    @discardableResult
    static func set(_ on: Bool) -> String {
        var message: String
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = on ? "Choose With will start at login." : "Choose With won't start at login."
        } catch {
            message = "Couldn't change Start at login: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval {
            message = "Allow Choose With in System Settings → General → Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
        NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
        return message
    }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let showSettings: () -> Void

    init(showSettings: @escaping () -> Void) {
        self.showSettings = showSettings
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .owpPrefsChanged, object: nil)
        update()
    }

    @objc func update() {
        if Prefs.showMenuBarIcon, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "Choose With")
                ?? NSImage(systemSymbolName: "filemenu.and.selection", accessibilityDescription: "Choose With")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = "Choose With"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !Prefs.showMenuBarIcon, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    // Rebuilt each time it opens so it always shows the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "Choose With", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let tracked = Registry.tracked
        let active = tracked.filter(Registry.isActive)
        let summary: String
        if tracked.isEmpty {
            summary = "No extensions yet"
        } else {
            summary = active.isEmpty ? "No extensions active" : active.map { ".\($0)" }.joined(separator: ", ")
        }
        let info = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        if active.count < tracked.count {
            let warn = NSMenuItem(title: "\(tracked.count - active.count) need re-enabling in Settings", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("How it works?", #selector(openHelp)))
        menu.addItem(makeItem("About Choose With", #selector(openAbout)))
        menu.addItem(makeItem("Choose With on GitHub", #selector(openRepo)))
        menu.addItem(makeItem("Report a Bug…", #selector(reportBug)))
        menu.addItem(.separator())
        let login = makeItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(makeItem("Hide Menu Bar Icon", #selector(hideIcon)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Choose With", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { showSettings() }

    @objc private func openAbout() { Credits.showAboutPanel() }
    @objc private func openRepo() { Credits.openRepo() }
    @objc private func reportBug() { Credits.reportBug() }

    @objc private func openHelp() { NotificationCenter.default.post(name: .owpShowHelp, object: nil) }

    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }

    @objc private func hideIcon() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = "Choose With keeps working. To show the icon again, open Choose With from Spotlight or your Applications folder and turn it back on in Settings."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Prefs.showMenuBarIcon = false
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
