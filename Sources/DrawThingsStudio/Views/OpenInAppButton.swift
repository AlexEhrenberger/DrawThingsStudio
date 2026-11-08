import AppKit
import SwiftUI

/// Externe Programme fürs Weiterarbeiten: Bilder in Pixelmator Pro, Videos in QuickTime Player.
enum ExternalApp {
    static let pixelmatorID = "com.pixelmatorteam.pixelmator.x"
    static let quickTimeID = "com.apple.QuickTimePlayerX"

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isVideo(_ url: URL) -> Bool {
        GalleryMedia.videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Öffnet Bilder in Pixelmator Pro und Videos in QuickTime Player.
    static func open(_ urls: [URL]) {
        let videos = urls.filter(isVideo)
        let images = urls.filter { !isVideo($0) }
        open(images, with: pixelmatorID)
        open(videos, with: quickTimeID)
    }

    private static func open(_ urls: [URL], with bundleID: String) {
        guard !urls.isEmpty, let app = url(for: bundleID) else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Kontextmenü-Eintrag „In Pixelmator Pro öffnen“ bzw. „In QuickTime öffnen“ – je nach Medium.
struct OpenInAppButton: View {
    let urls: [URL]

    var body: some View {
        let hasVideo = urls.contains(where: ExternalApp.isVideo)
        let hasImage = urls.contains { !ExternalApp.isVideo($0) }
        if hasImage || hasVideo {
            Button(title(image: hasImage, video: hasVideo), systemImage: hasVideo && !hasImage ? "play.rectangle" : "paintbrush") {
                ExternalApp.open(urls)
            }
            .disabled(!available(image: hasImage, video: hasVideo))
        }
    }

    private func title(image: Bool, video: Bool) -> String {
        switch (image, video) {
        case (true, true): "In Pixelmator Pro / QuickTime öffnen"
        case (false, true): "In QuickTime öffnen"
        default: "In Pixelmator Pro öffnen"
        }
    }

    private func available(image: Bool, video: Bool) -> Bool {
        (!image || ExternalApp.url(for: ExternalApp.pixelmatorID) != nil)
            && (!video || ExternalApp.url(for: ExternalApp.quickTimeID) != nil)
    }
}
