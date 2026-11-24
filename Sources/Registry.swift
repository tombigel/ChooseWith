// Which extensions use the popup, and switching their default app in LaunchServices.

import AppKit
import UniformTypeIdentifiers

let selfBundleID = Bundle.main.bundleIdentifier ?? "com.tombigel.ChooseWith"

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
        return validationError(e) == nil ? UTType(filenameExtension: e) : nil
    }

    private static let allowedChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_+")

    /// Types that must never be taken over: opening apps, folders, disks or links
    /// would break (or hijack) basic Finder behavior.
    private static let blockedTypes: [UTType] = [
        .application, .applicationBundle, .executable, .folder, .directory, .volume,
        .aliasFile, .symbolicLink, .resolvable,
    ]

    /// Why an extension can't be used, or nil if it's fine.
    static func validationError(_ raw: String) -> String? {
        let ext = normalize(raw)
        guard !ext.isEmpty, ext.count <= 32,
              ext.unicodeScalars.allSatisfy(allowedChars.contains) else {
            return "“\(raw)” isn’t a valid extension (up to 32 letters, digits, - _ +)"
        }
        if let type = UTType(filenameExtension: ext), blockedTypes.contains(where: type.conforms(to:)) {
            return ".\(ext) opens apps, folders or links, so it can’t be used"
        }
        return nil
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
    private static var changing = false

    static func setDefault(bundleID: String, forExtension ext: String) -> String? {
        if let err = validationError(ext) { return err }
        guard let type = utType(forExtension: ext) else { return ".\(ext): not a valid extension" }
        // The wait below keeps the run loop going, so guard against a second
        // change starting (e.g. a double click) before macOS has answered.
        guard !changing else { return ".\(ext): another change is still in progress" }
        changing = true
        defer { changing = false }
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
        if let err = validationError(raw) { return err }
        let ext = normalize(raw)
        // Remember the app to hand the extension back to on removal. If it's already
        // managed (Take Back after a takeover), keep the original: the current
        // handler is just the app that grabbed it.
        let alreadyManaged = tracked.contains(ext) && previousHandler(forExtension: ext) != nil
        if !alreadyManaged, let prev = currentHandler(forExtension: ext),
           prev.caseInsensitiveCompare(selfBundleID) != .orderedSame {
            defaults.set(prev, forKey: "previous." + ext)
        }
        if let err = setDefault(bundleID: selfBundleID, forExtension: ext) { return err }
        tracked = tracked + [ext]
        clearNotes(ext)
        return nil
    }

    // MARK: Take-back notes

    /// Shown in Settings: "Taken back from Inkscape".
    static func setTakenBackNote(_ ext: String, from app: String) {
        defaults.set(app, forKey: "takenBackFrom." + normalize(ext))
        defaults.set(Date(), forKey: "takenBackAt." + normalize(ext))
    }

    static func takenBackAt(_ ext: String) -> Date? {
        defaults.object(forKey: "takenBackAt." + normalize(ext)) as? Date
    }

    /// Most recent take-back across all extensions, for the menu bar menu.
    static func lastTakeBack() -> (ext: String, app: String, at: Date)? {
        tracked.compactMap { ext -> (String, String, Date)? in
            guard let app = takenBackFrom(ext), let at = takenBackAt(ext) else { return nil }
            return (ext, app, at)
        }.max { $0.2 < $1.2 }
    }

    static func takenBackFrom(_ ext: String) -> String? {
        defaults.string(forKey: "takenBackFrom." + normalize(ext))
    }

    /// An app kept re-claiming this extension, so Choose With stopped taking it back.
    static func setGaveUp(_ ext: String, takerName: String) {
        defaults.set(takerName, forKey: "gaveUpTo." + normalize(ext))
    }

    static func gaveUp(_ ext: String) -> Bool { gaveUpTo(ext) != nil }

    static func gaveUpTo(_ ext: String) -> String? {
        defaults.string(forKey: "gaveUpTo." + normalize(ext))
    }

    /// The user chose "Leave It" for this app; don't ask again unless another app takes over.
    static func setLeftTo(_ ext: String, app: String) {
        defaults.set(app, forKey: "leftTo." + normalize(ext))
    }

    static func leftTo(_ ext: String) -> String? {
        defaults.string(forKey: "leftTo." + normalize(ext))
    }

    private static func clearNotes(_ ext: String) {
        for key in ["takenBackFrom.", "takenBackAt.", "gaveUpTo.", "leftTo."] {
            defaults.removeObject(forKey: key + normalize(ext))
        }
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
        clearNotes(ext)
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
