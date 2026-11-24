// Small helpers for text and headers in menus.

import AppKit

enum MenuText {
    /// A section header (macOS 14+ style), or a disabled item on older systems.
    static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// File names can be very long or contain line breaks and control characters;
    /// keep them to one tidy line for menus and panels.
    static func safeFileName(_ name: String) -> String {
        let oneLine = String(name.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        guard oneLine.count > 60 else { return oneLine }
        return oneLine.prefix(40) + "…" + oneLine.suffix(17)
    }
}
