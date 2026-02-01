import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'story_editor_screen.dart';
import 'boomerang_recorder.dart';
import 'gradient_text_editor.dart';
import 'camera_settings_screen.dart';
import 'config/story_editor_config.dart';
import 'models/story_result.dart';

/// Layout types - Instagram Layout style collage layouts
enum LayoutType {
  /// Vertical 2 - 2 squares stacked vertically
  twoVertical,

  /// Horizontal 2 - 2 long squares side by side
  twoHorizontal,

  /// 2x2 Grid - 4 squares
  fourGrid,

  /// 2x3 Grid - 6 squares
  sixGrid,
}

/// Helper extension for LayoutType
extension LayoutTypeExtension on LayoutType {
  /// How many photos this layout requires
  int get photoCount {
    switch (this) {
      case LayoutType.twoVertical:
      case LayoutType.twoHorizontal:
        return 2;
      case LayoutType.fourGrid:
        return 4;
      case LayoutType.sixGrid:
        return 6;
    }
  }

  /// Icon display for layout (simple representation)
  String get label {
    switch (this) {
      case LayoutType.twoVertical:
        return '2V';
      case LayoutType.twoHorizontal:
        return '2H';
      case LayoutType.fourGrid:
        return '2×2';
      case LayoutType.sixGrid:
        return '2×3';
    }
  }
}

class StoryCameraScreen extends StatefulWidget {
  /// Called when an image is captured (before editing)
  final Function(String imagePath)? onImageCaptured;

  /// Called when story is shared
  /// Contains story file info and selected close friends (if any)
  final Function(StoryShareResult result)? onStoryShare;

  final Color? primaryColor;
  final bool showEditor;

  /// List of close friends to show in the share bottomsheet
  /// If not empty, close friends sharing option will be enabled
  /// If empty, the share bottomsheet will be skipped
  final List<CloseFriend> closeFriendsList;

  /// Returns true if close friends list is not empty
  bool get closeFriendsEnabled => closeFriendsList.isNotEmpty;

  const StoryCameraScreen({
    super.key,
    this.onImageCaptured,
    this.onStoryShare,
    this.primaryColor,
    this.showEditor = true,
    this.closeFriendsList = const [],
  });

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Flutter Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  bool _isInitialized = false;

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  double _zoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _longPressStartY = 0.0; // Starting Y position for long press zoom
  double _longPressZoomStart = 1.0; // Starting zoom level for long press zoom
  Uint8List? _lastGalleryThumbnail; // Thumbnail data for gallery button
  bool _hasGalleryPermission = false;

  // Settings
  bool _toolsOnLeft = false; // Is toolbar on the left side

  // Boomerang state
  bool _isBoomerangMode = false;
  static const int _boomerangMaxSeconds = 4; // Max 4 seconds

  // Video recording state
  bool _isVideoRecording = false;
  bool _isProcessingVideo = false;
  Timer? _videoRecordingTimer;
  int _videoRecordingElapsedMs = 0;
  static const int _videoMaxSeconds = 60; // Max 60 seconds

  // Boomerang recording progress
  Timer? _boomerangTimer;
  double _boomerangProgress = 0.0; // 0.0 - 1.0
  int _boomerangElapsedMs = 0;

  // Instagram-style boomerang recorder (photo capture based)
  BoomerangRecorder? _boomerangRecorder;

  // For flash effect
  bool _showFlash = false;

  // MultiLayout (Collage) state
  bool _isLayoutMode = false;
  bool _showLayoutSelector = false;
  LayoutType _selectedLayout = LayoutType.twoVertical;
  List<File?> _capturedLayoutPhotos = [];
  int _activeLayoutIndex = 0;
  bool _isLayoutProcessing = false; // True during layout merge process

  // Pending text overlay from Create Mode
  TextOverlay? _pendingTextOverlay;

  // Hands-free mode state
  bool _isHandsFreeMode = false;
  bool _showHandsFreeSelector = false;
  int _handsFreeDelaySeconds = 3; // 3, 5 or 10 seconds
  bool _isHandsFreeCountingDown = false;
  int _handsFreeCountdown = 0;
  Timer? _handsFreeCountdownTimer;
  Timer? _handsFreeRecordingTimer;
  int _handsFreeRecordingElapsed = 0;
  static const int _handsFreeMaxRecordingSeconds = 60; // 60 seconds max

