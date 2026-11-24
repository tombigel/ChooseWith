// Which extensions use the popup, and switching their default app in LaunchServices.

import AppKit
import UniformTypeIdentifiers

let selfBundleID = Bundle.main.bundleIdentifier ?? "com.tombigel.OpenWithPopup"

enum Registry {
    private static let defaults = UserDefaults.standard
    private static let trackedKey = "extensions"

    static func normalize(_ ext: String) -> String {
        ext.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n*")).lowercased()
    }

    /// Splits user input like "md, .txt json" into extensions.
    static func parse(_ input: String) -> [String] {
        input.components(separatedBy: CharacterSet(charactersIn: ", \t\n;"))
            .map(normalize).filter { !$0.isEmpty }
    }

    static func utType(forExtension ext: String) -> UTType? {
        let e = normalize(ext)
        return e.isEmpty ? nil : UTType(filenameExtension: e)
    }

    /// Extensions managed by this app (added in Settings or with --register).
    static var tracked: [String] {
        get {
            var set = Set(defaults.stringArray(forKey: trackedKey) ?? [])
            // Pick up anything registered before the list existed.
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("previous.") {
                set.insert(String(key.dropFirst("previous.".count)))
            }
            return set.sorted()
        }
        set { defaults.set(Array(Set(newValue.map(normalize))).sorted(), forKey: trackedKey) }
    }

    static func currentHandler(forExtension ext: String) -> String? {
        guard let type = utType(forExtension: ext) else { return nil }
        return LSCopyDefaultRoleHandlerForContentType(type.identifier as CFString, .all)?.takeRetainedValue() as String?
    }

    static func isActive(_ ext: String) -> Bool {
        currentHandler(forExtension: ext)?.caseInsensitiveCompare(selfBundleID) == .orderedSame
    }

    static func previousHandler(forExtension ext: String) -> String? {
        defaults.string(forKey: "previous." + normalize(ext))
    }

    static func appName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Sets the default app for an extension. Returns an error message, or nil on success.
    /// Uses NSWorkspace, which macOS honors (the older LSSetDefaultRoleHandler call is
    /// silently ignored on current macOS). macOS may ask the user to confirm.
    static func setDefault(bundleID: String, forExtension ext: String) -> String? {
        guard let type = utType(forExtension: ext) else { return ".\(ext): not a valid extension" }
        let appURL = bundleID.caseInsensitiveCompare(selfBundleID) == .orderedSame
            ? Bundle.main.bundleURL
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let appURL else { return ".\(ext): app \(bundleID) not found" }

        var done = false
        var failure: Error?
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
            DispatchQueue.main.async { failure = error; done = true }
        }
        // Wait for the result (and any confirmation prompt) without blocking the run loop.
        let deadline = Date().addingTimeInterval(120)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if !done { return ".\(ext): timed out waiting for macOS" }
        if let failure { return ".\(ext): \(failure.localizedDescription)" }
        return nil
    }

    /// Makes the popup the default for an extension and remembers the old default.
    static func register(_ raw: String) -> String? {
        let ext = normalize(raw)
        if let prev = currentHandler(forExtension: ext),
           prev.caseInsensitiveCompare(selfBundleID) != .orderedSame {
            defaults.set(prev, forKey: "previous." + ext)
        }
        if let err = setDefault(bundleID: selfBundleID, forExtension: ext) { return err }
        tracked = tracked + [ext]
        return nil
    }

    /// Gives an extension back to its previous default (or the first other app that
    /// can open it) and stops tracking it. Returns an error message, or nil on success.
    static func unregister(_ raw: String) -> String? {
        let ext = normalize(raw)
        if isActive(ext) {
            guard let target = previousHandler(forExtension: ext) ?? firstOtherApp(forExtension: ext) else {
                return ".\(ext): no other app can open it, so it was left on the popup"
            }
            if let err = setDefault(bundleID: target, forExtension: ext) { return err }
        }
        defaults.removeObject(forKey: "previous." + ext)
        tracked = tracked.filter { $0 != ext }
        return nil
    }

    private static func firstOtherApp(forExtension ext: String) -> String? {
        guard let type = utType(forExtension: ext) else { return nil }
        return NSWorkspace.shared.urlsForApplications(toOpen: type)
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
            .first { $0.caseInsensitiveCompare(selfBundleID) != .orderedSame }
    }
}
