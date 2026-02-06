import Foundation
import AVFoundation
import UIKit

class VideoOverlayProcessor {

    /// Compose overlay PNG on top of video and export as new MP4
    func exportVideoWithOverlay(
        videoPath: String,
        overlayImagePath: String,
        outputPath: String,
        completion: @escaping (String?) -> Void
    ) {
        let videoURL = URL(fileURLWithPath: videoPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        // Remove existing output
        try? FileManager.default.removeItem(at: outputURL)

        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)

            // 1. Create mutable composition
            let composition = AVMutableComposition()

            // 2. Add video track
            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                print("VideoOverlayProcessor: No video track found")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)

            do {
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            } catch {
                print("VideoOverlayProcessor: Failed to insert video track: \(error)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 3. Add audio track (if exists)
            if let audioTrack = asset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                 withMediaType: .audio,
                 preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }

            // 4. Calculate render size (accounting for video transform/rotation)
            let renderSize = self.calculateRenderSize(track: videoTrack)

            // 5. Create video composition
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.renderSize = renderSize

            // 6. Create layer instruction for proper video orientation
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )
            let transform = videoTrack.preferredTransform
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]

            // 7. Create overlay layer from PNG
            guard let overlayImage = UIImage(contentsOfFile: overlayImagePath) else {
                print("VideoOverlayProcessor: Failed to load overlay image")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let parentLayer = CALayer()
            let videoLayer = CALayer()
            let overlayLayer = CALayer()

            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.masksToBounds = true
            // Flip parent layer so overlay coordinates match Flutter's top-left origin
            parentLayer.isGeometryFlipped = true
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            overlayLayer.contents = overlayImage.cgImage

            // Scale overlay to cover renderSize while preserving aspect ratio (center crop)
            let overlayAspect = overlayImage.size.width / overlayImage.size.height
            let renderAspect = renderSize.width / renderSize.height
            let overlayFrame: CGRect
            if overlayAspect > renderAspect {
                // Overlay is wider: match height, crop width
                let scaledWidth = renderSize.height * overlayAspect
                let offsetX = (renderSize.width - scaledWidth) / 2
                overlayFrame = CGRect(x: offsetX, y: 0, width: scaledWidth, height: renderSize.height)
            } else {
                // Overlay is taller: match width, crop height
                let scaledHeight = renderSize.width / overlayAspect
                let offsetY = (renderSize.height - scaledHeight) / 2
                overlayFrame = CGRect(x: 0, y: offsetY, width: renderSize.width, height: scaledHeight)
            }
            overlayLayer.frame = overlayFrame
            overlayLayer.contentsGravity = .resize

            parentLayer.addSublayer(videoLayer)
            parentLayer.addSublayer(overlayLayer)

            // 8. Apply animation tool
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )

            // 9. Export
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                print("VideoOverlayProcessor: Failed to create export session")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            exporter.videoComposition = videoComposition
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true

            exporter.exportAsynchronously {
                DispatchQueue.main.async {
                    if exporter.status == .completed {
                        print("VideoOverlayProcessor: Export completed successfully")
                        completion(outputPath)
                    } else {
                        print("VideoOverlayProcessor: Export failed: \(exporter.error?.localizedDescription ?? "unknown")")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Calculate proper render size from video track (handles rotation)
    private func calculateRenderSize(track: AVAssetTrack) -> CGSize {
        let transform = track.preferredTransform
        let size = track.naturalSize

        // Determine rotation angle from the transform matrix
        let angle = atan2(transform.b, transform.a)
        let degrees = abs(angle * 180.0 / .pi)

        // If video is rotated 90 or 270 degrees, swap width/height
        if abs(degrees - 90) < 1 || abs(degrees - 270) < 1 {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }
}
