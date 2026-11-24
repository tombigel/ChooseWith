// Settings window: add and remove the extensions that open with the popup.

import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Row: Identifiable {
        let ext: String
        let active: Bool
        let handlerName: String?
        let appSummary: String?    // "8 of 23 apps" when customized
        var id: String { ext }
    }

    @Published var rows: [Row] = []
    @Published var input = ""
    @Published var message: String?
    @Published var launchAtLogin = LoginItem.isEnabled

    init() {
        reload()
        // Stay in sync when these are changed from the menu bar icon.
        NotificationCenter.default.addObserver(forName: .owpPrefsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.launchAtLogin = LoginItem.isEnabled
            self?.showMenuBarIcon = Prefs.showMenuBarIcon
            self?.showSplash = Prefs.showSplash
            self?.showHelpOnLaunch = Prefs.showHelpOnLaunch
        }
        // Apps may have been installed or removed, or defaults changed, while away.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    @Published var showMenuBarIcon = Prefs.showMenuBarIcon
    @Published var showSplash = Prefs.showSplash
    @Published var showHelpOnLaunch = Prefs.showHelpOnLaunch

    func setLaunchAtLogin(_ on: Bool) {
        message = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }

    func setShowMenuBarIcon(_ on: Bool) {
        Prefs.showMenuBarIcon = on
        message = on ? "Menu bar icon shown." : "Menu bar icon hidden. Open the app again to get back here."
    }

    func reload() {
        launchAtLogin = LoginItem.isEnabled
        showMenuBarIcon = Prefs.showMenuBarIcon
        rows = Registry.tracked.map { ext in
            let handler = Registry.currentHandler(forExtension: ext)
            var summary: String? = nil
            if AppLists.isCustomized(ext) {
                let (shown, hidden) = AppLists.arrange(AppLists.apps(forExtension: ext), ext: ext)
                summary = "\(shown.count) of \(shown.count + hidden.count) apps"
            }
            return Row(ext: ext, active: Registry.isActive(ext), handlerName: handler.map(Registry.appName),
                       appSummary: summary)
        }
    }

    func add() {
        let exts = Registry.parse(input)
        guard !exts.isEmpty else { return }
        let errors = exts.compactMap(Registry.register)
        input = ""
        finish(errors, success: "Added " + exts.map { ".\($0)" }.joined(separator: ", "))
    }

    func remove(_ ext: String) {
        let err = Registry.unregister(ext)
        finish(err.map { [$0] } ?? [], success: "Removed .\(ext)")
    }

    func reenable(_ ext: String) {
        let err = Registry.register(ext)
        finish(err.map { [$0] } ?? [], success: "Re-enabled .\(ext)")
    }

    private func finish(_ errors: [String], success: String) {
        message = errors.isEmpty ? success : errors.joined(separator: "\n")
        reload()
        // LaunchServices can take a moment to report the new default.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reload() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var customizing: CustomizeTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files with these extensions let you choose which app opens them, every time.")
                .foregroundStyle(.secondary)

            List {
                if model.rows.isEmpty {
                    Text("No extensions yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    HStack(spacing: 10) {
                        Text(verbatim: "." + row.ext)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 70, alignment: .leading)
                        if row.active {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label { Text(verbatim: "Opens in " + (row.handlerName ?? "no app")) }
                                icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                .foregroundStyle(.orange)
                                .help("Another app became the default for this extension.")
                            Button("Re-enable") { model.reenable(row.ext) }
                                .controlSize(.small)
                        }
                        Spacer()
                        if let summary = row.appSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Customize…") { customizing = CustomizeTarget(ext: row.ext) }
                            .controlSize(.small)
                            .help(Text(verbatim: "Reorder and hide apps in the menu for ." + row.ext))
                        Button {
                            model.remove(row.ext)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(Text(verbatim: "Remove ." + row.ext + " and give it back to its previous app"))
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)
            .sheet(item: $customizing) { target in
                CustomizeView(model: CustomizeModel(ext: target.ext)) {
                    customizing = nil
                    model.reload()
                }
            }

            HStack {
                TextField("Add extensions, e.g. md, txt, json", text: $model.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.add() }
                Button("Add") { model.add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Registry.parse(model.input).isEmpty)
            }

            Toggle("Start at login, so the menu appears instantly", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))
            Toggle("Show icon in menu bar", isOn: Binding(
                get: { model.showMenuBarIcon },
                set: { model.setShowMenuBarIcon($0) }))
            Toggle("Show splash screen when opening Choose With", isOn: Binding(
                get: { model.showSplash },
                set: { Prefs.showSplash = $0 }))
            Toggle("Show Help when opening Choose With", isOn: Binding(
                get: { model.showHelpOnLaunch },
                set: { Prefs.showHelpOnLaunch = $0 }))
            Text("Choose With keeps running in the background without a Dock icon. Quit it from the menu bar icon, or with ⌘Q in this window.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(alignment: .top) {
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Refresh") { model.reload() }
                    .controlSize(.small)
                Button {
                    NotificationCenter.default.post(name: .owpShowHelp, object: nil)
                } label: {
                    Image(systemName: "questionmark")
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .controlSize(.small)
                .help("How Choose With works")
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 460)
    }
}

final class SettingsWindowController: NSWindowController {
    let model = SettingsModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Choose With Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        // Room for the Customize buttons, even if a smaller size was saved earlier.
        window.contentMinSize = NSSize(width: 540, height: 500)
        if window.frame.width < 560 || window.frame.height < 520 {
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
        }
        self.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    func show() {
        model.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