  // Animation controller (for boomerang button)
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _loadSettings();
    _requestPermissionsAndInitialize();
  }

  /// Requests all required permissions when story editor is opened
  Future<void> _requestPermissionsAndInitialize() async {
    setState(() => _isLoading = true);

    // Request all permissions at once (permission_handler doesn't support parallel)
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
    ].request();

    final cameraStatus = statuses[Permission.camera]!;
    final galleryStatus = statuses[Permission.photos]!;

    _hasPermission = cameraStatus.isGranted;
    _hasGalleryPermission = galleryStatus.isGranted;

    if (!_hasPermission) {
      // Inform user if camera permission is denied
      if (mounted) {
        setState(() => _isLoading = false);
        _showPermissionDeniedDialog();
      }
      return;
    }

    // Permissions granted, initialize camera
    await _initializeCamera();
  }

  /// Dialog to show when permission is denied
  void _showPermissionDeniedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'We need camera and gallery permissions to create stories. Please grant permission from settings.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Load settings from config
  Future<void> _loadSettings() async {
    final config = StoryEditorConfigProvider.read(context);
    final toolsOnLeft = await config.settings.getToolsOnLeft();
    if (mounted) {
      setState(() {
        _toolsOnLeft = toolsOnLeft;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _boomerangTimer?.cancel();
    _boomerangRecorder?.dispose();
    _flashTimer?.cancel();
    _videoRecordingTimer?.cancel();
    _handsFreeCountdownTimer?.cancel();
    _handsFreeRecordingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Don't start if no permission
      if (!_hasPermission) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Get cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras available');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Get default camera from config
      if (!mounted) return;
      final config = StoryEditorConfigProvider.read(context);
      final useFrontCamera = await config.settings.getFrontCameraDefault();
      final preferredDirection = useFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == preferredDirection,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      // Create controller
      await _setupCameraController(_cameras[_currentCameraIndex]);

      // Load gallery thumbnail
      if (_hasGalleryPermission && mounted) {
        await _loadLastGalleryImage();
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupCameraController(CameraDescription camera) async {
    await _cameraController?.dispose();

    _cameraController = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation(
        DeviceOrientation.portraitUp,
      );

      _minZoom = await _cameraController!.getMinZoomLevel();
      _maxZoom = await _cameraController!.getMaxZoomLevel();
      _zoomLevel = _minZoom;

      await _cameraController!.setFlashMode(_flashMode);

      _isInitialized = true;

      debugPrint('Camera initialized: ${_cameraController!.value.previewSize}');

      if (mounted) setState(() {});
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.description}');
      _isInitialized = false;
    }
  }

  Future<void> _loadLastGalleryImage() async {
    // Get config before async operations to avoid BuildContext across async gaps
    final config = context.storyEditorConfig;

    try {
      // Gallery permission check
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        debugPrint('Gallery permission denied: $permission');
        return;
      }

      // Clear cache - to see new photos
      await PhotoManager.clearFileCache();

      // Get all albums (images and videos)
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        onlyAll: true,
      );

      debugPrint('Found ${albums.length} albums');

      if (albums.isEmpty) {
        debugPrint('No albums found');
        return;
      }

      // First album (All Photos / Recent)
      final AssetPathEntity recentAlbum = albums.first;
      final int assetCount = await recentAlbum.assetCountAsync;
      debugPrint('Album: ${recentAlbum.name}, asset count: $assetCount');

      if (assetCount == 0) {
        debugPrint('No assets in album');
        return;
      }

      // Get recently added media (try more, find the first displayable one)
      final List<AssetEntity> recentAssets = await recentAlbum
          .getAssetListPaged(
            page: 0,
            size: 20, // Get more, find the one that can get thumbnail
          );

      if (recentAssets.isEmpty) {
        debugPrint('No assets found in gallery');
        return;
      }

      // Find the first asset that can get thumbnail (with retry)
      for (final asset in recentAssets) {
        debugPrint('Trying asset: ${asset.id}, type: ${asset.type}');

        // Make 2 attempts for each asset
        for (int retry = 0; retry < 2; retry++) {
          try {
            // Get thumbnail (more reliable)
            final Uint8List? thumbData = await asset.thumbnailDataWithSize(
              ThumbnailSize(config.thumbnailSize, config.thumbnailSize),
              quality: config.thumbnailQuality,
            );

            if (thumbData != null && mounted) {
              debugPrint('Thumbnail loaded for asset: ${asset.id}');
              setState(() {
                _lastGalleryThumbnail = thumbData;
                _hasGalleryPermission = true;
              });
              return; // Found the first successful one, exit
            }
          } catch (e) {
            debugPrint('Thumbnail load attempt ${retry + 1} failed: $e');
          }

          // If first attempt failed, wait a bit
          if (retry == 0) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        }
      }

      // If no thumbnail could be obtained, at least set permission to true
      if (mounted) {
        setState(() {
          _hasGalleryPermission = true;
        });
      }
      debugPrint('Could not get thumbnail from any asset');
    } catch (e, stackTrace) {
      debugPrint('Error loading last gallery image: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Runs when gallery is tapped - request permission and open gallery
  Future<void> _openGallery() async {
    try {
      // First check permission
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        // Permission not granted - show warning
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gallery access denied'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => PhotoManager.openSetting(),
              ),
            ),
          );
        }
        return;
      }

      // If permission granted - update gallery permission
      if (mounted) {
        setState(() => _hasGalleryPermission = true);
      }

      // Clear cache - to see new photos
      await PhotoManager.clearFileCache();

      // Open gallery picker - get current media with filterOption
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No media found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Get all media
      final AssetPathEntity album = albums.first;
      final int totalCount = await album.assetCountAsync;

      if (totalCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No media found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Open gallery picker page
      if (mounted) {
        final selectedAsset = await Navigator.push<AssetEntity>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                _GalleryPickerPage(album: album, totalCount: totalCount),
          ),
        );

        // Process selected media
        if (selectedAsset != null && mounted) {
          final File? file = await selectedAsset.originFile;
          if (file != null && mounted) {
            // Check if image or video
            if (selectedAsset.type == AssetType.image) {
              widget.onImageCaptured?.call(file.path);

              if (widget.showEditor && mounted) {
                final pendingOverlay = _pendingTextOverlay;
                _pendingTextOverlay = null; // Clear after use

                await Navigator.push<Map<String, dynamic>?>(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => StoryEditorScreen(
                      imagePath: file.path,
                      primaryColor: widget.primaryColor,
                      isFromGallery: true,
                      initialTextOverlay: pendingOverlay,
                      closeFriendsList: widget.closeFriendsList,
                      onShare: widget.onStoryShare,
                    ),
                  ),
                );
                // onStoryShare callback is called from StoryEditorScreen
              }
            } else if (selectedAsset.type == AssetType.video) {
              // Video selected - call callback
              widget.onImageCaptured?.call(file.path);
            }
          }
        }

        // Update gallery thumbnail
        if (mounted) {
          _loadLastGalleryImage();
        }
      }
    } catch (e) {
      debugPrint('Gallery open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open gallery'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      HapticFeedback.mediumImpact();

      final XFile file = await _cameraController!.takePicture();
      final imagePath = file.path;

      if (mounted) {
        // Add captured photo to list in layout mode
        if (_isLayoutMode) {
          await _handleLayoutCapture(imagePath);
        } else {
          // Normal mode
          widget.onImageCaptured?.call(imagePath);

          if (widget.showEditor) {
            final pendingOverlay = _pendingTextOverlay;
            _pendingTextOverlay = null; // Clear after use

            await Navigator.push<Map<String, dynamic>?>(
              context,
              MaterialPageRoute(
                builder: (context) => StoryEditorScreen(
                  imagePath: imagePath,
                  primaryColor: widget.primaryColor,
                  initialTextOverlay: pendingOverlay,
                  closeFriendsList: widget.closeFriendsList,
                  onShare: widget.onStoryShare,
                ),
              ),
            );
            // onStoryShare callback is called from StoryEditorScreen
          }

          // Update gallery thumbnail after photo capture
          _loadLastGalleryImage();
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not take photo: $e')));
      }
    }

    if (mounted) {
      setState(() => _isCapturing = false);
    }
  }

  /// When photo is captured in layout mode
  Future<void> _handleLayoutCapture(String imagePath) async {
    // Save photo to active tile
    setState(() {
      _capturedLayoutPhotos[_activeLayoutIndex] = File(imagePath);
    });

    // Find the next empty tile
    int? nextEmptyIndex;
    for (int i = 0; i < _capturedLayoutPhotos.length; i++) {
      if (_capturedLayoutPhotos[i] == null) {
        nextEmptyIndex = i;
        break;
      }
    }

    if (nextEmptyIndex != null) {
      // Go to the next empty tile
      setState(() {
        _activeLayoutIndex = nextEmptyIndex!;
      });
    } else {
      // All photos captured - create collage
      await _createCollage();
    }
  }

  /// Select image from gallery for tile in layout mode
  Future<void> _pickImageForLayoutTile(int tileIndex) async {
    try {
      // First check permission
      final PermissionState permission =
          await PhotoManager.requestPermissionExtend(
            requestOption: const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.readWrite,
            ),
          );

      if (!permission.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gallery access denied'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => PhotoManager.openSetting(),
              ),
            ),
          );
        }
        return;
      }

      // Clear cache
      await PhotoManager.clearFileCache();

      // Get albums - only for images
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        onlyAll: true,
      );

      if (albums.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No images found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final AssetPathEntity album = albums.first;
      final int totalCount = await album.assetCountAsync;

      if (totalCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No images found in gallery'),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Open gallery picker page
      if (mounted) {
        final selectedAsset = await Navigator.push<AssetEntity>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                _GalleryPickerPage(album: album, totalCount: totalCount),
          ),
        );

        // Place selected image in tile
        if (selectedAsset != null && mounted) {
          final File? file = await selectedAsset.originFile;
          if (file != null && mounted) {
            HapticFeedback.mediumImpact();

            setState(() {
              _capturedLayoutPhotos[tileIndex] = file;
            });

            // Find the next empty tile
            int? nextEmptyIndex;
            for (int i = 0; i < _capturedLayoutPhotos.length; i++) {
              if (_capturedLayoutPhotos[i] == null) {
                nextEmptyIndex = i;
                break;
              }
            }

            if (nextEmptyIndex != null) {
              // Go to the next empty tile
              setState(() {
                _activeLayoutIndex = nextEmptyIndex!;
              });
            } else {
              // All photos ready - create collage
              await _createCollage();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Layout gallery pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open gallery'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Create collage when all photos are captured
  Future<void> _createCollage() async {
    // Make sure all photos are captured
    if (_capturedLayoutPhotos.any((photo) => photo == null)) {
      return;
    }

    setState(() {
      _isProcessingVideo = true;
      _isLayoutProcessing = true;
    });

    try {
      // Create collage
      final collagePath = await _generateCollageImage();

      if (collagePath != null && mounted) {
        // Processing completed
        setState(() {
          _isProcessingVideo = false;
          _isLayoutProcessing = false;
          _isLayoutMode = false;
          _showLayoutSelector = false;
        });

        // Navigate to editor
        widget.onImageCaptured?.call(collagePath);

        if (widget.showEditor) {
          final pendingOverlay = _pendingTextOverlay;
          _pendingTextOverlay = null; // Clear after use

          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: collagePath,
                primaryColor: widget.primaryColor,
                initialTextOverlay: pendingOverlay,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        }

        // Reset layout state
        setState(() {
          _capturedLayoutPhotos = [];
          _activeLayoutIndex = 0;
        });

        _loadLastGalleryImage();
      }
    } catch (e) {
      debugPrint('Collage creation error: $e');
      if (mounted) {
        setState(() {
          _isProcessingVideo = false;
          _isLayoutProcessing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create collage: $e')));
      }
    }
  }

  /// Generate collage image (merge with Canvas)
  Future<String?> _generateCollageImage() async {
    try {
      // Load photos
      final List<File> photos = _capturedLayoutPhotos
          .whereType<File>()
          .toList();
      if (photos.isEmpty) return null;

      // Canvas size (1080x1920 story format)
      const int canvasWidth = 1080;
      const int canvasHeight = 1920;
      const double spacing = 0.0; // Fullscreen without spacing

      // Create canvas with picture recorder
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Black background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        Paint()..color = Colors.black,
      );

      // Place each photo according to layout
      await _drawLayoutPhotos(
        canvas,
        photos,
        canvasWidth,
        canvasHeight,
        spacing,
      );

      // Convert picture to image
      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasWidth, canvasHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      // Save to file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/collage_$timestamp.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Generate collage error: $e');
      return null;
    }
  }

  /// Create only gradient background image (without text)
  Future<String?> _createGradientBackground(LinearGradient gradient) async {
    try {
      const int canvasWidth = 1080;
      const int canvasHeight = 1920;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw gradient background
      final gradientPaint = Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
        gradientPaint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasWidth, canvasHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/gradient_bg_$timestamp.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Create gradient background error: $e');
      return null;
    }
  }

  /// Draw photos on canvas according to layout
  Future<void> _drawLayoutPhotos(
    Canvas canvas,
    List<File> photos,
    int canvasWidth,
    int canvasHeight,
    double spacing,
  ) async {
    final List<Rect> rects = _getLayoutRects(
      canvasWidth.toDouble(),
      canvasHeight.toDouble(),
      spacing,
    );

    for (int i = 0; i < photos.length && i < rects.length; i++) {
      final rect = rects[i];
      final photoBytes = await photos[i].readAsBytes();
      final codec = await ui.instantiateImageCodec(photoBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Fit photo to rect (cover)
      final srcRect = _getCoverRect(
        Size(image.width.toDouble(), image.height.toDouble()),
        rect.size,
      );

      canvas.save();
      canvas.clipRect(rect); // Without corners, fullscreen
      canvas.drawImageRect(image, srcRect, rect, Paint());
      canvas.restore();
    }
  }

  /// Calculate rect positions according to layout type
  List<Rect> _getLayoutRects(double width, double height, double spacing) {
    switch (_selectedLayout) {
      case LayoutType.twoVertical:
        final tileHeight = (height - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, width, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, width, tileHeight),
        ];

      case LayoutType.twoHorizontal:
        final tileWidth = (width - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, tileWidth, height),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, height),
        ];

      case LayoutType.fourGrid:
        final tileWidth = (width - spacing) / 2;
        final tileHeight = (height - spacing) / 2;
        return [
          Rect.fromLTWH(0, 0, tileWidth, tileHeight),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            tileHeight + spacing,
            tileWidth,
            tileHeight,
          ),
        ];

      case LayoutType.sixGrid:
        final tileWidth = (width - spacing) / 2;
        final tileHeight = (height - spacing * 2) / 3;
        return [
          Rect.fromLTWH(0, 0, tileWidth, tileHeight),
          Rect.fromLTWH(tileWidth + spacing, 0, tileWidth, tileHeight),
          Rect.fromLTWH(0, tileHeight + spacing, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            tileHeight + spacing,
            tileWidth,
            tileHeight,
          ),
          Rect.fromLTWH(0, (tileHeight + spacing) * 2, tileWidth, tileHeight),
          Rect.fromLTWH(
            tileWidth + spacing,
            (tileHeight + spacing) * 2,
            tileWidth,
            tileHeight,
          ),
        ];
    }
  }

  /// Calculate source rect for cover mode
  Rect _getCoverRect(Size srcSize, Size dstSize) {
    final srcAspect = srcSize.width / srcSize.height;
    final dstAspect = dstSize.width / dstSize.height;

    double cropWidth, cropHeight;
    if (srcAspect > dstAspect) {
      // Source is wider, horizontal crop
      cropHeight = srcSize.height;
      cropWidth = cropHeight * dstAspect;
    } else {
      // Source is taller, vertical crop
      cropWidth = srcSize.width;
      cropHeight = cropWidth / dstAspect;
    }

    final left = (srcSize.width - cropWidth) / 2;
    final top = (srcSize.height - cropHeight) / 2;

    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    HapticFeedback.heavyImpact();

    try {
      await _cameraController!.startVideoRecording();

      if (mounted) {
        setState(() {
          _isVideoRecording = true;
          _isCapturing = true;
          _videoRecordingElapsedMs = 0;
        });

        // Start video duration timer
        _videoRecordingTimer?.cancel();
        _videoRecordingTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (timer) {
            if (!mounted || !_isVideoRecording) {
              timer.cancel();
              return;
            }
            setState(() {
              _videoRecordingElapsedMs += 100;
            });
            // Auto stop when reaching 60 seconds
            if (_videoRecordingElapsedMs >= _videoMaxSeconds * 1000) {
              _stopVideoRecording();
            }
          },
        );
      }
    } catch (e) {
      debugPrint('Video start error: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    // Stop the timer
    _videoRecordingTimer?.cancel();
    _videoRecordingTimer = null;

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      if (mounted) {
        // Normal video - use directly without applying boomerang effect
        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _videoRecordingElapsedMs = 0;
        });

        if (mounted && widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: videoPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            videoPath,
            durationMs: _videoRecordingElapsedMs,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Video stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _videoRecordingElapsedMs = 0;
      });
    }
  }

  // ==================== BOOMERANG RECORDING ====================

  // Flash effect timer (blinks continuously during boomerang recording)
  Timer? _flashTimer;

  /// Start blinking flash effect (during recording)
  void _startFlashEffect() {
    _flashTimer?.cancel();
    // Flash every 200ms
    _flashTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isVideoRecording || !mounted) {
        timer.cancel();
        if (mounted) setState(() => _showFlash = false);
        return;
      }
      // Turn on flash
      setState(() => _showFlash = true);
      // Turn off after 80ms
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _showFlash = false);
      });
    });
  }

  /// Stop flash effect
  void _stopFlashEffect() {
    _flashTimer?.cancel();
    _flashTimer = null;
    if (mounted) setState(() => _showFlash = false);
  }

  void _startBoomerangRecording() async {
    if (_cameraController == null ||
        !_isInitialized ||
        _isCapturing ||
        _isVideoRecording) {
      return;
    }

    HapticFeedback.heavyImpact();

    // First update UI - show user that recording is starting
    setState(() {
      _isCapturing = true;
      _boomerangProgress = 0.0;
      _boomerangElapsedMs = 0;
    });

    try {
      // Start video recording
      await _cameraController!.startVideoRecording();

      // IMPORTANT: Short wait for encoder to stabilize
      await Future.delayed(const Duration(milliseconds: 150));

      debugPrint('Boomerang: Video recording started');

      // Recording started - start flash effect
      _startFlashEffect();

      setState(() {
        _isVideoRecording = true;
      });

      // Progress timer - update every 50ms
      const updateInterval = 50;
      final maxMs = _boomerangMaxSeconds * 1000;

      _boomerangTimer = Timer.periodic(
        const Duration(milliseconds: updateInterval),
        (timer) {
          _boomerangElapsedMs += updateInterval;
          final progress = _boomerangElapsedMs / maxMs;

          if (mounted) {
            setState(() {
              _boomerangProgress = progress.clamp(0.0, 1.0);
            });
          }

          // Max duration reached - auto stop
          if (_boomerangElapsedMs >= maxMs) {
            timer.cancel();
            _stopBoomerangRecording();
          }
        },
      );
    } catch (e) {
      debugPrint('Boomerang start error: $e');
      // Reset state in case of error
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isVideoRecording = false;
        });
      }
    }
  }

  void _stopBoomerangRecording() async {
    _boomerangTimer?.cancel();
    _boomerangTimer = null;

    // Stop flash effect
    _stopFlashEffect();

    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
      _boomerangProgress = 0.0;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      debugPrint('Boomerang: Video recorded, creating boomerang effect...');

      // Calculate recorded duration (seconds)
      final recordedSeconds = _boomerangElapsedMs / 1000.0;

      if (mounted) {
        // Apply native boomerang effect
        final boomerangPath = await _createBoomerangEffect(
          videoPath,
          maxDuration: recordedSeconds.clamp(0.5, _boomerangMaxSeconds.toDouble()),
        );
        final finalPath = boomerangPath ?? videoPath;

        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _boomerangElapsedMs = 0;
        });

        if (mounted && widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: finalPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            finalPath,
            durationMs: _boomerangElapsedMs,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Boomerang stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _boomerangElapsedMs = 0;
      });
    }
  }

  /// Create native boomerang effect
  Future<String?> _createBoomerangEffect(
    String videoPath, {
    double maxDuration = 4.0,
  }) async {
    debugPrint('Creating boomerang effect from video: $videoPath');

    // Get config before async operations
    final config = context.storyEditorConfig;

    try {
      final inputFile = File(videoPath);
      if (!await inputFile.exists()) {
        debugPrint('ERROR: Input file does not exist!');
        return null;
      }

      final inputSize = await inputFile.length();
      debugPrint('Input file size: ${(inputSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // Create native boomerang
      const channel = MethodChannel('story_editor_pro');
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/boomerang_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final result = await channel.invokeMethod<String>('createBoomerang', {
        'inputPath': videoPath,
        'outputPath': outputPath,
        'loopCount': config.boomerangLoopCount,
        'fps': config.boomerangFps,
      });

      if (result != null) {
        final outputFile = File(result);
        if (await outputFile.exists()) {
          final outputSize = await outputFile.length();
          debugPrint('Boomerang created: $result (${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB)');

          // Delete original video
          try {
            await inputFile.delete();
          } catch (e) {
            debugPrint('Failed to delete original video: $e');
          }

          return result;
        }
      }

      debugPrint('ERROR: Boomerang creation failed');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Boomerang error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  // ==================== HANDS-FREE RECORDING ====================

  /// Start hands-free countdown
  void _startHandsFreeCountdown() {
    if (_isVideoRecording || _isCapturing || _isHandsFreeCountingDown) return;

    HapticFeedback.heavyImpact();

    setState(() {
      _isHandsFreeCountingDown = true;
      _handsFreeCountdown = _handsFreeDelaySeconds;
    });

    // Count down every second
    _handsFreeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _handsFreeCountdown--;
      });

      HapticFeedback.lightImpact();

      if (_handsFreeCountdown <= 0) {
        timer.cancel();
        _startHandsFreeRecording();
      }
    });
  }

  /// Cancel hands-free countdown
  void _cancelHandsFreeCountdown() {
    _handsFreeCountdownTimer?.cancel();
    _handsFreeCountdownTimer = null;

    if (mounted) {
      setState(() {
        _isHandsFreeCountingDown = false;
        _handsFreeCountdown = 0;
      });
    }
  }

  /// Start hands-free video recording
  Future<void> _startHandsFreeRecording() async {
    if (_cameraController == null || !_isInitialized) return;

    HapticFeedback.heavyImpact();

    try {
      await _cameraController!.startVideoRecording();

      setState(() {
        _isHandsFreeCountingDown = false;
        _isVideoRecording = true;
        _isCapturing = true;
        _handsFreeRecordingElapsed = 0;
      });

      // Update recording duration every second
      _handsFreeRecordingTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _handsFreeRecordingElapsed++;
        });

        // Auto stop when reaching 60 seconds
        if (_handsFreeRecordingElapsed >= _handsFreeMaxRecordingSeconds) {
          timer.cancel();
          _stopHandsFreeRecording();
        }
      });
    } catch (e) {
      debugPrint('Hands-free recording start error: $e');
      setState(() {
        _isHandsFreeCountingDown = false;
      });
    }
  }

  /// Stop hands-free video recording
  Future<void> _stopHandsFreeRecording() async {
    _handsFreeRecordingTimer?.cancel();
    _handsFreeRecordingTimer = null;

    if (_cameraController == null || !_isVideoRecording) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isVideoRecording = false;
      _isProcessingVideo = true;
    });

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      final videoPath = file.path;

      if (mounted) {
        setState(() {
          _isProcessingVideo = false;
          _isCapturing = false;
          _handsFreeRecordingElapsed = 0;
        });

        // Navigate to video editor
        if (widget.showEditor) {
          await Navigator.push<Map<String, dynamic>?>(
            context,
            MaterialPageRoute(
              builder: (context) => StoryEditorScreen(
                imagePath: videoPath,
                mediaType: MediaType.video,
                primaryColor: widget.primaryColor,
                closeFriendsList: widget.closeFriendsList,
                onShare: widget.onStoryShare,
              ),
            ),
          );
          // onStoryShare callback is called from StoryEditorScreen
        } else {
          // No editor - call onStoryShare directly
          final result = await StoryResult.fromFile(
            videoPath,
            durationMs: _handsFreeRecordingElapsed * 1000,
          );
          widget.onStoryShare?.call(
            StoryShareResult(
              story: result,
              shareTarget: ShareTarget.story,
              selectedFriends: [],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Hands-free recording stop error: $e');
      setState(() {
        _isProcessingVideo = false;
        _isCapturing = false;
        _handsFreeRecordingElapsed = 0;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isVideoRecording) return;

    HapticFeedback.lightImpact();

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _setupCameraController(_cameras[_currentCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isInitialized) return;

    HapticFeedback.lightImpact();

    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.always;
      } else if (_flashMode == FlashMode.always) {
        _flashMode = FlashMode.auto;
      } else {
        _flashMode = FlashMode.off;
      }
    });

    await _cameraController!.setFlashMode(_flashMode);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_cameraController == null || !_isInitialized) return;

    final newZoom = (_baseZoomLevel * details.scale).clamp(_minZoom, _maxZoom);
    if (newZoom != _zoomLevel) {
      setState(() => _zoomLevel = newZoom);
      _cameraController!.setZoomLevel(_zoomLevel);
    }
  }

  Widget get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
      case FlashMode.auto:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            Colors.yellowAccent,
            BlendMode.srcIn,
          ),
        );
      default:
        return SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/flash-off.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // Status bar area - black
            Container(height: statusBarHeight, color: Colors.black),
            // Remaining area
            Expanded(
              child: _isLayoutMode ? _buildLayoutModeBody() : _buildNormalModeBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// Separate body for layout mode
  Widget _buildLayoutModeBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layout preview - positioned above the bottom bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: Container(color: Colors.black, child: _buildLayoutGrid()),
            ),
          ),
        ),
        // UI is always visible
        _buildTopControlsRow(),
        _buildSideTools(),
        // Pending text overlay indicator
        if (_pendingTextOverlay != null) _buildPendingTextIndicator(),
        _buildCenterCaptureButton(),
        _buildBottomBar(),
        if (_zoomLevel > _minZoom) _buildZoomIndicator(),
        // White flash effect
        if (_showFlash)
          AnimatedOpacity(
            opacity: _showFlash ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 100),
            child: Container(color: Colors.white.withValues(alpha: 0.1)),
          ),
      ],
    );
  }

  /// Pending text overlay indicator - shows user that text was created
  /// from Create Mode and will be added after photo is taken
  Widget _buildPendingTextIndicator() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            // Cancel
            setState(() {
              _pendingTextOverlay = null;
            });
            HapticFeedback.selectionClick();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: _pendingTextOverlay?.backgroundGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _pendingTextOverlay?.text ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.close, color: Colors.white70, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Body for normal mode - fullscreen camera
  Widget _buildNormalModeBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Column(
      children: [
        // Camera preview area (top controls + camera + capture button)
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview - only apply ClipRRect to this
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                child: _buildFullscreenCameraPreview(),
              ),
              // Top controls (X, Flash, Settings)
              _buildTopControlsRow(),
              // Right side icons (Boomerang, Text, Collage, HandsFree)
              _buildSideToolsColumn(),
              // Capture button - centered at bottom
              _buildCaptureButtonArea(),
              // Pending text overlay indicator
              if (_pendingTextOverlay != null) _buildPendingTextIndicator(),
              // Zoom indicator
              if (_zoomLevel > _minZoom) _buildZoomIndicator(),
              // Hands-free countdown overlay
              if (_isHandsFreeCountingDown) _buildHandsFreeCountdownOverlay(),
              // White flash effect
              if (_showFlash)
                AnimatedOpacity(
                  opacity: _showFlash ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 100),
                  child: Container(color: Colors.white.withValues(alpha: 0.1)),
                ),
            ],
          ),
        ),
        // Bottom bar
        _buildBottomBarRow(),
      ],
    );
  }

  /// Hands-free countdown overlay - shows large number
  Widget _buildHandsFreeCountdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Large countdown number
              TweenAnimationBuilder<double>(
                key: ValueKey(_handsFreeCountdown),
                tween: Tween(begin: 1.5, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Text(
                      '$_handsFreeCountdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // Cancel button
              GestureDetector(
                onTap: _cancelHandsFreeCountdown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white54),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hands-free recording duration overlay
  /// Create grid according to selected layout type - fullscreen without spacing
  Widget _buildLayoutGrid() {
    switch (_selectedLayout) {
      case LayoutType.twoVertical:
        return Column(
          children: [
            Expanded(child: _buildLayoutTile(0)),
            Expanded(child: _buildLayoutTile(1)),
          ],
        );

      case LayoutType.twoHorizontal:
        return Row(
          children: [
            Expanded(child: _buildLayoutTile(0)),
            Expanded(child: _buildLayoutTile(1)),
          ],
        );

      case LayoutType.fourGrid:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(0)),
                  Expanded(child: _buildLayoutTile(1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(2)),
                  Expanded(child: _buildLayoutTile(3)),
                ],
              ),
            ),
          ],
        );

      case LayoutType.sixGrid:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(0)),
                  Expanded(child: _buildLayoutTile(1)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(2)),
                  Expanded(child: _buildLayoutTile(3)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildLayoutTile(4)),
                  Expanded(child: _buildLayoutTile(5)),
                ],
              ),
            ),
          ],
        );
    }
  }

  /// Single layout tile - camera preview in active one, photo in captured ones
  /// Fullscreen, without spacing and corners design
  Widget _buildLayoutTile(int index) {
    final isActive = index == _activeLayoutIndex;
    final File? capturedPhoto = index < _capturedLayoutPhotos.length
        ? _capturedLayoutPhotos[index]
        : null;

    // Tiles cannot be clicked during layout processing
    return IgnorePointer(
      ignoring: _isLayoutProcessing,
      child: GestureDetector(
        onTap: () {
          // Make this tile active when clicked (if not yet captured)
          if (capturedPhoto == null) {
            HapticFeedback.selectionClick();
            setState(() {
              _activeLayoutIndex = index;
            });
          } else {
            // Delete option when clicked on captured photo
            _showDeletePhotoDialog(index);
          }
        },
        onLongPress: () {
          // Select image from gallery on long press
          HapticFeedback.mediumImpact();
          _pickImageForLayoutTile(index);
        },
      child: Container(
        // Separate with thin white line
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.2),
            width: isActive ? 2 : 0.5,
          ),
        ),
        child: capturedPhoto != null
            // Captured photo
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(capturedPhoto, fit: BoxFit.cover),
                  // Delete icon - hide during processing
                  if (!_isLayoutProcessing)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  // Index indicator - hide during processing
                  if (!_isLayoutProcessing)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            // Active tile - camera preview
            : isActive
            ? _buildTileCameraPreview(index)
            // Pending tile
            : Container(
                color: Colors.grey.shade900,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      ),
    );
  }

  /// Camera preview for active tile - fullscreen
  Widget _buildTileCameraPreview(int index) {
    if (_cameraController == null || !_isInitialized) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview (cropped, fullscreen)
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1920,
                height: _cameraController!.value.previewSize?.width ?? 1080,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
        ),
        // Index and "CAPTURE" text
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Capture: ${index + 1}/${_selectedLayout.photoCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Delete captured photo dialog
  void _showDeletePhotoDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Delete Photo',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Do you want to delete this photo?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _capturedLayoutPhotos[index] = null;
                _activeLayoutIndex = index;
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenCameraPreview() {
    if (_cameraController == null || !_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use positioned area dimensions (excluding bottom bar)
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;
          final availableAspectRatio = availableWidth / availableHeight;
          final cameraAspectRatio = _cameraController!.value.aspectRatio;

          var scale = availableAspectRatio * cameraAspectRatio;
          if (scale < 1) scale = 1 / scale;

          return ClipRect(
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Center(child: CameraPreview(_cameraController!)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: Colors.white54,
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'We need camera access to create stories.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _initializeCamera,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor ?? Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Grant Permission',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top controls - status bar already separate, no SafeArea
  Widget _buildTopControlsRow() {
    // Hide top bar during all recording and processing states
    final shouldHide = _isLayoutProcessing || _isHandsFreeCountingDown ||
        _isVideoRecording || _isProcessingVideo;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: shouldHide ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: shouldHide,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIconButton(
                  iconWidget: SvgPicture.asset(
                    'packages/story_editor_pro/assets/icons/xmark.svg',
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  onTap: () {
                    // If in special modes only close the mode, otherwise close the screen
                    if (_isLayoutMode) {
                      setState(() {
                        _isLayoutMode = false;
                        _showLayoutSelector = false;
                        _capturedLayoutPhotos = [];
                        _activeLayoutIndex = 0;
                      });
                    } else if (_isBoomerangMode) {
                      setState(() {
                        _isBoomerangMode = false;
                      });
                    } else if (_isHandsFreeMode) {
                      setState(() {
                        _isHandsFreeMode = false;
                        _showHandsFreeSelector = false;
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                _buildIconButton(iconWidget: _flashIcon, onTap: _toggleFlash),
                _buildIconButton(
                  iconWidget: SvgPicture.asset(
                    'packages/story_editor_pro/assets/icons/settings.svg',
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CameraSettingsScreen(),
                      ),
                    );
                    if (mounted) {
                      _loadSettings();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Capture button area - positioned at bottom in Stack
  Widget _buildCaptureButtonArea() {
    Widget captureButton;
    if (_isBoomerangMode || _isProcessingVideo) {
      captureButton = _buildBoomerangCaptureButton();
    } else if (_isHandsFreeMode) {
      captureButton = _buildHandsFreeCaptureButton();
    } else {
      captureButton = _buildNormalCaptureButton();
    }

    final config = context.storyEditorConfig;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomOffset = screenHeight < config.smallScreenBreakpoint ? 10.0 : 20.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: Center(child: captureButton),
    );
  }

  /// Old method - still used for Layout mode
  Widget _buildCenterCaptureButton() {
    // Bottom bar height + half of button + some spacing
    final bottomBarHeight =
        16 + 44 + MediaQuery.of(context).viewPadding.bottom + 16;
    final buttonBottomOffset =
        bottomBarHeight + 20; // 20px spacing above bottom bar

    // Special button in boomerang mode
    if (_isBoomerangMode || _isProcessingVideo) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: buttonBottomOffset,
        child: Center(child: _buildBoomerangCaptureButton()),
      );
    }

    // Special button in hands-free mode
    if (_isHandsFreeMode) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: buttonBottomOffset,
        child: Center(child: _buildHandsFreeCaptureButton()),
      );
    }

    // Normal mode - Custom video/photo button
    return Positioned(
      left: 0,
      right: 0,
      bottom: buttonBottomOffset,
      child: Center(child: _buildNormalCaptureButton()),
    );
  }

  /// Photo/video button for normal mode - with duration indicator and progress
  Widget _buildNormalCaptureButton() {
    final config = context.storyEditorConfig;
    final screenHeight = MediaQuery.of(context).size.height;
    final double size = screenHeight < config.smallScreenBreakpoint
        ? config.shutterButtonSizeSmall
        : config.shutterButtonSizeLarge;
    final double strokeWidth = screenHeight < config.smallScreenBreakpoint ? 4 : 6;
    final Color recordingColor = config.recordingIndicatorColor;

    // Video recording progress (0.0 - 1.0)
    final videoProgress = _videoRecordingElapsedMs / (_videoMaxSeconds * 1000);

    // Duration format: 00:44
    final seconds = (_videoRecordingElapsedMs / 1000).floor();
    final timeString = '00:${seconds.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        // Short tap - take photo
        if (!_isVideoRecording && !_isCapturing) {
          _takePicture();
        }
      },
      onLongPressStart: (details) {
        // Long press - start video recording
        if (!_isVideoRecording && !_isCapturing) {
          _longPressStartY = details.globalPosition.dy;
          _longPressZoomStart = _zoomLevel;
          _startVideoRecording();
        }
      },
      onLongPressMoveUpdate: (details) {
        // Swipe up = zoom in, swipe down = zoom out
        if (_isVideoRecording && _cameraController != null) {
          final deltaY = _longPressStartY - details.globalPosition.dy;
          // Every 100 pixels = 1x zoom change
          final zoomDelta = deltaY / 100.0;
          final newZoom = (_longPressZoomStart + zoomDelta).clamp(_minZoom, _maxZoom);
          if (newZoom != _zoomLevel) {
            setState(() => _zoomLevel = newZoom);
            _cameraController!.setZoomLevel(_zoomLevel);
          }
        }
      },
      onLongPressEnd: (_) {
        // Finger lifted - stop video recording
        if (_isVideoRecording) {
          _stopVideoRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration indicator - above button (only during recording)
          if (_isVideoRecording)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                timeString,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Main button
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring - shows progress during video recording
                SizedBox(
                  width: size,
                  height: size,
                  child: _isVideoRecording
                      ? CustomPaint(
                          painter: _VideoProgressPainter(
                            progress: videoProgress,
                            strokeWidth: strokeWidth,
                            progressColor: recordingColor,
                            backgroundColor: Colors.white,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                ),

                // Inner circle - shrinks and turns red during video recording
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isVideoRecording ? 35 : 70,
                  height: _isVideoRecording ? 35 : 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isVideoRecording ? recordingColor : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Special capture button for hands-free - same appearance as video recording
  Widget _buildHandsFreeCaptureButton() {
    final config = context.storyEditorConfig;
    final double size = config.shutterButtonSizeLarge;
    const double strokeWidth = 6;
    final Color recordingColor = config.recordingIndicatorColor;

    // Video recording progress (0.0 - 1.0)
    final videoProgress =
        _handsFreeRecordingElapsed / _handsFreeMaxRecordingSeconds;

    // Duration format: 00:44
    final timeString =
        '00:${_handsFreeRecordingElapsed.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        if (!_isVideoRecording && !_isCapturing && !_isHandsFreeCountingDown) {
          _startHandsFreeCountdown();
        } else if (_isVideoRecording) {
          _stopHandsFreeRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration indicator - above button (during recording or start info)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isVideoRecording
                  ? timeString
                  : 'Start after ${_handsFreeDelaySeconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Main button
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring - shows progress during video recording
                SizedBox(
                  width: size,
                  height: size,
                  child: _isVideoRecording
                      ? CustomPaint(
                          painter: _VideoProgressPainter(
                            progress: videoProgress,
                            strokeWidth: strokeWidth,
                            progressColor: recordingColor,
                            backgroundColor: Colors.white,
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                ),

                // Inner circle - shrinks and turns red during video recording
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isVideoRecording ? 35 : 70,
                  height: _isVideoRecording ? 35 : 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isVideoRecording ? recordingColor : Colors.white,
                  ),
                  child: _isVideoRecording
                      ? null
                      : Center(
                          child: SvgPicture.asset(
                            'packages/story_editor_pro/assets/icons/hand-free.svg',
                            width: 32,
                            height: 32,
                            colorFilter: const ColorFilter.mode(
                              Colors.black54,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Special capture button for boomerang - with circular progress indicator
  /// Instagram Boomerang colors: orange -> pink gradient
  Widget _buildBoomerangCaptureButton() {
    const double size = 90;
    const double strokeWidth = 6;

    // Instagram Boomerang gradient colors
    const boomerangGradient = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color(0xFFF77737), // Orange
        Color(0xFFE1306C), // Pink
        Color(0xFFC13584), // Dark pink
      ],
    );

    return GestureDetector(
      onLongPressStart: (_) {
        if (!_isVideoRecording && !_isCapturing) {
          _startBoomerangRecording();
        }
      },
      onLongPressEnd: (_) {
        if (_isVideoRecording) {
          _stopBoomerangRecording();
        }
      },
      onLongPressCancel: () {
        if (_isVideoRecording) {
          _stopBoomerangRecording();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top text area - according to recording or processing state
          Visibility(
            visible: _isVideoRecording || _isProcessingVideo,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (_isVideoRecording || _isProcessingVideo)
                    ? Colors.black54
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isProcessingVideo
                    ? (_isLayoutMode
                          ? 'Processing image...'
                          : 'Processing video...')
                    : '${(_boomerangElapsedMs / 1000).toStringAsFixed(1)}s / ${_boomerangMaxSeconds}s',
                style: TextStyle(
                  color: (_isVideoRecording || _isProcessingVideo)
                      ? Colors.white
                      : Colors.transparent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Main button area
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring - always visible (including processing)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isVideoRecording || _isProcessingVideo
                          ? 1.0
                          : (_isBoomerangMode ? _pulseAnimation.value : 1.0),
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: _isVideoRecording
                            // During recording: ring filling with progress
                            ? CustomPaint(
                                painter: _GradientCircularProgressPainter(
                                  progress: _boomerangProgress,
                                  strokeWidth: strokeWidth,
                                  gradient: boomerangGradient,
                                  backgroundColor: Colors.white,
                                ),
                              )
                            // Normal and Processing: white border
                            : Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),

                // Inner circle - gradient or processing circular
                _isProcessingVideo
                    ? const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          color: Colors.white,
                        ),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _isVideoRecording ? 35 : 70,
                        height: _isVideoRecording ? 35 : 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: boomerangGradient,
                        ),
                        child: _isVideoRecording
                            ? null
                            : Center(
                                child: SvgPicture.asset(
                                  'packages/story_editor_pro/assets/icons/infinite.svg',
                                  width: 28,
                                  height: 28,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom bar - for Column structure (not Positioned)
  Widget _buildBottomBarRow() {
    // Hide buttons during recording or processing
    final shouldHide = _isProcessingVideo || _isVideoRecording || _isLayoutProcessing || _isHandsFreeCountingDown;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewPadding.bottom + 16,
      ),
      decoration: const BoxDecoration(color: Colors.black),
      child: AnimatedOpacity(
        opacity: shouldHide ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: shouldHide,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildGalleryButton(),
              if (!_isLayoutMode) _buildModeSelector(),
              if (_isLayoutMode) const SizedBox(width: 40),
              _buildIconButton(
                iconWidget: SvgPicture.asset(
                  'packages/story_editor_pro/assets/icons/refresh-double.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
                onTap: _switchCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Old _buildBottomBar - still used for Layout mode
  Widget _buildBottomBar() {
    // Hide buttons during recording or processing
    final shouldHide = _isProcessingVideo || _isVideoRecording || _isLayoutProcessing || _isHandsFreeCountingDown;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewPadding.bottom + 16,
        ),
        decoration: const BoxDecoration(color: Colors.black),
        child: AnimatedOpacity(
          opacity: shouldHide ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: shouldHide,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildGalleryButton(),
                // Hide mode selector in layout mode
                if (!_isLayoutMode) _buildModeSelector(),
                // SizedBox for spacing in layout mode
                if (_isLayoutMode) const SizedBox(width: 40),
                _buildIconButton(
                  iconWidget: SvgPicture.asset(
                    'packages/story_editor_pro/assets/icons/refresh-double.svg',
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  onTap: _switchCamera,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryButton() {
    final hasThumbnail = _hasGalleryPermission && _lastGalleryThumbnail != null;

    // 30% reduced sizes: 56->40, 48->34, 8->6, 2->1.5, 24->17, 20->14, 10->7
    return GestureDetector(
      onTap: () {
        // Select gallery image for active tile in layout mode
        if (_isLayoutMode) {
          _pickImageForLayoutTile(_activeLayoutIndex);
        } else {
          _openGallery();
        }
      },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              // Main gallery box - with white border
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 1.5),
                  color: hasThumbnail ? null : Colors.white10,
                ),
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          _lastGalleryThumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: SvgPicture.asset(
                                'packages/story_editor_pro/assets/icons/media-image-folder.svg',
                                width: 17,
                                height: 17,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : Center(
                        child: SvgPicture.asset(
                          'packages/story_editor_pro/assets/icons/media-image-folder.svg',
                          width: 17,
                          height: 17,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
              ),
              // Plus icon at bottom right corner
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'packages/story_editor_pro/assets/icons/plus.svg',
                      width: 7,
                      height: 7,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
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

  Widget _buildModeSelector() {
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          'Story',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    IconData? icon,
    Widget? iconWidget,
    VoidCallback? onTap,
    double size = 44,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: Center(
          child: iconWidget ?? Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildZoomIndicator() {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_zoomLevel.toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  /// Tool buttons on the right (or left) side - returns as Positioned
  /// Old _buildSideTools - still used for Layout mode
  Widget _buildSideTools() {
    // Hide during recording or processing
    final shouldHide = _isProcessingVideo || _isLayoutProcessing || _isHandsFreeCountingDown ||
        _isVideoRecording;
    return Positioned(
      right: _toolsOnLeft ? null : 16,
      left: _toolsOnLeft ? 16 : null,
      top: 0,
      bottom: 120,
      child: AnimatedOpacity(
        opacity: shouldHide ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: shouldHide,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBoomerangButton(),
                const SizedBox(height: 16),
                _buildCreateModeButton(),
                const SizedBox(height: 16),
                _buildCollageButton(),
                const SizedBox(height: 16),
                _buildHandsFreeButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tool buttons on the right side - for Column structure
  Widget _buildSideToolsColumn() {
    final config = context.storyEditorConfig;
    final screenHeight = MediaQuery.of(context).size.height;
    // Less spacing on small screens, more on large screens
    final bottomOffset = screenHeight * 0.15; // 15% of screen
    final itemSpacing = screenHeight < config.smallScreenBreakpoint ? 8.0 : 16.0;

    // Hide during recording or processing
    final shouldHide = _isProcessingVideo || _isLayoutProcessing || _isHandsFreeCountingDown ||
        _isVideoRecording;
    return Positioned(
      right: _toolsOnLeft ? null : 16,
      left: _toolsOnLeft ? 16 : null,
      top: 0,
      bottom: bottomOffset,
      child: AnimatedOpacity(
        opacity: shouldHide ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: shouldHide,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBoomerangButton(),
                SizedBox(height: itemSpacing),
                _buildCreateModeButton(),
                SizedBox(height: itemSpacing),
                _buildCollageButton(),
                SizedBox(height: itemSpacing),
                _buildHandsFreeButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Boomerang button
  Widget _buildBoomerangButton() {
    final config = context.storyEditorConfig;
    // Instagram Boomerang gradient - uses config colors
    final boomerangGradient = LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: config.boomerangGradientColors,
    );

    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        final wasBoomerangMode = _isBoomerangMode;
        setState(() {
          _isBoomerangMode = !_isBoomerangMode;
          // Close other modes if boomerang is opened
          if (_isBoomerangMode) {
            _isLayoutMode = false;
            _showLayoutSelector = false;
            _isHandsFreeMode = false;
            _showHandsFreeSelector = false;
          }
        });

        // Pre-warm encoder when switching to boomerang mode
        // This prevents delay when recording starts
        if (!wasBoomerangMode && _isBoomerangMode && _cameraController != null) {
          try {
            debugPrint('Boomerang: Pre-warming encoder...');
            await _cameraController!.startVideoRecording();
            await Future.delayed(const Duration(milliseconds: 100));
            await _cameraController!.stopVideoRecording();
            debugPrint('Boomerang: Encoder pre-warmed');
          } catch (e) {
            debugPrint('Boomerang pre-warm error: $e');
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: _isBoomerangMode
            ? BoxDecoration(shape: BoxShape.circle, gradient: boomerangGradient)
            : BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
        child: SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/infinite.svg',
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }

  /// Create Mode (Gradient Text Editor) button
  Widget _buildCreateModeButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        // Open Gradient Text Editor
        await openGradientTextEditor(
          context,
          onComplete: (text, gradient) async {
            debugPrint('Create Mode: onComplete called with text: $text');

            // Create only gradient background image (without text)
            final bgImagePath = await _createGradientBackground(gradient);

            if (bgImagePath != null && mounted) {
              await Navigator.push<Map<String, dynamic>?>(
                context,
                MaterialPageRoute(
                  builder: (ctx) => StoryEditorScreen(
                    imagePath: bgImagePath,
                    primaryColor: widget.primaryColor,
                    closeFriendsList: widget.closeFriendsList,
                    onShare: widget.onStoryShare,
                    // Send text as TextOverlay (movable, editable)
                    // offset: Offset.zero - will be auto centered on editor side
                    initialTextOverlay: TextOverlay(
                      text: text,
                      color: Colors.white,
                      fontSize: 32,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      offset: Offset.zero,
                    ),
                  ),
                ),
              );
              // onStoryShare callback is called from StoryEditorScreen
            }
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: const Icon(Icons.text_fields, color: Colors.white, size: 24),
      ),
    );
  }

  /// Hands-free button - expands downward to show duration options when clicked
  Widget _buildHandsFreeButton() {
    // Duration options (seconds)
    const List<int> delayOptions = [3, 5, 10, 15];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: _showHandsFreeSelector
            ? BorderRadius.circular(24)
            : BorderRadius.circular(100),
        color: _isHandsFreeMode
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main hands-free button (always visible)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_isHandsFreeMode) {
                  // Open hands-free mode and selector
                  _isHandsFreeMode = true;
                  _showHandsFreeSelector = true;
                  _isBoomerangMode = false;
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                } else {
                  // Close everything when clicked while mode is active (return to normal mode)
                  _isHandsFreeMode = false;
                  _showHandsFreeSelector = false;
                }
              });
            },
            child: SvgPicture.asset(
              'packages/story_editor_pro/assets/icons/hand-free.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),

          // Duration options (expands downward)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _showHandsFreeSelector
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      ...delayOptions.map((seconds) {
                        final isSelected = _handsFreeDelaySeconds == seconds;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _handsFreeDelaySeconds = seconds;
                            });
                            // Just select duration, will start when button is pressed
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white60,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$seconds',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Collage button - expands downward to show layout options when clicked
  Widget _buildCollageButton() {
    // Layout SVG icon paths
    const Map<LayoutType, String> layoutIcons = {
      LayoutType.twoVertical:
          'packages/story_editor_pro/assets/icons/collage-frame-two-horizontal.svg',
      LayoutType.twoHorizontal:
          'packages/story_editor_pro/assets/icons/collage-frame-two-vertical.svg',
      LayoutType.fourGrid:
          'packages/story_editor_pro/assets/icons/collage-frame-four.svg',
      LayoutType.sixGrid:
          'packages/story_editor_pro/assets/icons/collage-frame-six.svg',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: _showLayoutSelector
            ? BorderRadius.circular(24)
            : BorderRadius.circular(100),
        color: _isLayoutMode
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main collage button (always visible)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_isLayoutMode) {
                  // Open layout mode and selector
                  _isLayoutMode = true;
                  _showLayoutSelector = true;
                  _isBoomerangMode = false;
                  _isHandsFreeMode = false;
                  _showHandsFreeSelector = false;
                  _capturedLayoutPhotos = List.filled(
                    _selectedLayout.photoCount,
                    null,
                  );
                  _activeLayoutIndex = 0;
                } else if (_showLayoutSelector) {
                  // Close mode when clicked while selector is open
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                  _capturedLayoutPhotos = [];
                  _activeLayoutIndex = 0;
                } else {
                  // Open selector when clicked while selector is closed
                  _showLayoutSelector = true;
                }
              });
            },
            onLongPress: () {
              // Close layout mode on long press
              if (_isLayoutMode) {
                HapticFeedback.mediumImpact();
                setState(() {
                  _isLayoutMode = false;
                  _showLayoutSelector = false;
                  _capturedLayoutPhotos = [];
                  _activeLayoutIndex = 0;
                });
              }
            },
            child: SvgPicture.asset(
              'packages/story_editor_pro/assets/icons/collage-frame.svg',
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),

          // Layout options (expands downward)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _showLayoutSelector
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      ...LayoutType.values.map((layout) {
                        final isSelected = _selectedLayout == layout;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedLayout = layout;
                              _capturedLayoutPhotos = List.filled(
                                layout.photoCount,
                                null,
                              );
                              _activeLayoutIndex = 0;
                            });
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: SvgPicture.asset(
                              layoutIcons[layout]!,
                              width: 24,
                              height: 24,
                              colorFilter: ColorFilter.mode(
                                isSelected ? Colors.white : Colors.white60,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that draws circular progress indicator with gradient
class _GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Gradient gradient;
  final Color backgroundColor;

  _GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.gradient,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle (white, unfilled part)
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw gradient circle if progress exists
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // -90 degrees (start from top), draw up to progress
      const startAngle = -3.14159 / 2; // -90 degrees (top)
      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(_GradientCircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Circular progress painter for video recording
class _VideoProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;

  _VideoProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle (white, unfilled part)
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw red circle if progress exists
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);

      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // -90 degrees (start from top), draw up to progress
      const startAngle = -3.14159 / 2; // -90 degrees (top)
      final sweepAngle = 2 * 3.14159 * progress;

      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(_VideoProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Gallery picker page
class _GalleryPickerPage extends StatefulWidget {
  final AssetPathEntity album;
  final int totalCount;

  const _GalleryPickerPage({required this.album, required this.totalCount});

  @override
  State<_GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<_GalleryPickerPage> {
  final List<AssetEntity> _assets = [];
  bool _isLoading = true;
  int _currentPage = 0;
  int _pageSize = 50; // Will be updated from config in initState

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageSize = context.storyEditorConfig.galleryPageSize;
  }

  Future<void> _loadAssets() async {
    final pageSize = _pageSize;
    final assets = await widget.album.getAssetListPaged(
      page: _currentPage,
      size: pageSize,
    );

    if (mounted) {
      setState(() {
        _assets.addAll(assets);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _assets.length >= widget.totalCount) return;

    setState(() => _isLoading = true);
    _currentPage++;

    final pageSize = context.storyEditorConfig.galleryPageSize;
    final assets = await widget.album.getAssetListPaged(
      page: _currentPage,
      size: pageSize,
    );

    if (mounted) {
      setState(() {
        _assets.addAll(assets);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Gallery'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading && _assets.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.extentAfter < 200) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _assets.length,
                itemBuilder: (context, index) {
                  final asset = _assets[index];
                  return _GalleryThumbnail(
                    asset: asset,
                    onTap: () => Navigator.pop(context, asset),
                  );
                },
              ),
            ),
    );
  }
}

/// Gallery thumbnail widget
class _GalleryThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _GalleryThumbnail({required this.asset, required this.onTap});

  @override
  State<_GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends State<_GalleryThumbnail> {
  Uint8List? _thumbData;
  bool _loadFailed = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final config = context.storyEditorConfig;
      final data = await widget.asset.thumbnailDataWithSize(
        ThumbnailSize(config.thumbnailSize, config.thumbnailSize),
        quality: config.thumbnailQuality,
      );

      if (mounted && data != null) {
        setState(() {
          _thumbData = data;
          _loadFailed = false;
        });
      } else if (mounted && _retryCount < _maxRetries) {
        // Could not get thumbnail, wait a bit and retry
        _retryCount++;
        await Future.delayed(Duration(milliseconds: 500 * _retryCount));
        if (mounted) {
          _loadThumbnail();
        }
      } else if (mounted) {
        setState(() => _loadFailed = true);
      }
    } catch (e) {
      debugPrint('Thumbnail load error: $e');
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          _thumbData != null
              ? Image.memory(_thumbData!, fit: BoxFit.cover)
              : Container(
                  color: Colors.grey.shade900,
                  child: Center(
                    child: _loadFailed
                        ? const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 24,
                          )
                        : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                ),

          // Show duration if video
          if (widget.asset.type == AssetType.video)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(widget.asset.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
