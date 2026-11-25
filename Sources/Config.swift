// Export / Import: Choose With's setup as a readable JSON file, to move between
// Macs, keep with dotfiles or put in iCloud Drive.
//
// Included: extensions, each extension's app order and hidden apps, and the
// portable settings. Left out (per-Mac state): Start at login, which app each
// extension goes back to on removal, and take-back history.
//
// An imported file is untrusted input: it's size-limited, decoded as plain JSON,
// and every extension and app ID is validated. Nothing in it is ever run.

import Foundation
import SystemConfiguration

struct ChooseWithConfig: Codable, Equatable {
    struct Apps: Codable, Equatable {
        var order: [String]?
        var hidden: [String]?
    }

    /// Where and when the file was exported. Shown before importing; never applied.
    struct Info: Codable, Equatable {
        var exportedAt: String?
        var computer: String?
        var appVersion: String?
    }

    static let currentVersion = 1

    var version: Int
    var info: Info?
    var extensions: [String]
    var apps: [String: Apps]?
    var takeBack: Bool?
    var menuBarIcon: Bool?
    var splash: Bool?
    var helpOnLaunch: Bool?
}

enum ConfigError: LocalizedError {
    case tooLarge, notJSON(String), newerVersion(Int), invalid(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "The file is too large to be a Choose With settings file."
        case .notJSON(let why): return "The file isn’t valid Choose With settings: \(why)"
        case .newerVersion(let v): return "The file is from a newer Choose With (format \(v)). Update Choose With to import it."
        case .invalid(let why): return "The file has a problem: \(why)"
        }
    }
}

enum ConfigIO {
    private static let maxBytes = 1_000_000
    private static let maxExtensions = 500
    private static let maxAppsPerExtension = 1_000
    private static let maxIDLength = 1_024

    // MARK: Export

    static func current() -> ChooseWithConfig {
        var apps: [String: ChooseWithConfig.Apps] = [:]
        for ext in Registry.tracked where AppLists.isCustomized(ext) {
            let order = UserDefaults.standard.stringArray(forKey: "order." + ext)
            let hidden = AppLists.hidden(ext).sorted()
            apps[ext] = .init(order: order, hidden: hidden.isEmpty ? nil : hidden)
        }
        return ChooseWithConfig(
            version: ChooseWithConfig.currentVersion,
            info: nil,
            extensions: Registry.tracked,
            apps: apps.isEmpty ? nil : apps,
            takeBack: Prefs.takeBackExtensions,
            menuBarIcon: Prefs.showMenuBarIcon,
            splash: Prefs.showSplash,
            helpOnLaunch: Prefs.showHelpOnLaunch)
    }

