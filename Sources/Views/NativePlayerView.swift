import SwiftUI
import AVKit

public struct NativePlayerView: UIViewControllerRepresentable {
    public let videoURL: URL
    public let title: String
    
    public init(videoURL: URL, title: String) {
        self.videoURL = videoURL
        self.title = title
    }
    
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: videoURL)
        controller.player = player
        controller.showsPlaybackControls = true
        
        let metadataItem = AVMutableMetadataItem()
        metadataItem.identifier = .commonIdentifierTitle
        metadataItem.value = title as NSString
        player.currentItem?.externalMetadata = [metadataItem]
        
        player.play()
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
