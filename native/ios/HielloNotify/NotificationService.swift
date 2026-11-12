import UserNotifications
import UIKit
import ImageIO
import UniformTypeIdentifiers

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
                // A Flip arrives as one wide picture with its frames side by side: turn it into a little looping GIF
                if let gif = NotificationService.flipGIF(from: file) {
                    let pic = try UNNotificationAttachment(identifier: "flip", url: gif,
                                                           options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.gif.identifier])
                    content.attachments = [pic]
                } else {
                    let pic = try UNNotificationAttachment(identifier: "photo", url: file, options: nil)
                    content.attachments = [pic]
                }
            } catch {}
        }
        task.resume()
    }

    /// iOS is about to give up waiting: show the words without the picture rather than nothing.
    override func serviceExtensionTimeWillExpire() {
        if let h = contentHandler, let c = best { h(c) }
    }

    /// Cuts a wide Flip picture into its frames and saves them as a looping GIF (nil if it isn't a Flip).
    static func flipGIF(from file: URL) -> URL? {
        guard let img = UIImage(contentsOfFile: file.path), let cg = img.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard h > 0 else { return nil }
        let n = Int((w / h).rounded())
        guard n >= 2, n <= 7 else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, n, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 0.45]] as CFDictionary
        let fw = w / CGFloat(n)
        for i in 0..<n {
            if let c = cg.cropping(to: CGRect(x: (CGFloat(i) * fw).rounded(), y: 0, width: fw.rounded(.down), height: h)) {
                CGImageDestinationAddImage(dest, c, frameProps)
            }
        }
        return CGImageDestinationFinalize(dest) ? out : nil
    }
}