    static func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var config = current()
        config.info = .init(
            exportedAt: ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]),
            computer: computerName(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        return try encoder.encode(config)
    }

    /// The Mac's name as set in System Settings › General › Sharing.
    static func computerName() -> String? {
        let name = SCDynamicStoreCopyComputerName(nil, nil) as String?
        return name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// "Choose With Settings - Tom’s MacBook Pro - 2026-11-25.json"
    static func suggestedFileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        var parts = ["Choose With Settings"]
        if let name = computerName() {
            // Keep it a valid, tidy file name: no path separators or control characters.
            let bad = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
            let clean = String(String.UnicodeScalarView(name.unicodeScalars.filter { !bad.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { parts.append(String(clean.prefix(60))) }
        }
        parts.append(f.string(from: date))
        return parts.joined(separator: " - ") + ".json"
    }

    // MARK: Import

    /// Reads a settings file safely: regular files only (never a pipe, device or
    /// folder, so it can't block or stream forever), size checked before reading,
    /// and never more than the limit read into memory.
    static func read(_ url: URL) throws -> Data {
        let file = url.resolvingSymlinksInPath()
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ConfigError.invalid("it isn’t a regular file") }
        guard (values.fileSize ?? 0) <= maxBytes else { throw ConfigError.tooLarge }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw ConfigError.tooLarge }
        return data
    }

    /// Decodes and validates a settings file. Extensions are normalized; app IDs
    /// for extensions not in the list are dropped.
    static func load(_ data: Data) throws -> ChooseWithConfig {
        guard data.count <= maxBytes else { throw ConfigError.tooLarge }
        var config: ChooseWithConfig
        do {
            config = try JSONDecoder().decode(ChooseWithConfig.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ConfigError.notJSON("missing “\(key.stringValue)”")
        } catch let DecodingError.typeMismatch(_, context) {
            throw ConfigError.notJSON("wrong type at “\(context.codingPath.map(\.stringValue).joined(separator: "."))”")
        } catch {
            throw ConfigError.notJSON("it isn’t readable JSON")
        }
        guard config.version >= 1 else { throw ConfigError.invalid("unknown format version \(config.version)") }
        guard config.version <= ChooseWithConfig.currentVersion else { throw ConfigError.newerVersion(config.version) }
        guard config.extensions.count <= maxExtensions else { throw ConfigError.invalid("too many extensions") }

        var exts: [String] = []
        for raw in config.extensions {
            if let err = Registry.validationError(raw) { throw ConfigError.invalid(err) }
            let ext = Registry.normalize(raw)
            if !exts.contains(ext) { exts.append(ext) }
        }
        config.extensions = exts

        var apps: [String: ChooseWithConfig.Apps] = [:]
        for (raw, entry) in config.apps ?? [:] {
            if let err = Registry.validationError(raw) { throw ConfigError.invalid(err) }
            let ext = Registry.normalize(raw)
            guard exts.contains(ext) else { continue }   // settings for an extension not in the list
            let order = try validIDs(entry.order, ext)
            let hidden = try validIDs(entry.hidden, ext)
            apps[ext] = .init(order: order, hidden: hidden)
        }
        config.apps = apps.isEmpty ? nil : apps
        // Info is only ever displayed: keep short, plain values and drop anything else.
        func plain(_ v: String?) -> String? {
            guard let v, !v.isEmpty, v.count <= 200,
                  !v.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            return v
        }
        if let info = config.info {
            let clean = ChooseWithConfig.Info(exportedAt: plain(info.exportedAt), computer: plain(info.computer), appVersion: plain(info.appVersion))
            config.info = (clean.exportedAt ?? clean.computer ?? clean.appVersion) == nil ? nil : clean
        }
        return config
    }

    /// App IDs are only ever stored and compared, never run, but keep them sane.
    private static func validIDs(_ ids: [String]?, _ ext: String) throws -> [String]? {
        guard let ids else { return nil }
        guard ids.count <= maxAppsPerExtension else { throw ConfigError.invalid("too many apps for .\(ext)") }
        for id in ids {
            guard !id.isEmpty, id.count <= maxIDLength,
                  !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ConfigError.invalid("a bad app ID for .\(ext)")
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// "Exported from Tom’s MacBook Pro on 25 Nov 2026 at 14:02", or nil.
    static func origin(_ config: ChooseWithConfig) -> String? {
        guard let info = config.info else { return nil }
        var text = "Exported"
        if let c = info.computer { text += " from " + c }
        if let s = info.exportedAt, let d = ISO8601DateFormatter().date(from: s) {
            text += " on " + d.formatted(date: .abbreviated, time: .shortened)
        }
        return text == "Exported" ? nil : text
    }

    // MARK: Changes

    /// What importing `config` would change on this Mac, as readable lines.
    static func changes(_ config: ChooseWithConfig) -> [String] {
        let now = current()
        var lines: [String] = []
        let added = config.extensions.filter { !now.extensions.contains($0) }
        let removed = now.extensions.filter { !config.extensions.contains($0) }
        if !added.isEmpty { lines.append("Add " + added.map { "." + $0 }.joined(separator: ", ")) }
        if !removed.isEmpty { lines.append("Remove " + removed.map { "." + $0 }.joined(separator: ", ") + " (back to their previous apps)") }
        let appChanges = config.extensions.filter { (config.apps?[$0]) != (now.apps?[$0]) }
        if !appChanges.isEmpty { lines.append("Change the app list for " + appChanges.map { "." + $0 }.joined(separator: ", ")) }
        func setting(_ name: String, _ new: Bool?, _ old: Bool?) {
            if let new, new != old { lines.append(name + (new ? " on" : " off")) }
        }
        setting("Turn take back", config.takeBack, now.takeBack)
        setting("Turn the menu bar icon", config.menuBarIcon, now.menuBarIcon)
        setting("Turn the splash screen", config.splash, now.splash)
        setting("Turn Help when opening", config.helpOnLaunch, now.helpOnLaunch)
        return lines
    }

    // MARK: Apply

    /// Makes this Mac's setup match `config`. Returns error messages, if any.
    @discardableResult
    static func apply(_ config: ChooseWithConfig) -> [String] {
        var errors: [String] = []
        for ext in Registry.tracked where !config.extensions.contains(ext) {
            if let err = Registry.unregister(ext) { errors.append(err) }
        }
        for ext in config.extensions where !Registry.tracked.contains(ext) || !Registry.isActive(ext) {
            if let err = Registry.register(ext) { errors.append(err) }
        }
        for ext in config.extensions {
            if let entry = config.apps?[ext] {
                // Order may name apps not installed here; they slot in if installed later.
                AppLists.save(ext, order: entry.order ?? [], hidden: Set(entry.hidden ?? []))
            } else {
                AppLists.reset(ext)
            }
        }
        if let v = config.takeBack { Prefs.takeBackExtensions = v }
        if let v = config.menuBarIcon { Prefs.showMenuBarIcon = v }
        if let v = config.splash { Prefs.showSplash = v }
        if let v = config.helpOnLaunch { Prefs.showHelpOnLaunch = v }
        NotificationCenter.default.post(name: .owpPrefsChanged, object: nil)
        return errors
    }
}
