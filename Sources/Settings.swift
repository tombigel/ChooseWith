// Settings window: add and remove the extensions that open with the popup.

import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Row: Identifiable {
        let ext: String
        let active: Bool
        let handlerName: String?
        let appSummary: String?    // "8 of 23 apps" when customized
        let note: String?          // take-back history, e.g. "Taken back from Inkscape"
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
            self?.takeBack = Prefs.takeBackExtensions
            self?.reload()
        }
        NotificationCenter.default.addObserver(forName: .owpCustomizeExtension, object: nil, queue: .main) { [weak self] note in
            self?.customizeRequest = note.object as? String
        }
        // Apps may have been installed or removed, or defaults changed, while away.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    @Published var showMenuBarIcon = Prefs.showMenuBarIcon
    @Published var takeBack = Prefs.takeBackExtensions
    /// Set when the menu bar asks for one extension's Customize sheet.
    @Published var customizeRequest: String?
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

    // MARK: Export / Import

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Choose With Settings.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Save your extensions, app lists and settings to a file you can import on another Mac."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigIO.exportData().write(to: url, options: .atomic)
            message = "Exported to " + url.lastPathComponent
        } catch {
            message = "Couldn’t export: " + error.localizedDescription
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Choose With settings file. You’ll see what changes before anything is applied."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let config: ChooseWithConfig
        do {
            config = try ConfigIO.load(ConfigIO.read(url))
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t import “\(MenuText.safeFileName(url.lastPathComponent))”"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        let changes = ConfigIO.changes(config)
        guard !changes.isEmpty else { message = "Nothing to change: this Mac already matches the file."; return }
        let alert = NSAlert()
        alert.messageText = "Import settings from “\(MenuText.safeFileName(url.lastPathComponent))”?"
        alert.informativeText = "This will:\n" + changes.map { "• " + $0 }.joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let errors = ConfigIO.apply(config)
        message = errors.isEmpty ? "Imported settings." : errors.joined(separator: "\n")
        reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reload() }
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
            var note: String? = nil
            if let taker = Registry.gaveUpTo(ext) {
                note = taker + " keeps taking it"
            } else if let from = Registry.takenBackFrom(ext) {
                note = "Taken back from " + from
                if let at = Registry.takenBackAt(ext) { note! += " · " + Notifier.when(at) }
            }
            return Row(ext: ext, active: Registry.isActive(ext), handlerName: handler.map(Registry.appName),
                       appSummary: summary, note: note)
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
        finish(err.map { [$0] } ?? [], success: "Took back .\(ext)")
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
        VStack(spacing: 0) {
            Form {
                extensionsSection
                behaviorSection
                openingSection
            }
            .formStyle(.grouped)

            HStack(alignment: .center) {
                Button("Export…") { model.exportSettings() }
                    .help("Save your extensions, app lists and settings to a file")
                Button("Import…") { model.importSettings() }
                    .help("Load settings from a file exported on this or another Mac")
                if let message = model.message {
                    Text(message).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .owpShowHelp, object: nil)
                } label: {
                    Image(systemName: "questionmark")
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .help("How Choose With works")
                .accessibilityLabel("Help")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(width: WindowSize.settings.width, height: WindowSize.settings.height)
        .onReceive(model.$customizeRequest) { ext in
            guard let ext else { return }
            customizing = CustomizeTarget(ext: ext)
            model.customizeRequest = nil
        }
        .sheet(item: $customizing) { target in
            CustomizeView(model: CustomizeModel(ext: target.ext)) {
                customizing = nil
                model.reload()
            }
        }
    }

    // MARK: Sections

    private var extensionsSection: some View {
        Section {
            let taken = model.rows.filter { !$0.active }
            if !taken.isEmpty { takenBanner(taken) }

            if model.rows.isEmpty {
                Text("No extensions yet. Add one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in extensionRow(row) }

            HStack {
                TextField("Add extensions", text: $model.input, prompt: Text("Add extensions, e.g. md, txt, json"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.add() }
                Button("Add") { model.add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Registry.parse(model.input).isEmpty)
            }
        } header: {
            Text("Extensions")
        } footer: {
            Text("Files with these extensions let you choose which app opens them, every time.")
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle(isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) })) {
                Text("Start at login")
                Text("The menu appears instantly, even right after a restart.")
            }
            Toggle(isOn: Binding(
                get: { model.takeBack },
                set: { on in
                    Prefs.takeBackExtensions = on
                    // Ask for notification permission here, when it's clearly needed.
                    if on { Notifier.requestPermission() }
                    TakeoverGuard.shared.check()
                })) {
                Text("Take extensions back if another app claims them")
                Text("Apps can make themselves the default for a file type. When this is off, Choose With warns you in the menu bar and here instead.")
            }
        }
    }

    private var openingSection: some View {
        Section {
            Toggle("Show icon in menu bar", isOn: Binding(
                get: { model.showMenuBarIcon },
                set: { model.setShowMenuBarIcon($0) }))
            Toggle("Show splash screen when opening Choose With", isOn: Binding(
                get: { model.showSplash },
                set: { Prefs.showSplash = $0 }))
            Toggle("Show Help when opening Choose With", isOn: Binding(
                get: { model.showHelpOnLaunch },
                set: { Prefs.showHelpOnLaunch = $0 }))
        } header: {
            Text("Appearance")
        } footer: {
            Label("Choose With keeps running in the background without a Dock icon. Quit it from the menu bar icon, or with ⌘Q in this window.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    private func takenBanner(_ taken: [SettingsModel.Row]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: MenuSummary.takenText(taken.map(\.ext))).bold()
                Text(taken.count == 1
                     ? "Files with this extension open directly, without the Choose With menu."
                     : "Files with these extensions open directly, without the Choose With menu.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(taken.count == 1 ? "Take It Back" : "Take Back All") {
                TakeoverGuard.shared.takeBackAll()
                model.reload()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }

    private func extensionRow(_ row: SettingsModel.Row) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "." + row.ext)
                    .font(.system(.body, design: .monospaced))
                if !row.active {
                    Label { Text(verbatim: "Opens in " + (row.handlerName ?? "no app")) }
                        icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(.orange)
                        .help("Another app became the default for this extension.")
                }
                // Secondary details as a readable subtitle, like System Settings.
                let details = [row.appSummary, row.note].compactMap { $0 }
                if !details.isEmpty {
                    Text(verbatim: details.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if !row.active {
                Button("Take Back") { model.reenable(row.ext) }
            }
            IconButton(symbol: "pencil",
                       label: "Customize apps for ." + row.ext,
                       tooltip: "Customize apps for ." + row.ext + ": reorder and hide") {
                customizing = CustomizeTarget(ext: row.ext)
            }
            IconButton(symbol: "trash",
                       label: "Remove ." + row.ext,
                       tooltip: "Remove ." + row.ext + " and give it back to its previous app",
                       hoverTint: .red) {
                model.remove(row.ext)
            }
        }
    }
}

/// Window sizes, kept in proportion: Settings is the main window, Help a slightly
/// narrower companion, the Customize sheet fits inside Settings with even margins,
/// and the splash is the smallest.
enum WindowSize {
    static let settings = NSSize(width: 600, height: 680)
    static let helpWidth: CGFloat = 520
    static let sheetWidth: CGFloat = 480
    static let splashWidth: CGFloat = 420
}

/// Small icon-only button for list rows: a soft highlight (and optional tint) on
/// hover, a tooltip, and a spoken label for VoiceOver.
struct IconButton: View {
    let symbol: String
    let label: String
    let tooltip: String
    var hoverTint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .foregroundStyle(hovering ? hoverTint : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(Text(verbatim: tooltip))
        .accessibilityLabel(Text(verbatim: label))
    }
}

final class SettingsWindowController: NSWindowController {
    let model = SettingsModel()

    convenience init() {
        // Fixed size, like other Mac settings windows; the form scrolls if the
        // extension list grows.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowSize.settings),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Choose With Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")   // remembers position
        window.setContentSize(WindowSize.settings)       // ignore any older saved size
        self.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    func show() {
        model.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
