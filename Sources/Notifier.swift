// macOS notifications for automatic take-backs. Quiet (no sound), grouped, and
// only after the user turns on "Take extensions back", which is when permission
// is requested.

import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// One notification per check, however many extensions were taken back.
    static func tookBack(_ items: [(ext: String, app: String)]) {
        guard let first = items.first else { return }
        let content = UNMutableNotificationContent()
        if items.count == 1 {
            content.title = "Took back ." + first.ext
            content.body = first.app + " had made itself the default. ." + first.ext + " files show the Choose With menu again."
        } else {
            content.title = "Took back \(items.count) extensions"
            content.body = items.map { "." + $0.ext + " from " + $0.app }.joined(separator: ", ")
        }
        content.threadIdentifier = "take-back"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// "14:02" today, otherwise a short date and time.
    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateStyle = .none
        } else {
            f.dateStyle = .short
        }
        f.timeStyle = .short
        return f.string(from: date)
    }
}
