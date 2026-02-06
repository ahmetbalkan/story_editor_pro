## 1.0.3

### Added
- **Feature toggles** - Camera toolbar features can now be enabled/disabled via `StoryEditorConfig`:
  - `enableBoomerang` - Boomerang mode button
  - `enableCollage` - Collage/layout mode button
  - `enableHandsFree` - Hands-free recording button
  - `enableGradientTextEditor` - Gradient text editor button
  - All default to `true` for backward compatibility

---

## 1.0.2

### Added
- **Native video overlay export** - Video save/share now composites text, drawing, and image overlays directly onto video using native APIs (no FFmpeg dependency)
  - Android: OpenGL/EGL GPU pipeline with `MediaCodec` + `MediaMuxer`
  - iOS: `AVMutableComposition` + `AVVideoCompositionCoreAnimationTool` + `AVAssetExportSession`
- `VideoOverlayExportService` - Flutter-to-native bridge for video overlay compositing
- `TextureRenderer.kt` - Android EGL context and GLSL shader management for GPU-accelerated video processing
- `VideoOverlayProcessor.kt` / `VideoOverlayProcessor.swift` - Native video+overlay compositing pipelines
- Overlay-only `RepaintBoundary` (`_overlayRepaintKey`) for capturing transparent PNG overlays for video export
- Saving/Sharing progress indicator overlay with localized text (`editorSaving` / `editorSharing` strings)
- `_isSharing` flag to distinguish save vs share operations in UI
- Remove background button in text overlay color picker (reset to no background)

### Fixed
- **Text overlays not visible in exported images** - Text overlays are now rendered inside `RepaintBoundary` for correct capture during save/share
- **Drawing overlays rendering order** - Drawings now render on top of text and image overlays consistently
- **Text overlay padding consistency** - Unified padding (`horizontal: 28, vertical: 16`) across editor preview, export, and text input modes
- **Text overlay width calculation** - Consistent `maxWidth` calculation across all rendering contexts
- **Interactive overlays blocked during export** - All gesture layers disabled when `_isSaving = true` to prevent modifications during export
- **Drag-to-trash animation** - Export overlay now mirrors drag-to-trash scale/opacity animation for visual consistency

### Changed
- Adaptive `pixelRatio` for video overlay capture (clamped 1.0-2.0) instead of fixed 3.0 to optimize performance
- Audio preserved via single-pass passthrough muxing (no temp file, no double I/O)
- Overlay aspect ratio handling: cover+center crop to match video dimensions

---

## 1.0.1

### Added
- `shareButtonColor` config in `StoryEditorTheme` for customizing share button color
- `userProfileImageUrl` parameter for "Your Story" profile picture
- Close button (X) in text editing mode to return to editor
- All close friends are now selected by default in share modal

### Fixed
- Back button in drawing mode now returns to editor instead of camera
- Text editing close button now properly closes the modal

### Updated
- Updated all dependencies to latest versions:
  - `flutter_svg`: ^2.2.3
  - `video_player`: ^2.10.1
  - `path_provider`: ^2.1.5
  - `camera`: ^0.11.3
  - `permission_handler`: ^12.0.1
  - `photo_manager`: ^3.8.3
  - `shared_preferences`: ^2.5.4

---

## 1.0.0

Initial release with full feature set:

### Camera
- Photo and video capture
- Front/back camera switching
- Flash control (on/off/auto)
- Pinch-to-zoom support
- Gallery integration

### Recording Modes
- **Normal** - Tap for photo, hold for video
- **Boomerang** - Instagram-style looping videos
- **Collage** - Multi-photo layouts (2, 4, 6 grid)
- **Hands-Free** - Timer-based recording (3, 5, 10, 15 sec)

### Editor
- Drawing tools with 6 brush types (normal, marker, glow, chalk, arrow, eraser)
- Text overlays with customizable fonts and colors
- Gradient text editor for creating text-based stories
- Undo support for drawings

### Sharing
- Close friends selection UI
- Share to story or close friends
- `StoryShareResult` with file info and selected friends

### Customization
- `StoryEditorConfigProvider` for global configuration
- Customizable strings (localization support)
- Customizable theme (colors, icons)
- Customizable fonts and gradients
- Settings persistence with SharedPreferences
