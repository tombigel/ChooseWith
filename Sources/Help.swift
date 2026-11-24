// Help window: a short explanation of what the app does and how to use it.

import AppKit
import SwiftUI

enum Credits {
    static let author = "Tom Bigelajzen"
    static let websiteName = "tombigel.com"
    static let website = URL(string: "https://tombigel.com")!
    static let repo = URL(string: "https://github.com/tombigel/ChooseWith")!
    static let bugReport = URL(string: "https://github.com/tombigel/ChooseWith/issues/new")!

    static func openRepo() { NSWorkspace.shared.open(repo) }
    static func reportBug() { NSWorkspace.shared.open(bugReport) }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 \(author)"
    }

    /// The standard macOS About window, with the author credit.
    static func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Choose With",
            .credits: aboutCredits(),
        ])
    }

    private static func aboutCredits() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let text = NSMutableAttributedString(
            string: "Made by \(author)\n",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para])
        text.append(NSAttributedString(
            string: websiteName,
            attributes: [.font: font, .link: website, .paragraphStyle: para]))
        text.append(NSAttributedString(
            string: " · ",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
        text.append(NSAttributedString(
            string: "GitHub",
            attributes: [.font: font, .link: repo, .paragraphStyle: para]))
        return text
    }
}

extension Notification.Name {
    /// Posted by any view or menu that wants the Help or Settings window shown.
    static let owpShowHelp = Notification.Name("ChooseWithShowHelp")
    static let owpShowSettings = Notification.Name("ChooseWithShowSettings")
    static let owpSettingsVisibility = Notification.Name("ChooseWithSettingsVisibility")
    /// Opens Settings at one extension's Customize sheet; `object` is the extension.
    static let owpCustomizeExtension = Notification.Name("ChooseWithCustomizeExtension")
}

/// Whether the Settings window is open, so Help can hide its "Open Settings" button.
enum WindowState {
    static var settingsOpen = false {
        didSet { NotificationCenter.default.post(name: .owpSettingsVisibility, object: nil) }
    }
}

struct HelpView: View {
    var close: () -> Void
    @State private var showOnLaunch = Prefs.showHelpOnLaunch
    @State private var settingsOpen = WindowState.settingsOpen

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose With").font(.title2.bold())
                    Text("Don’t just open with. Choose with.")
                        .foregroundStyle(.secondary)
                }
            }

            section("How it works") {
                step(1, "Add file extensions in Settings, like **md** or **json**. macOS may ask you to confirm.")
                step(2, "Open one of those files the usual way: double-click it, or select it and press ⌘↓.")
                step(3, "A menu appears at your pointer. Choose the app to open it with.")
            }

            section("Tips") {
                tip("keyboard", "Press **Return** for the first app, **1–9** to pick another, or **Esc** to cancel.")
                tip("slider.horizontal.3", "Click the pencil next to an extension in Settings to reorder its apps and hide the ones you don’t need. Until you do, the app you chose last is listed first.")
                tip("doc.on.doc", "Select several files to open them together. Only apps that can open all of them are listed.")
                tip("ellipsis.circle", "**Other…** picks any app. **Show in Finder** reveals the files.")
                tip("arrow.uturn.backward", "Removing an extension gives it back to the app that opened it before.")
                tip("arrow.uturn.left.circle", "If another app makes itself the default for one of your extensions, the menu bar icon turns orange. Take it back from there or Settings, or turn on **Take extensions back** to do it automatically.")
                tip("square.and.arrow.up", "Moving to another Mac? **Export…** in Settings saves your setup to a file, and **Import…** loads it.")
                tip("hand.raised", "Apps, folders, disks, aliases and links can’t be added, so opening them always works as usual.")
                tip("menubar.rectangle", "Choose With runs in the background. Turn on **Start at login** so the menu is always instant.")
            }

            // Pins the footer to the window's bottom edge, level with Settings'.
            Spacer(minLength: 0)

            Toggle("Show this when opening Choose With", isOn: Binding(
                get: { showOnLaunch },
                set: { showOnLaunch = $0; Prefs.showHelpOnLaunch = $0 }))
                .toggleStyle(.checkbox)
                .onReceive(NotificationCenter.default.publisher(for: .owpPrefsChanged)) { _ in
                    showOnLaunch = Prefs.showHelpOnLaunch
                }

            Text("Made by \(Credits.author) · Version \(Credits.version)")
                .font(.callout).foregroundStyle(.secondary)

            // One footer row, the same height and bottom margin as Settings', so the
            // buttons line up when the two windows sit side by side.
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    Link(Credits.websiteName, destination: Credits.website)
                    Text("·").foregroundStyle(.secondary)
                    Link("GitHub", destination: Credits.repo)
                    Text("·").foregroundStyle(.secondary)
                    Link("Report a bug", destination: Credits.bugReport)
                }
                .font(.callout)
                Spacer()
                // Not needed while Settings is already open beside Help.
                if !settingsOpen {
                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .owpShowSettings, object: nil)
                    }
                }
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(height: WindowSize.footerHeight)
        }
        .padding(.horizontal, WindowSize.edgeInset)
        .padding(.top, 16)
        .padding(.bottom, WindowSize.edgeInset)
        // Same height as Settings, so the two line up side by side.
        .frame(width: WindowSize.helpWidth, height: WindowSize.settings.height, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .owpSettingsVisibility)) { _ in
            settingsOpen = WindowState.settingsOpen
        }
        .onExitCommand { close() }   // Esc closes, like other help windows
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tip(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class HelpWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Choose With Help"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.contentView = NSHostingView(rootView: HelpView { [weak window] in window?.close() })
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
