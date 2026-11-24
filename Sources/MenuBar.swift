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

    /// Switch extensions back automatically when another app claims them. Off by
    /// default, so a default the user changes on purpose (Get Info) isn't undone;
    /// takeovers are always flagged in the menu bar and Settings either way.
    static var takeBackExtensions: Bool {
        get { UserDefaults.standard.object(forKey: "takeBackExtensions") as? Bool ?? false }
        set { setFlag("takeBackExtensions", newValue) }
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

/// Text for the menu bar menu's summary lines, kept short whatever the input.
enum MenuSummary {
    /// Up to `maxNames` extensions within about `maxChars` characters, then "+N more".
    static func line(active: [String], tracked: [String], maxNames: Int = 4, maxChars: Int = 36) -> String {
        if tracked.isEmpty { return "No extensions yet" }
        if active.isEmpty { return tracked.count == 1 ? "1 extension, not active" : "\(tracked.count) extensions, none active" }
        var names: [String] = []
        for ext in active {
            // The "+N more" suffix counts toward the limit too. The first name is
            // always included (shortened below if it's too long on its own).
            let next = (names + ["." + ext]).joined(separator: ", ")
            let remaining = active.count - names.count - 1
            let suffix = remaining > 0 ? " +\(remaining) more" : ""
            if !names.isEmpty && (names.count == maxNames || next.count + suffix.count > maxChars) { break }
            names.append("." + ext)
        }
        // A single very long extension still has to fit.
        if names.count == 1, names[0].count > maxChars {
            names[0] = String(names[0].prefix(maxChars - 1)) + "…"
        }
        let rest = active.count - names.count
        return names.joined(separator: ", ") + (rest > 0 ? " +\(rest) more" : "")
    }

    /// ".svg now opens in Inkscape", or "3 extensions now open in other apps".
    static func takenText(_ taken: [String]) -> String {
        if taken.count == 1, let ext = taken.first {
            let app = Registry.currentHandler(forExtension: ext).map(Registry.appName) ?? "another app"
            return "." + ext + " now opens in " + app
        }
        return "\(taken.count) extensions now open in other apps"
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
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        updateWarningBadge()
    }

    /// When another app has taken any extension: an orange icon with the count
    /// beside it, and a tooltip saying which. Back to normal once none are taken.
    private func updateWarningBadge() {
        guard let button = item?.button else { return }
        let taken = TakeoverGuard.takenExtensions()
        if taken.isEmpty {
            button.contentTintColor = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.toolTip = "Choose With"
            button.setAccessibilityLabel("Choose With")
        } else {
            button.contentTintColor = .systemOrange
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: "\(taken.count)",
                attributes: [.foregroundColor: NSColor.systemOrange,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)])
            let text = MenuSummary.takenText(taken)
            button.toolTip = "Choose With: " + text
            button.setAccessibilityLabel("Choose With, warning: " + text)
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
        let inactive = tracked.count - active.count

        // One short line however many extensions there are; the full list is in
        // its submenu, which scrolls if it gets long.
        let info = NSMenuItem(title: MenuSummary.line(active: active, tracked: tracked), action: nil, keyEquivalent: "")
        if tracked.isEmpty {
            info.isEnabled = false
        } else {
            info.submenu = extensionsSubmenu(tracked)
        }
        menu.addItem(info)
        // Recent automatic take-back, so it's visible even without notifications.
        if let last = Registry.lastTakeBack(), Date().timeIntervalSince(last.at) < 24 * 60 * 60 {
            let info = NSMenuItem(title: "Took back ." + last.ext + " from " + last.app + " · " + Notifier.when(last.at),
                                  action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if inactive > 0 {
            let warn = makeItem(MenuSummary.takenText(TakeoverGuard.takenExtensions()) + "…", #selector(openSettings))
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            if #available(macOS 27.0, *) { warn.preferredImageVisibility = .visible }
            menu.addItem(warn)
            menu.addItem(makeItem(inactive == 1 ? "Take It Back" : "Take Back All", #selector(takeBackAll)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("How it works?", #selector(openHelp)))
        menu.addItem(makeItem("About", #selector(openAbout)))
        menu.addItem(makeItem("GitHub", #selector(openRepo)))
        menu.addItem(makeItem("Report a Bug…", #selector(reportBug)))
        menu.addItem(.separator())
        let login = makeItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(makeItem("Hide Menu Bar Icon", #selector(hideIcon)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit", #selector(quit), key: "q"))
    }

    /// Every managed extension, one per row; problems show what opens them now.
    private func extensionsSubmenu(_ tracked: [String]) -> NSMenu {
        let sub = NSMenu()
        for ext in tracked {
            let item: NSMenuItem
            if Registry.isActive(ext) {
                item = makeItem("." + ext, #selector(openExtension(_:)))
            } else {
                let handler = Registry.currentHandler(forExtension: ext).map(Registry.appName) ?? "no app"
                item = makeItem("." + ext + " (opens in " + handler + ")", #selector(openExtension(_:)))
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Warning")
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            }
            item.representedObject = ext
            item.toolTip = "Customize apps for ." + ext
            sub.addItem(item)
        }
        return sub
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { showSettings() }

    @objc private func takeBackAll() { TakeoverGuard.shared.takeBackAll() }

    @objc private func openExtension(_ sender: NSMenuItem) {
        guard let ext = sender.representedObject as? String else { return }
        showSettings()
        NotificationCenter.default.post(name: .owpCustomizeExtension, object: ext)
    }

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
