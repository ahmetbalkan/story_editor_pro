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
