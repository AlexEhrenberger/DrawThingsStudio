import AVKit
import SwiftUI

/// Video abspielen – mit den Bedienelementen von macOS (schwebende Leiste, Vollbild, Bild-in-Bild).
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    var autoplay = true

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        if autoplay { view.player?.play() }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard (view.player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
        if autoplay { view.player?.play() }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
