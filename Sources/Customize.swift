// Customize sheet: reorder the apps for one extension and choose which ones the
// menu shows. Unticked apps move into the menu's "More Apps" submenu.

import AppKit
import SwiftUI

struct CustomizeTarget: Identifiable {
    let ext: String
    var id: String { ext }
}

final class CustomizeModel: ObservableObject {
    struct Item: Identifiable {
        let id: String          // bundle ID or path
        let url: URL
        let name: String
        let icon: NSImage
        var shown: Bool
    }

    let ext: String
    @Published var items: [Item] = []

    init(ext: String) {
        self.ext = ext
        load()
        // Re-sync when the user comes back from installing or deleting apps.
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
    }

    private var observer: NSObjectProtocol?

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Brings the list up to date with the apps installed right now, keeping the
    /// user's unsaved order and ticks: removed apps drop out, new apps are added at
    /// the end (shown).
    func sync() {
        AppLists.clearIconCache()
        let installed = AppLists.apps(forExtension: ext)
        let installedIDs = Set(installed.map(AppLists.key))
        var kept = items.filter { installedIDs.contains($0.id) }
        let keptIDs = Set(kept.map(\.id))
        let hidden = AppLists.hidden(ext)
        kept += installed.filter { !keptIDs.contains(AppLists.key($0)) }.map(makeItem(hidden))
        // Refresh paths, names and icons (an app may have moved or been updated).
        let byID = Dictionary(installed.map { (AppLists.key($0), $0) }, uniquingKeysWith: { a, _ in a })
        items = kept.map { item in
            guard let url = byID[item.id] else { return item }
            var fresh = makeItem([])(url)
            fresh.shown = item.shown
            return fresh
        }
    }

    /// Current state: the saved order and hidden apps, or LaunchServices order with all shown.
    func load() {
        AppLists.clearIconCache()
        let hidden = AppLists.hidden(ext)
        items = AppLists.ordered(AppLists.apps(forExtension: ext), ext: ext).map(makeItem(hidden))
    }

    /// The default: LaunchServices order, everything shown.
    func resetToDefault() {
        items = AppLists.apps(forExtension: ext).map(makeItem([]))
    }

    private func makeItem(_ hidden: Set<String>) -> (URL) -> Item {
        { url in
            let id = AppLists.key(url)
            return Item(id: id, url: url, name: AppLists.name(url), icon: AppLists.icon(url, size: 20), shown: !hidden.contains(id))
        }
    }

    enum Move { case top, up, down, bottom }

    func move(_ id: String, _ where: Move) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let target: Int
        switch `where` {
        case .top: target = 0
        case .up: target = max(i - 1, 0)
        case .down: target = min(i + 1, items.count - 1)
        case .bottom: target = items.count - 1
        }
        guard target != i else { return }
        items.insert(items.remove(at: i), at: target)
    }

    func setAll(shown: Bool) {
        for i in items.indices { items[i].shown = shown }
    }

    var shownCount: Int { items.filter(\.shown).count }

    /// Menu key (1–9) for a shown app, by its position among shown apps.
    func shortcut(for item: Item) -> String? {
        guard item.shown, let pos = items.filter(\.shown).firstIndex(where: { $0.id == item.id }), pos < 9 else { return nil }
        return String(pos + 1)
    }

    func save() {
        let isDefault = items.allSatisfy(\.shown)
            && items.map(\.id) == AppLists.apps(forExtension: ext).map(AppLists.key)
        if isDefault {
            AppLists.reset(ext)   // back to default: "last used first" applies again
        } else {
            AppLists.save(ext, order: items.map(\.id), hidden: Set(items.filter { !$0.shown }.map(\.id)))
        }
    }
}

struct CustomizeView: View {
    @StateObject var model: CustomizeModel
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Apps for ." + model.ext).font(.headline)
            Text("Drag apps to reorder them, or right-click for Move options. Untick apps you don’t need; they move to **More Apps** at the bottom of the menu.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($model.items) { $item in
                    CustomizeRow(item: $item, shortcut: model.shortcut(for: item), model: model)
                }
                .onMove { model.items.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 340)
            .accessibilityLabel(Text(verbatim: "Apps for ." + model.ext))

            Text(verbatim: "\(model.shownCount) of \(model.items.count) apps in the menu. Your order replaces “last used first” for .\(model.ext).")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Button("Show All") { model.setAll(shown: true) }
                Button("Hide All") { model.setAll(shown: false) }
                Button("Reset") { model.resetToDefault() }
                    .help("Back to the default: every app shown, in the system’s order")
                Spacer()
                Button("Cancel") { done() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { model.save(); done() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: WindowSize.sheetWidth)
    }
}

/// One app in the Customize list. Dragging works anywhere on the row; the handle is
/// a hint that lights up (with a grab cursor) on hover. Moving also works from the
/// right-click menu and as VoiceOver actions, so it never depends on dragging.
private struct CustomizeRow: View {
    @Binding var item: CustomizeModel.Item
    let shortcut: String?
    let model: CustomizeModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(hovering ? .secondary : .tertiary)
                .accessibilityHidden(true)
            // The label is the app name, so VoiceOver reads "Sublime Text, checkbox".
            Toggle(isOn: $item.shown) { Text(verbatim: item.name) }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(item.shown ? "Shown in the menu" : "Under More Apps")
            Image(nsImage: item.icon)
                .resizable().frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(verbatim: item.name)
                .foregroundStyle(item.shown ? .primary : .secondary)
                .help(item.url.path)
                .accessibilityHidden(true)
            Spacer()
            if let shortcut {
                Text(verbatim: shortcut)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
                    .help(Text(verbatim: "Press \(shortcut) in the menu to pick this app"))
                    .accessibilityLabel(Text(verbatim: "Shortcut \(shortcut)"))
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
        .contextMenu {
            Button("Move to Top") { model.move(item.id, .top) }
            Button("Move Up") { model.move(item.id, .up) }
            Button("Move Down") { model.move(item.id, .down) }
            Button("Move to Bottom") { model.move(item.id, .bottom) }
        }
        .accessibilityAction(named: Text("Move Up")) { model.move(item.id, .up) }
        .accessibilityAction(named: Text("Move Down")) { model.move(item.id, .down) }
        .accessibilityAction(named: Text("Move to Top")) { model.move(item.id, .top) }
        .accessibilityAction(named: Text("Move to Bottom")) { model.move(item.id, .bottom) }
    }
}
