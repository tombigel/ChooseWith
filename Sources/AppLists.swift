// Per-extension app lists: which apps can open an extension, the order the user set,
// and which apps they hid. Also crisp menu-sized app icons.

import AppKit
import UniformTypeIdentifiers

enum AppLists {
    private static let defaults = UserDefaults.standard

    /// Stable key for an app: its bundle ID, or its path if it has none.
    static func key(_ app: URL) -> String {
        Bundle(url: app)?.bundleIdentifier ?? app.path
    }

    static func name(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Apps that can open files with this extension, in LaunchServices order,
    /// without duplicates and without Choose With itself.
    static func apps(forExtension ext: String) -> [URL] {
        guard let type = Registry.utType(forExtension: ext) else { return [] }
        return unique(NSWorkspace.shared.urlsForApplications(toOpen: type))
    }

    static func unique(_ apps: [URL]) -> [URL] {
        var seen = Set<String>()
        return apps.filter { app in
            let id = key(app)
            guard id.caseInsensitiveCompare(selfBundleID) != .orderedSame, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    // MARK: Saved customization

    private static func orderKey(_ ext: String) -> String { "order." + Registry.normalize(ext) }
    private static func hiddenKey(_ ext: String) -> String { "hidden." + Registry.normalize(ext) }

    static func isCustomized(_ ext: String) -> Bool {
        defaults.object(forKey: orderKey(ext)) != nil || defaults.object(forKey: hiddenKey(ext)) != nil
    }

    static func hidden(_ ext: String) -> Set<String> {
        Set(defaults.stringArray(forKey: hiddenKey(ext)) ?? [])
    }

    static func save(_ ext: String, order: [String], hidden: Set<String>) {
        defaults.set(order, forKey: orderKey(ext))
        defaults.set(Array(hidden).sorted(), forKey: hiddenKey(ext))
    }

    static func reset(_ ext: String) {
        defaults.removeObject(forKey: orderKey(ext))
        defaults.removeObject(forKey: hiddenKey(ext))
    }

    /// Puts apps in the saved order. Apps installed since then go at the end, shown.
    static func ordered(_ apps: [URL], ext: String) -> [URL] {
        guard let order = defaults.stringArray(forKey: orderKey(ext)) else { return apps }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return apps.enumerated().sorted { a, b in
            let ra = rank[key(a.element)] ?? Int.max, rb = rank[key(b.element)] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Splits apps into the ones shown in the menu and the hidden ones, both in order.
    static func arrange(_ apps: [URL], ext: String) -> (shown: [URL], hidden: [URL]) {
        let all = ordered(apps, ext: ext)
        let hiddenIDs = hidden(ext)
        return (all.filter { !hiddenIDs.contains(key($0)) }, all.filter { hiddenIDs.contains(key($0)) })
    }

    // MARK: Icons

    private static var iconCache: [String: NSImage] = [:]

    static func clearIconCache() { iconCache.removeAll() }

    /// The app's icon drawn into its own 16 pt image (32 px for Retina), so menus
    /// show it reliably instead of resizing the shared icon.
    static func icon(_ app: URL, size: CGFloat = 16) -> NSImage {
        let cacheKey = "\(app.path)@\(size)"
        if let cached = iconCache[cacheKey] { return cached }
        let source = NSWorkspace.shared.icon(forFile: app.path)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        iconCache[cacheKey] = image
        return image
    }
}
