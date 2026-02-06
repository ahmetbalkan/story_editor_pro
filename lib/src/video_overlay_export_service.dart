import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Native video overlay export service.
/// Composites a transparent PNG overlay onto a video using native APIs.
///
/// iOS: AVMutableComposition + AVVideoCompositionCoreAnimationTool
/// Android: MediaCodec + Surface + Canvas
class VideoOverlayExportService {
  static const MethodChannel _channel = MethodChannel('story_editor_pro');

  /// Export video with overlay PNG baked in.
  ///
  /// [videoPath]: Original video file path
  /// [overlayPngBytes]: PNG image bytes (transparent background, only overlays)
  /// Returns: Path to the exported MP4 file, or null on failure
  static Future<String?> exportVideoWithOverlay({
    required String videoPath,
    required Uint8List overlayPngBytes,
  }) async {
    try {
      final sw = Stopwatch()..start();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final overlayPath = '${tempDir.path}/overlay_$timestamp.png';
      final outputPath = '${tempDir.path}/story_video_$timestamp.mp4';

      final overlayFile = File(overlayPath);
      await overlayFile.writeAsBytes(overlayPngBytes);
      debugPrint('VideoOverlayProcessor: Overlay PNG written in ${sw.elapsedMilliseconds}ms (${(overlayPngBytes.length / 1024).toStringAsFixed(0)}KB)');

      debugPrint('VideoOverlayProcessor: Starting native export...');
      debugPrint('  Video: $videoPath');
      debugPrint('  Output: $outputPath');

      final result = await _channel.invokeMethod<String>(
        'exportVideoWithOverlay',
        {
          'videoPath': videoPath,
          'overlayImagePath': overlayPath,
          'outputPath': outputPath,
        },
      );

      // Clean up overlay temp file
      try {
        await overlayFile.delete();
      } catch (_) {}

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint('VideoOverlayProcessor: Success! '
              'Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
          return result;
        }
      }

      debugPrint('VideoOverlayProcessor: Export returned null');
      return null;
    } on PlatformException catch (e) {
      debugPrint('VideoOverlayProcessor: Platform error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('VideoOverlayProcessor: Error: $e');
      return null;
    }
  }
}
