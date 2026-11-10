import UserNotifications

/// Puts the family's photo right inside the notification (lock screen, banner, and when you press on it).
/// The server sends a one-day link to the small picture in "image"; this downloads it before the alert shows.
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var best: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        best = content
        guard let s = request.content.userInfo["image"] as? String, let url = URL(string: s) else {
            contentHandler(content); return
        }
        let task = URLSession.shared.downloadTask(with: url) { tmp, _, _ in
            defer { contentHandler(content) }
            guard let tmp = tmp else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try FileManager.default.moveItem(at: tmp, to: file)
                let pic = try UNNotificationAttachment(identifier: "photo", url: file, options: nil)
                content.attachments = [pic]
            } catch {}
        }
        task.resume()
    }

    /// iOS is about to give up waiting: show the words without the picture rather than nothing.
    override func serviceExtensionTimeWillExpire() {
        if let h = contentHandler, let c = best { h(c) }
    }
}
