// Settings window: add and remove the extensions that open with the popup.

import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Row: Identifiable {
        let ext: String
        let active: Bool
        let handlerName: String?
        var id: String { ext }
    }

    @Published var rows: [Row] = []
    @Published var input = ""
    @Published var message: String?

    init() { reload() }

    func reload() {
        rows = Registry.tracked.map { ext in
            let handler = Registry.currentHandler(forExtension: ext)
            return Row(ext: ext, active: Registry.isActive(ext), handlerName: handler.map(Registry.appName))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files with these extensions show the Open With menu when you open them.")
                .foregroundStyle(.secondary)

            List {
                if model.rows.isEmpty {
                    Text("No extensions yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rows) { row in
                    HStack(spacing: 10) {
                        Text(".\(row.ext)")
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 70, alignment: .leading)
                        if row.active {
                            Label("Popup", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Opens in \(row.handlerName ?? "no app")", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("Another app became the default for this extension.")
                            Button("Re-enable") { model.reenable(row.ext) }
                                .controlSize(.small)
                        }
                        Spacer()
                        Button {
                            model.remove(row.ext)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove .\(row.ext) and give it back to its previous app")
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)

            HStack {
                TextField("Add extensions, e.g. md, txt, json", text: $model.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.add() }
                Button("Add") { model.add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Registry.parse(model.input).isEmpty)
            }

            HStack(alignment: .top) {
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Refresh") { model.reload() }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(minWidth: 440, minHeight: 340)
    }
}

final class SettingsWindowController: NSWindowController {
    let model = SettingsModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Open With Popup Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        self.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    func show() {
        model.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
