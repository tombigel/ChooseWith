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
}

struct HelpView: View {
    var close: () -> Void
    @State private var showOnLaunch = Prefs.showHelpOnLaunch

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                tip("arrow.up.to.line", "The app you chose last for each extension is listed first.")
                tip("slider.horizontal.3", "Too many apps? Click the pencil next to an extension in Settings to reorder them and hide the ones you don’t need.")
                tip("doc.on.doc", "Select several files to open them together. Only apps that can open all of them are listed.")
                tip("ellipsis.circle", "**Other…** picks any app. **Show in Finder** reveals the files.")
                tip("arrow.uturn.backward", "Removing an extension gives it back to the app that opened it before.")
                tip("hand.raised", "Apps, folders, disks, aliases and links can’t be added, so opening them always works as usual.")
                tip("menubar.rectangle", "Choose With runs in the background. Turn on **Start at login** so the menu is always instant.")
            }

            Toggle("Show this when opening Choose With", isOn: Binding(
                get: { showOnLaunch },
                set: { showOnLaunch = $0; Prefs.showHelpOnLaunch = $0 }))
                .toggleStyle(.checkbox)
                .onReceive(NotificationCenter.default.publisher(for: .owpPrefsChanged)) { _ in
                    showOnLaunch = Prefs.showHelpOnLaunch
                }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by \(Credits.author) · Version \(Credits.version)")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Link(Credits.websiteName, destination: Credits.website)
                        Text("·").foregroundStyle(.secondary)
                        Link("GitHub", destination: Credits.repo)
                        Text("·").foregroundStyle(.secondary)
                        Link("Report a bug", destination: Credits.bugReport)
                    }
                }
                .font(.caption)
                Spacer()
                Button("Open Settings") {
                    NotificationCenter.default.post(name: .owpShowSettings, object: nil)
                }
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        window.title = "About Choose With"
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
