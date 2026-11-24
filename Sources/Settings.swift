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
        VStack(alignment: .leading, spacing: 12) {
            let taken = model.rows.filter { !$0.active }
            if !taken.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: MenuSummary.takenText(taken.map(\.ext))).bold()
                        Text(taken.count == 1
                             ? "Files with this extension open directly, without the Choose With menu."
                             : "Files with these extensions open directly, without the Choose With menu.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(taken.count == 1 ? "Take It Back" : "Take Back All") {
                        TakeoverGuard.shared.takeBackAll()
                        model.reload()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.orange.opacity(0.5)))
                .accessibilityElement(children: .combine)
            }

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
                        // Only worth showing when something's wrong: another app took over.
                        if !row.active {
                            Label { Text(verbatim: "Opens in " + (row.handlerName ?? "no app")) }
                                icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                .foregroundStyle(.orange)
                                .help("Another app became the default for this extension.")
                            Button("Take Back") { model.reenable(row.ext) }
                                .controlSize(.small)
                        }
                        if let note = row.note {
                            Text(verbatim: note)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let summary = row.appSummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
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
                    .padding(.vertical, 2)
                    .listRowBackground(row.active ? nil : Color.orange.opacity(0.15))
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)
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
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Take extensions back if another app claims them", isOn: Binding(
                    get: { model.takeBack },
                    set: { on in
                        Prefs.takeBackExtensions = on
                        // Ask for notification permission here, when it's clearly needed.
                        if on { Notifier.requestPermission() }
                        TakeoverGuard.shared.check()
                    }))
                Text("Apps can make themselves the default for a file type. When this is off, Choose With warns you in the menu bar and here instead.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
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
                Button {
                    NotificationCenter.default.post(name: .owpShowHelp, object: nil)
                } label: {
                    Image(systemName: "questionmark")
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .controlSize(.small)
                .help("How Choose With works")
                .accessibilityLabel("Help")
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 460)
    }
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Choose With Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        // Room for the Customize buttons, even if a smaller size was saved earlier.
        window.contentMinSize = NSSize(width: 600, height: 520)
        if window.frame.width < 600 || window.frame.height < 540 {
            window.setContentSize(NSSize(width: 620, height: 560))
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
