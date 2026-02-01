import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:story_editor_pro/story_editor_pro.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Wrap with StoryEditorConfigProvider for full customization
    return StoryEditorConfigProvider(
      config: StoryEditorConfig(
        // ═══════════════════════════════════════════════════════════════
        // LOCALIZATION - All UI texts (English defaults shown)
        // Naming: [screenName][elementName]
        // ═══════════════════════════════════════════════════════════════
        strings: const StoryEditorStrings(
          // ─────────────────────────────────────────────────────────────
          // Camera Settings Screen (settings*)
          // ─────────────────────────────────────────────────────────────
          settingsTitle: 'Settings',
          settingsControlsSection: 'Controls',
          settingsFrontCameraTitle: 'Front Camera Default',
          settingsFrontCameraSubtitle: 'Start with front camera when app opens',
          settingsToolsSection: 'Camera Tools',
          settingsToolbarPositionTitle: 'Toolbar Position',
          settingsToolbarPositionSubtitle:
              'Choose which side of the screen boomerang, text editor, and frame tools appear.',
          settingsLeftSide: 'Left Side',
          settingsRightSide: 'Right Side',

          // ─────────────────────────────────────────────────────────────
          // Camera Screen (camera*)
          // ─────────────────────────────────────────────────────────────
          cameraStory: 'Story',
          cameraGallery: 'Gallery',
          cameraCancel: 'Cancel',
          cameraDelete: 'Delete',
          cameraSettings: 'Settings',
          cameraPermissionRequired: 'Camera Permission Required',
          cameraPermissionDescription:
              'We need camera access to create stories.',
          cameraGrantPermission: 'Grant Permission',
          cameraGalleryAccessDenied: 'Gallery access denied',
          cameraNoMediaInGallery: 'No media found in gallery',
          cameraNoImagesInGallery: 'No images found in gallery',
          cameraCouldNotOpenGallery: 'Could not open gallery',
          cameraCouldNotTakePhoto: 'Could not take photo',
          cameraCouldNotStartVideo: 'Could not start video',
          cameraCouldNotCreateCollage: 'Could not create collage',
          cameraCouldNotCreateBoomerang: 'Could not create boomerang',
          cameraBoomerangProcessingError: 'Error processing boomerang',
          cameraDeletePhoto: 'Delete Photo',
          cameraDeletePhotoConfirmation: 'Do you want to delete this photo?',
          cameraCapture: 'Capture',
          cameraStartAfter: 'Start after',
          cameraProcessingImage: 'Processing image...',
          cameraProcessingVideo: 'Processing video...',
          cameraProcessing: 'Processing...',
          cameraCreatingBoomerang: 'Creating boomerang...',
          cameraPhoto: 'Photo',
          cameraVideo: 'Video',
          cameraBoomerang: 'Boomerang',

          // ─────────────────────────────────────────────────────────────
          // Gradient Text Editor (gradient*)
          // ─────────────────────────────────────────────────────────────
          gradientBalance: 'Balance',
          gradientWriteSomething: 'Write something...',
          gradientProcessingImage: 'Processing image...',

          // ─────────────────────────────────────────────────────────────
          // Story Editor Screen (editor*)
          // ─────────────────────────────────────────────────────────────
          editorImageSettings: 'Image Settings',
          editorOk: 'OK',
          editorShare: 'Share',
          editorCloseFriends: 'Close Friends',
          editorPeopleCount: '0 people',
          editorCouldNotSave: 'Could not save',
          editorYourStory: 'Your Story',
          editorFacebookStory: 'And Facebook Story',
          editorEnterText: 'Enter text...',

          // ─────────────────────────────────────────────────────────────
          // Story Editor - Brush Types (editorBrush*)
          // ─────────────────────────────────────────────────────────────
          editorBrushNormal: 'Normal',
          editorBrushArrow: 'Arrow',
          editorBrushMarker: 'Marker',
          editorBrushGlow: 'Glow',
          editorBrushEraser: 'Eraser',
          editorBrushChalk: 'Chalk',
        ),

        // ═══════════════════════════════════════════════════════════════
        // THEME - Colors, Icons, Gradients
        // ═══════════════════════════════════════════════════════════════
        theme: StoryEditorTheme(
          // ─────────────────────────────────────────────────────────────
          // Primary Colors
          // ─────────────────────────────────────────────────────────────
          primaryColor: const Color(0xFFC13584), // Instagram Pink
          // ─────────────────────────────────────────────────────────────
          // Background Colors
          // ─────────────────────────────────────────────────────────────
          backgroundColor: const Color(0xFF121212), // Dark background
          surfaceColor: const Color(0xFF1E1E1E), // Card/surface color
          overlayColor: const Color(0xFF2A2A2A), // Darker overlay
          // ─────────────────────────────────────────────────────────────
          // Text Colors
          // ─────────────────────────────────────────────────────────────
          textColor: Colors.white,
          textSecondaryColor: Colors.white70,
          hintColor: Colors.white54,

          // ─────────────────────────────────────────────────────────────
          // State Colors
          // ─────────────────────────────────────────────────────────────
          recordingColor: const Color(0xFFFF3B30), // Red for recording
          switchActiveColor: const Color(0xFF007AFF), // iOS Blue
          errorColor: Colors.red,
          successColor: const Color(0xFF1DB954), // Spotify Green
          // ─────────────────────────────────────────────────────────────
          // Drawing color palette (Story Editor brush tools)
          // ─────────────────────────────────────────────────────────────
          drawingColors: const [
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

          // ─────────────────────────────────────────────────────────────
          // Boomerang button gradient (Camera Screen)
          // ─────────────────────────────────────────────────────────────
          boomerangGradientColors: const [
            Color(0xFFF77737), // Orange
            Color(0xFFE1306C), // Pink
            Color(0xFFC13584), // Dark Pink
          ],

          // ─────────────────────────────────────────────────────────────
          // Icons - All customizable icons
          // ─────────────────────────────────────────────────────────────
          icons: const StoryEditorIcons(
            // Tool Bar Icons
            boomerangIconData: Icons.all_inclusive,
            boomerangIconBackgroundColor: Color(0xFFC13584), // Instagram Pink
            boomerangIconColor: Colors.white,
            collageIconData: Icons.grid_view,
            collageIconBackgroundColor: Colors.white24,
            collageIconColor: Colors.white,
            handsFreeIconData: Icons.timer,
            handsFreeIconBackgroundColor: Colors.white24,
            handsFreeIconColor: Colors.white,
            gradientTextIconData: Icons.text_fields,
            gradientTextIconBackgroundColor: Colors.white24,
            gradientTextIconColor: Colors.white,

            // Common Icons
            closeIcon: Icons.close,
            checkIcon: Icons.check,
            undoIcon: Icons.undo,
            editIcon: Icons.edit,
            textIcon: Icons.text_fields,

            // Camera Icons
            flashOnIcon: Icons.flash_on,
            flashOffIcon: Icons.flash_off,
            flashAutoIcon: Icons.flash_auto,
            cameraSwitchIcon: Icons.flip_camera_ios,
            cameraIcon: Icons.camera_alt_outlined,

            // Navigation Icons
            settingsIcon: Icons.settings,
            galleryIcon: Icons.photo_library,
            arrowBackIcon: Icons.arrow_back_ios,
            arrowForwardIcon: Icons.arrow_forward,

            // Media Icons
            playIcon: Icons.play_arrow,
            pauseIcon: Icons.pause,
            brokenImageIcon: Icons.broken_image_outlined,

            // Gradient Editor Direction Icons (6 directions)
            directionIcons: [
              Icons.north_west,
              Icons.north,
              Icons.north_east,
              Icons.west,
              Icons.south_west,
              Icons.south,
            ],

            // Brush Type Icons
            brushNormalIcon: Icons.edit,
            brushArrowIcon: Icons.arrow_upward,
            brushMarkerIcon: Icons.highlight,
            brushGlowIcon: Icons.auto_awesome,
            brushEraserIcon: Icons.auto_fix_normal,
            brushChalkIcon: Icons.gesture,
          ),

          // ─────────────────────────────────────────────────────────────
          // Gradients for Gradient Text Editor
          // ─────────────────────────────────────────────────────────────
          gradients: const StoryEditorGradients(
            presets: [
              // Gradient presets
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
              // Solid colors
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
          ),
        ),

        // ═══════════════════════════════════════════════════════════════
        // FONTS - Story Editor text font styles (Google Fonts)
        // User provides TextStyle from their own fonts (Google Fonts, asset fonts, etc.)
        // ═══════════════════════════════════════════════════════════════
        fonts: StoryEditorFonts(
          fontStyles: [
            FontStyleConfig(
              name: 'Default',
              textStyle: const TextStyle(),
            ),
            FontStyleConfig(
              name: 'Bungee',
              textStyle: GoogleFonts.bungee(),
            ),
            FontStyleConfig(
              name: 'Lobster',
              textStyle: GoogleFonts.lobster(),
            ),
            FontStyleConfig(
              name: 'Pacifico',
              textStyle: GoogleFonts.pacifico(),
            ),
            FontStyleConfig(
              name: 'Bebas Neue',
              textStyle: GoogleFonts.bebasNeue(),
            ),
            FontStyleConfig(
              name: 'Permanent Marker',
              textStyle: GoogleFonts.permanentMarker(),
            ),
          ],
          defaultFontIndex: 0,
          defaultFontSize: 24.0,
          minFontSize: 12.0,
          maxFontSize: 72.0,
        ),

        // ═══════════════════════════════════════════════════════════════
        // SETTINGS - Stored automatically with SharedPreferences
        // ═══════════════════════════════════════════════════════════════
        settings: const StoryEditorSettings(
          // Initial/default values (used if no saved value exists)
          initialFrontCameraDefault: false,
          initialToolsOnLeft: false,
        ),

        // ═══════════════════════════════════════════════════════════════
        // TIMING & LIMITS
        // ═══════════════════════════════════════════════════════════════
        handsFreeDelayOptions: const [3, 5, 10, 15],
        defaultHandsFreeDelay: 3,
        maxHandsFreeRecordingSeconds: 60,
        maxVideoRecordingSeconds: 60,
        maxBoomerangSeconds: 4,
        defaultGradientBalance: 0.5,
      ),
      child: MaterialApp(
        title: 'Story Editor Pro Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _capturedImagePath;

  @override
  Widget build(BuildContext context) {
    // Eğer fotoğraf varsa tam ekranda göster
    if (_capturedImagePath != null) {
      return _buildImagePreview();
    }

    return _buildHomeContent();
  }

  Widget _buildImagePreview() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Fotoğraf tam ekran
            Image.file(File(_capturedImagePath!), fit: BoxFit.contain),
            // Üst kısımda çarpı butonu
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _capturedImagePath = null;
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            // Alt kısımda Story Editor'a git butonu
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => _openCamera(context),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Open Story Editor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_stories, size: 100, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  'Story Editor Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your story',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: () => _openCamera(context),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Open Camera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryCameraScreen(
          primaryColor: Colors.deepPurple,
          onImageCaptured: (path) {
            debugPrint('Photo captured: $path');
          },

          // ═══════════════════════════════════════════════════════════════
          // USER PROFILE - Shown in "Your Story" section of share bottomsheet
          // ═══════════════════════════════════════════════════════════════
          userProfileImageUrl: 'https://i.pravatar.cc/150?img=68',

          // ═══════════════════════════════════════════════════════════════
          // CLOSE FRIENDS - If list is not empty, close friends feature is enabled
          // If empty list or not provided, share bottomsheet will be skipped
          // All close friends are selected by default
          // ═══════════════════════════════════════════════════════════════
          closeFriendsList: const [
            CloseFriend(
              id: '1',
              name: 'John Doe',
              avatarUrl: 'https://i.pravatar.cc/150?img=1',
            ),
            CloseFriend(
              id: '2',
              name: 'Jane Smith',
              avatarUrl: 'https://i.pravatar.cc/150?img=2',
            ),
            CloseFriend(
              id: '3',
              name: 'Bob Wilson',
              avatarUrl: 'https://i.pravatar.cc/150?img=3',
            ),
            CloseFriend(
              id: '4',
              name: 'Alice Brown',
              avatarUrl: 'https://i.pravatar.cc/150?img=4',
            ),
            CloseFriend(
              id: '5',
              name: 'Charlie Davis',
              avatarUrl: 'https://i.pravatar.cc/150?img=5',
            ),
          ],

          // ═══════════════════════════════════════════════════════════════
          // SHARE CALLBACK - Called when story is shared
          // Contains file info AND selected close friends
          // ═══════════════════════════════════════════════════════════════
          onStoryShare: (shareResult) {
            debugPrint('═══════════════════════════════════════');
            debugPrint('Story shared!');
            debugPrint('Share target: ${shareResult.shareTarget}');
            debugPrint('File path: ${shareResult.story.filePath}');
            debugPrint('File size: ${shareResult.story.fileSizeFormatted}');

            if (shareResult.isCloseFriends) {
              debugPrint(
                'Selected friends: ${shareResult.selectedFriends.length}',
              );
              for (final friend in shareResult.selectedFriends) {
                debugPrint('  - ${friend.name} (${friend.id})');
              }
            }
            debugPrint('═══════════════════════════════════════');

            // Fotoğrafı kaydet ve ekranda göster
            final imagePath = shareResult.story.filePath;
            Navigator.pop(context);
            setState(() {
              _capturedImagePath = imagePath;
            });
          },
        ),
      ),
    );
  }
}
