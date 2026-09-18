import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        guard let imageURL = notificationImageURL(from: request.content.userInfo) else {
            contentHandler(content)
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        let session = URLSession(configuration: configuration)

        downloadTask = session.downloadTask(with: imageURL) { [weak self] temporaryURL, response, error in
            guard let self = self else { return }
            defer { session.finishTasksAndInvalidate() }

            if error == nil,
               let temporaryURL = temporaryURL,
               let attachmentURL = self.persistDownloadedImage(
                    temporaryURL,
                    response: response,
                    sourceURL: imageURL
               ),
               let attachment = try? UNNotificationAttachment(
                    identifier: "mundicam-image",
                    url: attachmentURL,
                    options: nil
               ) {
                content.attachments = [attachment]
            }

            self.finish(with: content)
        }
        downloadTask?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()
        if let content = bestAttemptContent {
            finish(with: content)
        }
    }

    private func finish(with content: UNNotificationContent) {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(content)
    }

    private func notificationImageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let directKeys = [
            "notification_image_url",
            "image_url",
            "imageUrl",
            "image",
            "gcm.notification.image"
        ]

        for key in directKeys {
            if let raw = userInfo[key] as? String,
               let url = validatedRemoteURL(raw) {
                return url
            }
        }

        if let fcmOptions = userInfo["fcm_options"] as? [String: Any],
           let raw = fcmOptions["image"] as? String,
           let url = validatedRemoteURL(raw) {
            return url
        }

        if let fcmOptions = userInfo["fcm_options"] as? [AnyHashable: Any],
           let raw = fcmOptions["image"] as? String,
           let url = validatedRemoteURL(raw) {
            return url
        }

        return nil
    }

    private func validatedRemoteURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private func persistDownloadedImage(
        _ temporaryURL: URL,
        response: URLResponse?,
        sourceURL: URL
    ) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("MundiCamPush", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return nil
        }

        let preferredExtension = sanitizedExtension(
            from: response?.suggestedFilename,
            sourceURL: sourceURL
        )
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func sanitizedExtension(from suggestedFilename: String?, sourceURL: URL) -> String {
        let allowed = Set(["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"])

        if let suggestedFilename = suggestedFilename {
            let ext = (suggestedFilename as NSString).pathExtension.lowercased()
            if allowed.contains(ext) { return ext }
        }

        let sourceExtension = sourceURL.pathExtension.lowercased()
        if allowed.contains(sourceExtension) { return sourceExtension }

        return "jpg"
    }
}
