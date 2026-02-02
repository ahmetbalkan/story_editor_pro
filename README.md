# Story Editor Pro

[![pub package](https://img.shields.io/pub/v/story_editor_pro.svg)](https://pub.dev/packages/story_editor_pro)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A powerful, fully customizable Instagram-style story editor for Flutter. Create stunning stories with camera capture, drawing tools, text overlays, boomerang effects, collages, and close friends sharing.

> **Note:** This package was built with minimal dependencies in mind. I chose well-maintained packages that are unlikely to be deprecated and implemented video processing natively (Android: MediaCodec + MediaMuxer, iOS: AVAssetReader + AVAssetWriter) to avoid heavy FFmpeg dependencies. I hope this is useful for your projects. Looking forward to your feedback. Thank you!

## Features

<table>
<tr>
<td width="300">

<img src="[https://raw.githubusercontent.com/ahmetbalkan/story_editor_pro/refs/heads/main/story_editor_pro_gif.gif](https://github.com/ahmetbalkan/story_editor_pro/blob/main/story_editor_pro_gif.gif?raw=true)" width="280" alt="Story Editor Pro Demo"/>

</td>
<td>

| Feature | Description |
|---------|-------------|
| **Camera** | Full-featured camera with photo and video capture |
| **Boomerang** | Create Instagram-style looping video effects |
| **Collage** | Multi-photo grid layouts (2, 4, or 6 photos) |
| **Hands-Free** | Timer-based video recording (3, 5, 10, 15 sec) |
| **Drawing** | Multiple brush types: normal, marker, glow, chalk, arrow, eraser |
| **Text** | Customizable text overlays with fonts, colors, and styles |
| **Gradient Editor** | Create gradient background stories with text |
| **Close Friends** | Built-in close friends selection UI |
| **Customizable** | Themes, icons, strings, fonts - everything is configurable |

</td>
</tr>
</table>

## Installation

```yaml
dependencies:
  story_editor_pro: ^1.0.0
```

### Android Setup

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
```

Set minimum SDK in `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to create stories</string>
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to record videos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need photo library access to select media</string>
```

## Quick Start

### Basic Usage

```dart
import 'package:story_editor_pro/story_editor_pro.dart';

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => StoryCameraScreen(
      onStoryShare: (result) {
        print('Story saved: ${result.story.filePath}');
        Navigator.pop(context);
      },
    ),
  ),
);
```

### With Close Friends

When you provide a `closeFriendsList`, the close friends feature is automatically enabled:

```dart
StoryCameraScreen(
  closeFriendsList: [
    CloseFriend(id: '1', name: 'John Doe', avatarUrl: 'https://...'),
    CloseFriend(id: '2', name: 'Jane Smith', avatarUrl: 'https://...'),
  ],
  onStoryShare: (result) {
    if (result.isCloseFriends) {
      print('Shared to ${result.selectedFriends.length} friends');
      final friendIds = result.selectedFriends.map((f) => f.id).toList();
    } else {
      print('Shared to story');
    }
    final filePath = result.story.filePath;
    final fileBytes = await result.story.bytes;
  },
)
```

---

## Full Customization

Wrap your app with `StoryEditorConfigProvider` for complete control:

```dart
StoryEditorConfigProvider(
  config: StoryEditorConfig(
    strings: StoryEditorStrings(...),
    theme: StoryEditorTheme(...),
    fonts: StoryEditorFonts(...),
    // Timing settings
    handsFreeDelayOptions: [3, 5, 10, 15],
    defaultHandsFreeDelay: 3,
    maxHandsFreeRecordingSeconds: 60,
    maxVideoRecordingSeconds: 60,
    maxBoomerangSeconds: 4,
    defaultGradientBalance: 0.5,
  ),
  child: MaterialApp(...),
)
```

---

## StoryEditorStrings - All Localizable Texts

All UI texts can be customized for localization:

```dart
StoryEditorStrings(
  // ═══════════════════════════════════════════════════════════════════════
  // CAMERA SETTINGS SCREEN
  // ═══════════════════════════════════════════════════════════════════════
  settingsTitle: 'Settings',                           // Settings screen title
  settingsControlsSection: 'Controls',                 // Controls section header
  settingsFrontCameraTitle: 'Front Camera Default',    // Front camera toggle title
  settingsFrontCameraSubtitle: 'Start with front camera when app opens',
  settingsToolsSection: 'Camera Tools',                // Tools section header
  settingsToolbarPositionTitle: 'Toolbar Position',    // Toolbar position title
  settingsToolbarPositionSubtitle: 'Choose which side of the screen tools appear',
  settingsLeftSide: 'Left Side',                       // Left side option
  settingsRightSide: 'Right Side',                     // Right side option

  // ═══════════════════════════════════════════════════════════════════════
  // CAMERA SCREEN
  // ═══════════════════════════════════════════════════════════════════════
  cameraStory: 'Story',                                // Story mode label
  cameraGallery: 'Gallery',                            // Gallery button label
  cameraCancel: 'Cancel',                              // Cancel button
  cameraDelete: 'Delete',                              // Delete button
  cameraSettings: 'Settings',                          // Settings button
  cameraPermissionRequired: 'Camera Permission Required',
  cameraPermissionDescription: 'We need camera access to create stories.',
  cameraGrantPermission: 'Grant Permission',           // Permission button
  cameraGalleryAccessDenied: 'Gallery access denied',  // Gallery permission error
  cameraNoMediaInGallery: 'No media found in gallery', // Empty gallery message
  cameraNoImagesInGallery: 'No images found in gallery',
  cameraCouldNotOpenGallery: 'Could not open gallery', // Gallery error
  cameraCouldNotTakePhoto: 'Could not take photo',     // Photo capture error
  cameraCouldNotStartVideo: 'Could not start video',   // Video start error
  cameraCouldNotCreateCollage: 'Could not create collage',
  cameraCouldNotCreateBoomerang: 'Could not create boomerang',
  cameraBoomerangProcessingError: 'Error processing boomerang',
  cameraDeletePhoto: 'Delete Photo',                   // Delete photo dialog title
  cameraDeletePhotoConfirmation: 'Do you want to delete this photo?',
  cameraCapture: 'Capture',                            // Capture label (collage mode)
  cameraStartAfter: 'Start after',                     // Hands-free countdown label
  cameraProcessingImage: 'Processing image...',        // Image processing message
  cameraProcessingVideo: 'Processing video...',        // Video processing message
  cameraProcessing: 'Processing...',                   // Generic processing message
  cameraCreatingBoomerang: 'Creating boomerang...',    // Boomerang processing message
  cameraPhoto: 'Photo',                                // Photo mode label
  cameraVideo: 'Video',                                // Video mode label
  cameraBoomerang: 'Boomerang',                        // Boomerang mode label

  // ═══════════════════════════════════════════════════════════════════════
  // GRADIENT TEXT EDITOR
  // ═══════════════════════════════════════════════════════════════════════
  gradientBalance: 'Balance',                          // Gradient balance slider label
  gradientWriteSomething: 'Write something...',        // Text input placeholder
  gradientProcessingImage: 'Processing image...',      // Processing message

  // ═══════════════════════════════════════════════════════════════════════
  // STORY EDITOR SCREEN
  // ═══════════════════════════════════════════════════════════════════════
  editorImageSettings: 'Image Settings',               // Image settings button
  editorOk: 'OK',                                      // OK button
  editorShare: 'Share',                                // Share button
  editorCloseFriends: 'Close Friends',                 // Close friends section title
  editorPeopleCount: '0 people',                       // People count label
  editorCouldNotSave: 'Could not save',                // Save error message
  editorYourStory: 'Your Story',                       // Your story share option
  editorFacebookStory: 'And Facebook Story',           // Facebook story option
  editorEnterText: 'Enter text...',                    // Text input placeholder

  // ═══════════════════════════════════════════════════════════════════════
  // BRUSH TYPE NAMES
  // ═══════════════════════════════════════════════════════════════════════
  editorBrushNormal: 'Normal',                         // Normal brush name
  editorBrushArrow: 'Arrow',                           // Arrow brush name
  editorBrushMarker: 'Marker',                         // Marker brush name
  editorBrushGlow: 'Glow',                             // Glow/neon brush name
  editorBrushEraser: 'Eraser',                         // Eraser name
  editorBrushChalk: 'Chalk',                           // Chalk brush name
)
```

---

## StoryEditorTheme - Colors and Styling

```dart
StoryEditorTheme(
  // ═══════════════════════════════════════════════════════════════════════
  // PRIMARY COLORS
  // ═══════════════════════════════════════════════════════════════════════
  primaryColor: Color(0xFFC13584),      // Main accent color (buttons, highlights)
  secondaryColor: Color(0xFF833AB4),    // Secondary accent color

  // ═══════════════════════════════════════════════════════════════════════
  // BACKGROUND COLORS
  // ═══════════════════════════════════════════════════════════════════════
  backgroundColor: Color(0xFF121212),   // Main background color
  surfaceColor: Color(0xFF1E1E1E),      // Cards, dialogs, bottom sheets
  overlayColor: Color(0xFF2A2A2A),      // Darker overlays, headers

  // ═══════════════════════════════════════════════════════════════════════
  // TEXT COLORS
  // ═══════════════════════════════════════════════════════════════════════
  textColor: Colors.white,              // Primary text color
  textSecondaryColor: Colors.white70,   // Secondary/muted text
  hintColor: Colors.white54,            // Placeholder/hint text

  // ═══════════════════════════════════════════════════════════════════════
  // STATE COLORS
  // ═══════════════════════════════════════════════════════════════════════
  recordingColor: Color(0xFFFF3B30),    // Recording indicator (red dot)
  switchActiveColor: Color(0xFF007AFF), // Toggle switch active state
  errorColor: Colors.red,               // Error messages and states
  successColor: Color(0xFF1DB954),      // Success messages and states

  // ═══════════════════════════════════════════════════════════════════════
  // DRAWING COLOR PALETTE
  // Colors available in the drawing tool color picker
  // ═══════════════════════════════════════════════════════════════════════
  drawingColors: [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ],

  // ═══════════════════════════════════════════════════════════════════════
  // BOOMERANG BUTTON GRADIENT
  // Gradient colors for the boomerang mode button
  // ═══════════════════════════════════════════════════════════════════════
  boomerangGradientColors: [
    Color(0xFFF77737),  // Orange
    Color(0xFFE1306C),  // Pink
    Color(0xFFC13584),  // Dark pink
  ],

  // ═══════════════════════════════════════════════════════════════════════
  // SHARE BUTTON COLOR
  // Color for the share button in the share bottom sheet
  // ═══════════════════════════════════════════════════════════════════════
  shareButtonColor: Color(0xFF0095F6),  // Instagram blue

  // Icons and Gradients (see below)
  icons: StoryEditorIcons(...),
  gradients: StoryEditorGradients(...),
)
```

---

## StoryEditorIcons - All Customizable Icons

```dart
StoryEditorIcons(
  // ═══════════════════════════════════════════════════════════════════════
  // TOOLBAR ICONS (Camera screen right side)
  // ═══════════════════════════════════════════════════════════════════════

  // Boomerang button
  boomerangIcon: null,                              // Custom widget (takes precedence)
  boomerangIconData: Icons.all_inclusive,           // Icon when no custom widget
  boomerangIconBackgroundColor: Color(0xFFC13584),  // Button background color
  boomerangIconColor: Colors.white,                 // Icon color

  // Collage/Layout button
  collageIcon: null,                                // Custom widget
  collageIconData: Icons.grid_view,                 // Grid layout icon
  collageIconBackgroundColor: Colors.white24,       // Button background
  collageIconColor: Colors.white,                   // Icon color

  // Hands-Free timer button
  handsFreeIcon: null,                              // Custom widget
  handsFreeIconData: Icons.timer,                   // Timer icon
  handsFreeIconBackgroundColor: Colors.white24,     // Button background
  handsFreeIconColor: Colors.white,                 // Icon color

  // Gradient Text Editor button
  gradientTextIcon: null,                           // Custom widget
  gradientTextIconData: Icons.text_fields,          // Text icon
  gradientTextIconBackgroundColor: Colors.white24,  // Button background
  gradientTextIconColor: Colors.white,              // Icon color

  // ═══════════════════════════════════════════════════════════════════════
  // COMMON ICONS
  // ═══════════════════════════════════════════════════════════════════════
  closeIcon: Icons.close,                // Close/dismiss button
  checkIcon: Icons.check,                // Confirm/done button
  undoIcon: Icons.undo,                  // Undo drawing action
  editIcon: Icons.edit,                  // Edit/draw mode button
  textIcon: Icons.text_fields,           // Add text button

  // ═══════════════════════════════════════════════════════════════════════
  // CAMERA ICONS
  // ═══════════════════════════════════════════════════════════════════════
  flashOnIcon: Icons.flash_on,           // Flash enabled
  flashOffIcon: Icons.flash_off,         // Flash disabled
  flashAutoIcon: Icons.flash_auto,       // Flash auto mode
  cameraSwitchIcon: Icons.flip_camera_ios, // Switch front/back camera
  cameraIcon: Icons.camera_alt_outlined, // Camera button

  // ═══════════════════════════════════════════════════════════════════════
  // NAVIGATION ICONS
  // ═══════════════════════════════════════════════════════════════════════
  settingsIcon: Icons.settings,          // Settings button
  galleryIcon: Icons.photo_library,      // Gallery/photos button
  arrowBackIcon: Icons.arrow_back_ios,   // Back navigation
  arrowForwardIcon: Icons.arrow_forward, // Forward navigation

  // ═══════════════════════════════════════════════════════════════════════
  // MEDIA ICONS
  // ═══════════════════════════════════════════════════════════════════════
  playIcon: Icons.play_arrow,            // Play video
  pauseIcon: Icons.pause,                // Pause video
  brokenImageIcon: Icons.broken_image_outlined, // Image load error

  // ═══════════════════════════════════════════════════════════════════════
  // GRADIENT EDITOR DIRECTION ICONS
  // 6 icons for gradient direction selection
  // ═══════════════════════════════════════════════════════════════════════
  directionIcons: [
    Icons.north_west,   // Top-left to bottom-right
    Icons.north,        // Top to bottom
    Icons.north_east,   // Top-right to bottom-left
    Icons.west,         // Left to right
    Icons.south_west,   // Bottom-left to top-right
    Icons.south,        // Bottom to top
  ],

  // ═══════════════════════════════════════════════════════════════════════
  // BRUSH TYPE ICONS
  // ═══════════════════════════════════════════════════════════════════════
  brushNormalIcon: Icons.edit,           // Normal drawing brush
  brushArrowIcon: Icons.arrow_upward,    // Arrow tip brush
  brushMarkerIcon: Icons.highlight,      // Highlighter/marker brush
  brushGlowIcon: Icons.auto_awesome,     // Neon glow brush
  brushEraserIcon: Icons.auto_fix_normal, // Eraser tool
  brushChalkIcon: Icons.gesture,         // Chalk texture brush
)
```

---

## StoryEditorFonts - Text Style Configuration

```dart
StoryEditorFonts(
  // Available font styles for text overlays
  fontStyles: [
    FontStyleConfig(
      name: 'Bold',                      // Display name in UI
      fontWeight: FontWeight.bold,       // Font weight
      fontStyle: FontStyle.normal,       // Normal or italic
      letterSpacing: 0.0,                // Letter spacing
      fontFamily: null,                  // Custom font family (null = system)
    ),
    FontStyleConfig(
      name: 'Light',
      fontWeight: FontWeight.w300,
      fontStyle: FontStyle.normal,
      letterSpacing: 0.5,
    ),
    FontStyleConfig(
      name: 'Italic',
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.0,
    ),
    FontStyleConfig(
      name: 'Bold Italic',
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.0,
    ),
  ],

  defaultFontIndex: 0,     // Which font is selected by default (index)
  defaultFontSize: 32.0,   // Default text size
  minFontSize: 12.0,       // Minimum allowed font size
  maxFontSize: 72.0,       // Maximum allowed font size
)
```

---

## StoryEditorGradients - Gradient Text Editor Presets

```dart
StoryEditorGradients(
  presets: [
    // ═══════════════════════════════════════════════════════════════════════
    // GRADIENT PRESETS
    // ═══════════════════════════════════════════════════════════════════════
    GradientPreset(
      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
      name: 'Purple-Blue',
    ),
    GradientPreset(
      colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
      name: 'Pink',
    ),
    GradientPreset(
      colors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
      name: 'Blue-Cyan',
    ),
    GradientPreset(
      colors: [Color(0xFF43e97b), Color(0xFF38f9d7)],
      name: 'Green-Teal',
    ),
    GradientPreset(
      colors: [Color(0xFFfa709a), Color(0xFFfee140)],
      name: 'Pink-Yellow',
    ),
    GradientPreset(
      colors: [Color(0xFFa8edea), Color(0xFFfed6e3)],
      name: 'Pastel',
    ),
    GradientPreset(
      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
      name: 'Indigo',
    ),
    GradientPreset(
      colors: [Color(0xFFff9a9e), Color(0xFFfecfef)],
      name: 'Soft Pink',
    ),
    GradientPreset(
      colors: [Color(0xFFffecd2), Color(0xFFfcb69f)],
      name: 'Peach',
    ),
    GradientPreset(
      colors: [Color(0xFF89f7fe), Color(0xFF66a6ff)],
      name: 'Sky',
    ),
    GradientPreset(
      colors: [Color(0xFFa18cd1), Color(0xFFfbc2eb)],
      name: 'Lavender',
    ),
    GradientPreset(
      colors: [Color(0xFFfad0c4), Color(0xFFffd1ff)],
      name: 'Soft Rose',
    ),
    GradientPreset(
      colors: [Color(0xFFff8177), Color(0xFFcf556c)],
      name: 'Red',
    ),
    GradientPreset(
      colors: [Color(0xFFFFB347), Color(0xFFFFCC33)],
      name: 'Orange',
    ),
    GradientPreset(
      colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
      name: 'Green',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // SOLID COLORS (same color for both = solid background)
    // ═══════════════════════════════════════════════════════════════════════
    GradientPreset(
      colors: [Color(0xFF000000), Color(0xFF000000)],
      name: 'Black',
    ),
    GradientPreset(
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
      name: 'White',
    ),
    GradientPreset(
      colors: [Color(0xFF1a1a2e), Color(0xFF1a1a2e)],
      name: 'Dark Navy',
    ),
  ],
)
```

---

## StoryEditorConfig - All Settings

```dart
StoryEditorConfig(
  // ═══════════════════════════════════════════════════════════════════════
  // TIMING SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  // Hands-free delay options shown in UI (seconds)
  handsFreeDelayOptions: [3, 5, 10, 15],

  // Default selected delay (seconds)
  defaultHandsFreeDelay: 3,

  // Maximum hands-free recording duration (seconds)
  maxHandsFreeRecordingSeconds: 60,

  // Maximum normal video recording duration (seconds)
  maxVideoRecordingSeconds: 60,

  // Maximum boomerang recording duration (seconds)
  maxBoomerangSeconds: 4,

  // Default gradient balance (0.0 to 1.0)
  // 0.5 = 50%/50% color distribution
  defaultGradientBalance: 0.5,

  // ═══════════════════════════════════════════════════════════════════════
  // BOOMERANG SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  // Output FPS (lower = slower playback, higher = faster)
  // Range: 10-30 recommended, default: 15 for smooth slow-motion
  boomerangFps: 15,

  // Number of loops (forward + backward = 1 loop)
  // Instagram uses 3 loops
  boomerangLoopCount: 3,

  // Boomerang button gradient colors
  boomerangGradientColors: [Color(0xFFFF6B35), Color(0xFFFF1744)],

  // ═══════════════════════════════════════════════════════════════════════
  // UI SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  // Recording indicator color (default: Instagram red)
  recordingIndicatorColor: Color(0xFFFF3B30),

  // Story canvas dimensions for export
  storyCanvasWidth: 1080,
  storyCanvasHeight: 1920,

  // Screen breakpoint for responsive UI
  smallScreenBreakpoint: 700,

  // Shutter button sizes
  shutterButtonSizeLarge: 90,   // Large screens
  shutterButtonSizeSmall: 70,   // Small screens

  // Gallery pagination
  galleryPageSize: 50,

  // ═══════════════════════════════════════════════════════════════════════
  // ANIMATION SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  // Default animation duration for UI transitions
  animationDuration: Duration(milliseconds: 200),

  // Auto-close delay for "Saved" modal
  savedModalAutoCloseDelay: Duration(seconds: 3),

  // Gallery thumbnail settings
  thumbnailSize: 200,
  thumbnailQuality: 80,  // 1-100

  // Recording indicator pulse animation scale
  pulseAnimationScale: 1.15,
)
```

---

## API Reference

### StoryCameraScreen

| Parameter | Type | Description |
|-----------|------|-------------|
| `onStoryShare` | `Function(StoryShareResult)` | Called when story is shared |
| `onImageCaptured` | `Function(String)?` | Called when photo is captured (before editing) |
| `closeFriendsList` | `List<CloseFriend>` | Close friends list (enables feature if not empty) |
| `primaryColor` | `Color?` | Primary accent color |
| `showEditor` | `bool` | Show editor after capture (default: `true`) |

### StoryShareResult

```dart
class StoryShareResult {
  final StoryResult story;           // File info and helpers
  final ShareTarget shareTarget;     // story or closeFriends
  final List<CloseFriend> selectedFriends;

  bool get isCloseFriends;           // true if shared to close friends
}
```

### StoryResult

```dart
class StoryResult {
  final String filePath;             // Full path to saved file
  File get file;                     // File object
  Future<Uint8List> get bytes;       // File bytes for upload
  Future<String> get base64;         // Base64 encoded
  String get fileSizeFormatted;      // e.g., "2.5 MB"

  Map<String, dynamic> toJson();     // For API serialization
}
```

### CloseFriend

```dart
class CloseFriend {
  final String id;
  final String name;
  final String? avatarUrl;
}
```

---

## Example

Check the [example](example/) folder for a complete working demo:

```bash
cd example
flutter run
```

## Dependencies

This package uses minimal, well-maintained dependencies:

| Package | Purpose |
|---------|---------|
| `camera` | Camera access and capture |
| `video_player` | Video playback |
| `photo_manager` | Gallery access |
| `permission_handler` | Runtime permissions |
| `path_provider` | File storage paths |
| `shared_preferences` | User preferences |
| `flutter_svg` | SVG icon support |

**No FFmpeg!** Boomerang video processing is implemented natively:
- **Android:** MediaCodec + MediaMuxer
- **iOS:** AVAssetReader + AVAssetWriter

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.
