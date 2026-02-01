import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'gradient_text_editor.dart';
import 'models/story_result.dart';
import 'config/story_editor_config.dart';

/// Media type - photo or video
enum MediaType {
  image,
  video,
}

/// Brush types
enum BrushType {
  normal,     // Normal straight line
  arrow,      // Arrow tip
  marker,     // Broken/marker tip
  glow,       // Glow effect (neon)
  eraser,     // Eraser
  chalk,      // Chalk
}

class StoryEditorScreen extends StatefulWidget {
  /// Path to media file (photo or video)
  final String mediaPath;

  /// imagePath alias for backwards compatibility
  String get imagePath => mediaPath;

  /// Media type - automatically detected or can be specified manually
  final MediaType? mediaType;

  final Color? primaryColor;

  /// Is it selected from gallery? (true: fitWidth, false: cover)
  final bool isFromGallery;

  /// Initial text overlay from Create Mode
  final TextOverlay? initialTextOverlay;

  /// Movable image overlay from Create Mode
  final ImageOverlay? initialImageOverlay;

  /// List of close friends to show in the share bottomsheet
  /// If not empty, close friends sharing option will be enabled
  /// If empty, the share bottomsheet will be skipped
  final List<CloseFriend> closeFriendsList;

  /// Returns true if close friends list is not empty
  bool get closeFriendsEnabled => closeFriendsList.isNotEmpty;

  /// User's profile image URL for "Your Story" section
  final String? userProfileImageUrl;

  /// Callback when story is shared (returns StoryShareResult with file and selected friends)
  final Function(StoryShareResult result)? onShare;

  const StoryEditorScreen({
    super.key,
    required String imagePath,
    this.mediaType,
    this.primaryColor,
    this.isFromGallery = false,
    this.initialTextOverlay,
    this.initialImageOverlay,
    this.closeFriendsList = const [],
    this.userProfileImageUrl,
    this.onShare,
  }) : mediaPath = imagePath;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  final List<TextOverlay> _textOverlays = [];
  final List<DrawingPath> _drawings = [];
  final List<ImageOverlay> _imageOverlays = [];

  // Video player
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  late MediaType _mediaType;

  // Close friends selection
  final Set<CloseFriend> _selectedCloseFriends = {};

  // Drag-to-delete (trash bin)
  bool _isDraggingOverlay = false;
  bool _isOverTrash = false;
  int? _draggingOverlayIndex;
  String? _draggingOverlayType; // 'text' or 'image'

  @override
  void initState() {
    super.initState();
    // Determine media type
    _mediaType = widget.mediaType ?? _detectMediaType(widget.mediaPath);

    // If video, start the player
    if (_mediaType == MediaType.video) {
      _initVideoPlayer();
    }

    // Add initial overlay from Create Mode (position at center in first frame)
    if (widget.initialTextOverlay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addInitialTextOverlayCentered(widget.initialTextOverlay!);
      });
    }
    // Add initial image overlay from Create Mode
    if (widget.initialImageOverlay != null) {
      _imageOverlays.add(widget.initialImageOverlay!);
    }

    // Select all close friends by default
    if (widget.closeFriendsEnabled) {
      _selectedCloseFriends.addAll(widget.closeFriendsList);
    }
  }

  /// Add initial text overlay positioned at the exact center of the screen
  void _addInitialTextOverlayCentered(TextOverlay overlay) {
    if (!mounted) return;

    final screenSize = MediaQuery.of(context).size;
    final viewPadding = MediaQuery.of(context).viewPadding;

    // Calculate text size
    final textStyle = overlay.toTextStyle();
    final maxTextWidth = screenSize.width - 80;

    final textPainter = TextPainter(
      text: TextSpan(text: overlay.text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: maxTextWidth);

    // Widget size - no padding (when backgroundColor is null)
    final totalWidth = textPainter.width;
    final totalHeight = textPainter.height;

    // Calculate available area
    final topOffset = viewPadding.top + 60;
    final bottomOffset = viewPadding.bottom + 100;
    final availableHeight = screenSize.height - topOffset - bottomOffset;

    // Position at exact center
    final centerX = (screenSize.width - totalWidth) / 2;
    final centerY = topOffset + (availableHeight - totalHeight) / 2;

    setState(() {
      _textOverlays.add(overlay.copyWith(
        offset: Offset(centerX, centerY),
      ));
    });
  }

  /// Detect media type based on file extension
  MediaType _detectMediaType(String path) {
    final ext = path.toLowerCase().split('.').last;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'].contains(ext)) {
      return MediaType.video;
    }
    return MediaType.image;
  }

  /// Initialize video player
  Future<void> _initVideoPlayer() async {
    _videoController = VideoPlayerController.file(File(widget.mediaPath));
    try {
      await _videoController!.initialize();
      _videoController!.setLooping(true);
      _videoController!.play();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Video init error: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  bool _isDrawing = false;
  bool _isTextEditing = false;
  bool _isSliding = false; // Is slider being dragged
  Color _currentColor = Colors.white;
  double _brushSize = 5.0;
  BrushType _currentBrushType = BrushType.normal;
  DrawingPath? _currentPath;
  int _drawingCountBeforeSession = 0; // Drawing count before entering drawing mode

  // State variables for text overlay dragging and scaling
  int? _draggingTextIndex;
  Offset? _textDragStartOffset;
  Offset? _textDragStartPosition;
  double? _textScaleStart;

  // State variables for background image zoom/pan
  double _bgImageScale = 1.0;
  Offset _bgImageOffset = Offset.zero;
  double? _bgScaleStart;
  Offset? _bgOffsetStart;
  Offset? _bgFocalPointStart;

  bool _isSaving = false;

  final List<Color> _colors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return PopScope(
      canPop: !_isDrawing && !_isTextEditing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // If drawing or text editing, just close that mode
          if (_isDrawing) {
            setState(() => _isDrawing = false);
          } else if (_isTextEditing) {
            setState(() => _isTextEditing = false);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
        children: [
          // Status bar area - black
          Container(
            height: statusBarHeight,
            color: Colors.black,
          ),
          // Remaining area
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image area - rounded corners
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Black background
                      Container(color: Colors.black),
                      // RepaintBoundary - for drawings and image overlays
                      RepaintBoundary(
                        key: _repaintKey,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Background media (photo or video)
                            Transform.translate(
                              offset: _bgImageOffset,
                              child: Transform.scale(
                                scale: _bgImageScale,
                                child: _buildBackgroundMedia(),
                              ),
                            ),
                            // Wrap with SaveLayer so eraser blendMode.clear works
                            ClipRect(
                              child: CustomPaint(
                                painter: DrawingPainter(paths: _drawings),
                                size: Size.infinite,
                                isComplex: true,
                                willChange: true,
                              ),
                            ),
                            if (!_isDrawing) ..._buildImageOverlays(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Background image gesture handler - always active (works with two fingers)
                _buildBackgroundImageGesture(),
                // Text overlays
                if (!_isTextEditing && !_isDrawing) ..._buildTextOverlays(),
                if (_isDrawing) _buildDrawingLayer(),
                if (!_isTextEditing && !_isDrawing) _buildTopControls(),
                if (!_isTextEditing && !_isDrawing) _buildBottomControls(),
                if (_isDrawing) _buildDrawingTools(),
                if (_isDrawing) _buildDrawingTopBar(),
                if (_isDrawing && _isSliding) _buildBrushSizePreview(),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Build background media (photo or video)
  Widget _buildBackgroundMedia() {
    if (_mediaType == MediaType.video) {
      // Video background
      if (_isVideoInitialized && _videoController != null) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      } else {
        // Show loading while video is loading
        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      }
    } else {
      // Photo background
      // From gallery: fitWidth (fit to width), From camera: cover (fullscreen)
      return Image.file(
        File(widget.mediaPath),
        fit: widget.isFromGallery ? BoxFit.fitWidth : BoxFit.cover,
        width: double.infinity,
        height: widget.isFromGallery ? null : double.infinity,
      );
    }
  }

  /// Background image gesture handler - only works with two fingers
  Widget _buildBackgroundImageGesture() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) {
          // Only start with two fingers
          if (details.pointerCount >= 2) {
            _bgScaleStart = _bgImageScale;
            _bgOffsetStart = _bgImageOffset;
            _bgFocalPointStart = details.focalPoint;
          }
        },
        onScaleUpdate: (details) {
          // Only update with two fingers
          if (details.pointerCount >= 2 && _bgScaleStart != null && _bgOffsetStart != null && _bgFocalPointStart != null) {
            final delta = details.focalPoint - _bgFocalPointStart!;
            setState(() {
              _bgImageOffset = Offset(
                _bgOffsetStart!.dx + delta.dx,
                _bgOffsetStart!.dy + delta.dy,
              );
              // Update scale (limit between 0.3 and 10.0)
              _bgImageScale = (_bgScaleStart! * details.scale).clamp(0.3, 10.0);
            });
          }
        },
        onScaleEnd: (details) {
          _bgScaleStart = null;
          _bgOffsetStart = null;
          _bgFocalPointStart = null;
        },
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildDrawingLayer() {
    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _currentPath = DrawingPath(
            color: _currentBrushType == BrushType.eraser ? Colors.transparent : _currentColor,
            strokeWidth: _brushSize,
            brushType: _currentBrushType,
          );
          _currentPath!.points.add(details.localPosition);
          _drawings.add(_currentPath!);
        });
      },
      onPanUpdate: (details) {
        setState(() {
          _currentPath?.points.add(details.localPosition);
        });
      },
      onPanEnd: (details) {
        _currentPath = null;
      },
      child: Container(color: Colors.transparent),
    );
  }

  /// Build movable image overlays (gradient+text images from Create Mode)
  List<Widget> _buildImageOverlays() {
    return _imageOverlays.asMap().entries.map((entry) {
      final index = entry.key;
      final overlay = entry.value;

      return Positioned(
        left: overlay.offset.dx,
        top: overlay.offset.dy,
        child: GestureDetector(
          onTap: () => _editImageOverlay(index),
          onPanStart: (details) {
            setState(() {
              _isDraggingOverlay = true;
              _draggingOverlayIndex = index;
              _draggingOverlayType = 'image';
            });
          },
          onPanUpdate: (details) {
            final newOffset = Offset(
              overlay.offset.dx + details.delta.dx,
              overlay.offset.dy + details.delta.dy,
            );

            // Check trash zone (bottom right, left of check button)
            final screenHeight = MediaQuery.of(context).size.height;
            final screenWidth = MediaQuery.of(context).size.width;
            final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
            final trashZone = Rect.fromCenter(
              center: Offset(screenWidth / 2, screenHeight - bottomPadding - 24 - 28),
              width: 80,
              height: 80,
            );
            final isOver = trashZone.contains(details.globalPosition);

            setState(() {
              _imageOverlays[index] = overlay.copyWith(offset: newOffset);
              _isOverTrash = isOver;
            });
          },
          onPanEnd: (details) {
            // Delete if over trash
            if (_isOverTrash && _draggingOverlayIndex == index) {
              setState(() {
                _imageOverlays.removeAt(index);
              });
            }
            setState(() {
              _isDraggingOverlay = false;
              _isOverTrash = false;
              _draggingOverlayIndex = null;
              _draggingOverlayType = null;
            });
          },
          child: AnimatedScale(
            scale: (_isOverTrash && _draggingOverlayIndex == index && _draggingOverlayType == 'image')
                ? 0.5
                : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedOpacity(
              opacity: (_isOverTrash && _draggingOverlayIndex == index && _draggingOverlayType == 'image')
                  ? 0.5
                  : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: MediaQuery.of(context).size.width * overlay.scale,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(overlay.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Image overlay editing dialog
  void _editImageOverlay(int index) {
    final overlay = _imageOverlays[index];

    // If text and gradient exist, open GradientTextEditor for editing
    if (overlay.text != null && overlay.gradient != null) {
      openGradientTextEditor(
        context,
        onComplete: (newText, newGradient) async {
          // Create new image
          final newImagePath = await _createGradientTextImage(newText, newGradient);
          if (newImagePath != null) {
            setState(() {
              _imageOverlays[index] = overlay.copyWith(
                imagePath: newImagePath,
                text: newText,
                gradient: newGradient,
              );
            });
          }
        },
      );
      return;
    }

    // If no text/gradient, only show delete option
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Image Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => _imageOverlays.removeAt(index));
                    Navigator.pop(context);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.primaryColor ?? Colors.blue,
                  ),
                  child: const Text('OK', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Create PNG image with gradient background + centered text
  Future<String?> _createGradientTextImage(String text, LinearGradient gradient) async {
    try {
      // Canvas size from config (story format)
      final config = context.storyEditorConfig;
      final int canvasWidth = config.storyCanvasWidth;
      final int canvasHeight = config.storyCanvasHeight;

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

      // Set text style
      final textStyle = ui.TextStyle(
        color: Colors.white,
        fontSize: 72,
        fontWeight: FontWeight.bold,
        shadows: [
          const ui.Shadow(
            color: Color(0x61000000),
            offset: Offset(2, 2),
            blurRadius: 8,
          ),
        ],
      );

      final paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          maxLines: null,
        ),
      )
        ..pushStyle(textStyle)
        ..addText(text);

      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: canvasWidth - 100));

      final textX = (canvasWidth - paragraph.width) / 2;
      final textY = (canvasHeight - paragraph.height) / 2;

      canvas.drawParagraph(paragraph, Offset(textX, textY));

      final picture = recorder.endRecording();
      final img = await picture.toImage(canvasWidth, canvasHeight);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/gradient_text_$timestamp.png';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(byteData.buffer.asUint8List());

      return outputPath;
    } catch (e) {
      debugPrint('Create gradient text image error: $e');
      return null;
    }
  }

  List<Widget> _buildTextOverlays() {
    return _textOverlays.asMap().entries.map((entry) {
      final index = entry.key;
      final overlay = entry.value;

      // Gradient or solid color background
      final bool hasGradient = overlay.backgroundGradient != null;

      return Positioned(
        left: overlay.offset.dx,
        top: overlay.offset.dy,
        child: GestureDetector(
          onTap: () => _editText(index),
          onScaleStart: (details) {
            _draggingTextIndex = index;
            _textDragStartOffset = overlay.offset;
            _textDragStartPosition = details.focalPoint;
            _textScaleStart = overlay.scale;
            setState(() {
              _isDraggingOverlay = true;
              _draggingOverlayIndex = index;
              _draggingOverlayType = 'text';
            });
          },
          onScaleUpdate: (details) {
            if (_draggingTextIndex == index &&
                _textDragStartOffset != null &&
                _textDragStartPosition != null &&
                _textScaleStart != null) {
              final delta = details.focalPoint - _textDragStartPosition!;
              final newOffset = Offset(
                _textDragStartOffset!.dx + delta.dx,
                _textDragStartOffset!.dy + delta.dy,
              );

              // Check trash zone (bottom right, left of check button)
              final screenHeight = MediaQuery.of(context).size.height;
              final screenWidth = MediaQuery.of(context).size.width;
              final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
              final trashZone = Rect.fromCenter(
                center: Offset(screenWidth / 2, screenHeight - bottomPadding - 24 - 28),
                width: 80,
                height: 80,
              );
              final isOver = trashZone.contains(details.focalPoint);

              setState(() {
                _textOverlays[index] = overlay.copyWith(
                  offset: newOffset,
                  scale: (_textScaleStart! * details.scale).clamp(0.5, 3.0),
                );
                _isOverTrash = isOver;
              });
            }
          },
          onScaleEnd: (details) {
            // Delete if over trash
            if (_isOverTrash && _draggingOverlayIndex == index) {
              setState(() {
                _textOverlays.removeAt(index);
              });
            }
            setState(() {
              _isDraggingOverlay = false;
              _isOverTrash = false;
              _draggingOverlayIndex = null;
              _draggingOverlayType = null;
            });
            _draggingTextIndex = null;
            _textDragStartOffset = null;
            _textDragStartPosition = null;
            _textScaleStart = null;
          },
          child: AnimatedScale(
            scale: (_isOverTrash && _draggingOverlayIndex == index && _draggingOverlayType == 'text')
                ? overlay.scale * 0.5
                : overlay.scale,
            duration: const Duration(milliseconds: 150),
            child: AnimatedOpacity(
              opacity: (_isOverTrash && _draggingOverlayIndex == index && _draggingOverlayType == 'text')
                  ? 0.5
                  : 1.0,
              duration: const Duration(milliseconds: 150),
              child: hasGradient
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: overlay.backgroundGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    overlay.text,
                    style: overlay.toTextStyle(
                      shadows: [
                        const Shadow(
                          color: Colors.black38,
                          offset: Offset(1, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                )
              // Each line as separate box - including soft wrap lines
              : Builder(
                  builder: (context) {
                    final textStyle = overlay.toTextStyle();

                    // Maximum width (screen width - padding)
                    // If background exists, also subtract horizontal padding (20*2=40)
                    final bgPadding = overlay.backgroundColor != null ? 40.0 : 0.0;
                    final maxWidth = MediaQuery.of(context).size.width - 80 - bgPadding;

                    // Calculate lines
                    final lines = _calculateTextLines(overlay.text, textStyle, maxWidth);

                    // If lines couldn't be calculated, use original text
                    if (lines.isEmpty) {
                      lines.add(overlay.text);
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: lines.asMap().entries.map((lineEntry) {
                        final lineIndex = lineEntry.key;
                        final line = lineEntry.value;

                        return Transform.translate(
                          offset: Offset(0, lineIndex * -6.0), // Each line shifts 6px up
                          child: IntrinsicWidth(
                            child: Container(
                              padding: overlay.backgroundColor != null
                                  ? const EdgeInsets.symmetric(horizontal: 20, vertical: 4)
                                  : EdgeInsets.zero,
                              decoration: overlay.backgroundColor != null
                                  ? BoxDecoration(
                                      color: overlay.backgroundColor,
                                      borderRadius: BorderRadius.circular(25),
                                    )
                                  : null,
                              child: Text(
                                line.isEmpty ? ' ' : line,
                                style: textStyle.copyWith(height: 1.1),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTopControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildControlButton(
              iconWidget: SvgPicture.asset(
                'packages/story_editor_pro/assets/icons/xmark.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
              onTap: () => Navigator.pop(context),
            ),
            Row(
              children: [
                _buildControlButton(
                  icon: Icons.undo,
                  onTap: _undo,
                ),
                const SizedBox(width: 12),
                _buildControlButton(
                  icon: _isDrawing ? Icons.edit_off : Icons.edit,
                  onTap: () => setState(() {
                    if (!_isDrawing) {
                      // Save current drawing count when entering drawing mode
                      _drawingCountBeforeSession = _drawings.length;
                    }
                    _isDrawing = !_isDrawing;
                  }),
                  isActive: _isDrawing,
                ),
                const SizedBox(width: 12),
                _buildControlButton(
                  icon: Icons.text_fields,
                  onTap: _addText,
                ),
                const SizedBox(width: 12),
                _buildControlButton(
                  icon: Icons.save,
                  onTap: _isSaving ? () {} : () => _saveToGallery(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Stack(
      children: [
        // Trash bin (visible during dragging) - center of screen
        if (_isDraggingOverlay)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).viewPadding.bottom + 24,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isOverTrash
                      ? Colors.red.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'packages/story_editor_pro/assets/icons/trash.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Check button - bottom right
        Positioned(
          right: 16,
          bottom: MediaQuery.of(context).viewPadding.bottom + 24,
          child: GestureDetector(
            onTap: _isSaving ? null : _showShareSheet,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : SvgPicture.asset(
                        'packages/story_editor_pro/assets/icons/check.svg',
                        width: 28,
                        height: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // State for share options
  bool _shareToStory = true;
  bool _shareToCloseFriends = false;

  void _showShareSheet() {
    // If close friends is disabled, share directly to story
    if (!widget.closeFriendsEnabled) {
      _saveAndComplete(
        toStory: true,
        closeFriends: false,
        selectedFriends: [],
      );
      return;
    }

    // Reset state
    _shareToStory = true;
    _shareToCloseFriends = false;
    _selectedCloseFriends.clear();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).viewPadding.bottom + 16,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF262626),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top line (handle)
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Share',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                // Your Story option
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setSheetState(() {
                      _shareToStory = true;
                      _shareToCloseFriends = false;
                      _selectedCloseFriends.clear();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        // Profile picture
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blue,
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: widget.userProfileImageUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      widget.userProfileImageUrl!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          _buildDefaultProfileIcon(),
                                    ),
                                  )
                                : _buildDefaultProfileIcon(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Text
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Story',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'And Facebook Story',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Radio button
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _shareToStory ? Colors.white : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: _shareToStory
                              ? Center(
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),

                // Close Friends option
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setSheetState(() {
                      _shareToCloseFriends = true;
                      _shareToStory = false;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        // Green star icon
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF1DB954),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'packages/story_editor_pro/assets/icons/star.svg',
                              width: 28,
                              height: 28,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Close Friends',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.closeFriendsList.length} people',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Radio button
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _shareToCloseFriends ? Colors.white : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: _shareToCloseFriends
                              ? Center(
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),

                // Close friends list (when close friends is selected)
                if (_shareToCloseFriends && widget.closeFriendsList.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select friends to share with:',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.closeFriendsList.length,
                      itemBuilder: (context, index) {
                        final friend = widget.closeFriendsList[index];
                        final isSelected = _selectedCloseFriends.contains(friend);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setSheetState(() {
                              if (isSelected) {
                                _selectedCloseFriends.remove(friend);
                              } else {
                                _selectedCloseFriends.add(friend);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                // Avatar
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey.shade700,
                                  ),
                                  child: friend.avatarUrl != null
                                      ? ClipOval(
                                          child: Image.network(
                                            friend.avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Center(
                                              child: Text(
                                                friend.name.isNotEmpty
                                                    ? friend.name[0].toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            friend.name.isNotEmpty
                                                ? friend.name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                // Name
                                Expanded(
                                  child: Text(
                                    friend.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                // Checkbox
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? const Color(0xFF0095F6) : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF0095F6) : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Share button
                GestureDetector(
                  onTap: _canShare()
                      ? () {
                          Navigator.pop(context);
                          _saveAndComplete(
                            toStory: _shareToStory,
                            closeFriends: _shareToCloseFriends,
                            selectedFriends: _selectedCloseFriends.toList(),
                          );
                        }
                      : null,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _canShare()
                          ? const Color(0xFF0095F6)
                          : const Color(0xFF0095F6).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        _shareToCloseFriends && _selectedCloseFriends.isNotEmpty
                            ? 'Share to ${_selectedCloseFriends.length} friends'
                            : 'Share',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _canShare() {
    if (_shareToStory) return true;
    if (_shareToCloseFriends && _selectedCloseFriends.isNotEmpty) return true;
    return false;
  }

  Widget _buildDrawingTools() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).viewPadding.bottom + 16,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Brush size slider (horizontal) - icons aligned at top
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small circle icon - at top
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white38,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: _brushSize,
                          min: 2,
                          max: 20,
                          onChangeStart: (value) {
                            setState(() => _isSliding = true);
                          },
                          onChanged: (value) {
                            setState(() => _brushSize = value);
                          },
                          onChangeEnd: (value) {
                            setState(() => _isSliding = false);
                          },
                        ),
                      ),
                    ),
                    // Large circle icon - at top
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Colors (horizontal) - Hide in eraser mode
              if (_currentBrushType != BrushType.eraser)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _colors.map((color) => GestureDetector(
                      onTap: () => setState(() => _currentColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _currentColor == color ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              if (_currentBrushType != BrushType.eraser)
                const SizedBox(height: 16),
              // Brush types (horizontal)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildBrushTypeButton(BrushType.normal, Icons.edit),
                    _buildBrushTypeButton(BrushType.arrow, Icons.arrow_upward),
                    _buildBrushTypeButton(BrushType.marker, Icons.highlight),
                    _buildBrushTypeButton(BrushType.glow, Icons.auto_awesome),
                    _buildBrushTypeButton(BrushType.eraser, Icons.auto_fix_normal),
                    _buildBrushTypeButton(BrushType.chalk, Icons.gesture),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Brush type button
  Widget _buildBrushTypeButton(BrushType type, IconData icon) {
    final isSelected = _currentBrushType == type;
    return GestureDetector(
      onTap: () => setState(() => _currentBrushType = type),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: isSelected ? Colors.black : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// Brush size preview - shown just above the slider while sliding
  Widget _buildBrushSizePreview() {
    // Above the slider, above the colors
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom + 16 + 32 + 12 + 50 + 20;
    // viewPadding + container bottom + color height + margin + slider height + gap

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomPadding,
      child: Center(
        child: Container(
          width: _brushSize + 4, // +4 for border
          height: _brushSize + 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
          ),
          child: Center(
            child: Container(
              width: _brushSize,
              height: _brushSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    IconData? icon,
    Widget? iconWidget,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.15),
        ),
        child: Center(
          child: iconWidget ?? Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  void _undo() {
    setState(() {
      if (_drawings.isNotEmpty) {
        _drawings.removeLast();
      } else if (_textOverlays.isNotEmpty) {
        _textOverlays.removeLast();
      }
    });
  }

  /// Drawing mode top bar - X (exit), Undo and Check button
  Widget _buildDrawingTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left side - X button and Undo button
            Row(
              children: [
                // X button - exit drawing mode (cancel drawings from this session)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      // Only delete drawings from this session, keep previous drawings
                      while (_drawings.length > _drawingCountBeforeSession) {
                        _drawings.removeLast();
                      }
                      _isDrawing = false;
                    });
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Undo button - only show if there are drawings
                if (_drawings.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _drawings.removeLast();
                      });
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.undo,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Check button - save drawings and exit mode
            GestureDetector(
              onTap: () {
                setState(() => _isDrawing = false);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'packages/story_editor_pro/assets/icons/check.svg',
                    width: 24,
                    height: 24,
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

  /// Split text into lines - consistent results using getLineBoundary
  List<String> _calculateTextLines(String text, TextStyle style, double maxWidth) {
    if (text.isEmpty) return [];

    final List<String> result = [];

    // First split by manual line breaks
    final paragraphs = text.split('\n');

    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        result.add('');
        continue;
      }

      // Check if there are spaces
      final hasSpaces = paragraph.contains(' ');

      if (hasSpaces) {
        // Word-based line breaking
        final words = paragraph.split(' ');
        String currentLine = '';

        for (int i = 0; i < words.length; i++) {
          final word = words[i];
          final testLine = currentLine.isEmpty ? word : '$currentLine $word';

          final textPainter = TextPainter(
            text: TextSpan(text: testLine, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          );
          textPainter.layout();

          if (textPainter.width <= maxWidth) {
            currentLine = testLine;
          } else {
            if (currentLine.isNotEmpty) {
              result.add(currentLine);
              currentLine = word;
            } else {
              // Word doesn't fit alone, break by characters
              final charLines = _breakLongWord(word, style, maxWidth);
              result.addAll(charLines);
              currentLine = '';
            }
          }
        }

        if (currentLine.isNotEmpty) {
          result.add(currentLine);
        }
      } else {
        // No spaces, character-based line breaking
        final charLines = _breakLongWord(paragraph, style, maxWidth);
        result.addAll(charLines);
      }
    }

    return result;
  }

  /// Break long word by characters (keeping minimum 3 characters)
  List<String> _breakLongWord(String word, TextStyle style, double maxWidth) {
    final List<String> lines = [];
    String remaining = word;

    while (remaining.isNotEmpty) {
      // Find maximum fitting character count using binary search
      int low = 1;
      int high = remaining.length;
      int bestFit = 1;

      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final testText = remaining.substring(0, mid);

        final textPainter = TextPainter(
          text: TextSpan(text: testText, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        );
        textPainter.layout();

        if (textPainter.width <= maxWidth) {
          bestFit = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      // If remaining part would be too short (3 or less), take some from previous line
      final remainingAfter = remaining.length - bestFit;
      if (remainingAfter > 0 && remainingAfter <= 3 && bestFit > 3) {
        // Adjust so at least 4 characters remain in the last line
        bestFit = remaining.length - 4;
        if (bestFit < 1) bestFit = 1;
      }

      lines.add(remaining.substring(0, bestFit));
      remaining = remaining.substring(bestFit);
    }

    return lines;
  }

  void _addText() {
    _showTextDialog();
  }

  void _editText(int index) {
    _showTextDialog(existingIndex: index);
  }

  void _showTextDialog({int? existingIndex}) {
    // Enter text edit mode
    setState(() => _isTextEditing = true);

    // Get fonts from config
    final fontsConfig = context.storyFonts;
    final fontStyles = fontsConfig.fontStyles;

    final existing = existingIndex != null ? _textOverlays[existingIndex] : null;
    final controller = TextEditingController(text: existing?.text ?? '');
    Color selectedColor = existing?.color ?? Colors.white;
    Color backgroundColor = existing?.backgroundColor ?? Colors.black;
    double fontSize = existing?.fontSize ?? fontsConfig.defaultFontSize;
    TextAlign textAlign = TextAlign.center;
    int selectedFontIndex = existing?.fontIndex ?? fontsConfig.defaultFontIndex;
    bool hasBackground = existing?.backgroundColor != null;
    bool isItalic = existing?.isItalic ?? false;

    // Which picker is open
    String? openPicker; // 'color', 'bgColor'

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // TextStyle based on font style (from config)
              TextStyle getTextStyle() {
                final fontConfig = fontsConfig.getFontStyle(selectedFontIndex);
                return fontConfig.toTextStyle(
                  fontSize: fontSize,
                  color: selectedColor,
                );
              }

              return PopScope(
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) {
                    setState(() => _isTextEditing = false);
                  }
                },
                child: Scaffold(
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  resizeToAvoidBottomInset: true,
                  body: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Top bar - Close and Done buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Close button (X) - cancel and go back to editor
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            // Done button - save text
                            GestureDetector(
                              onTap: () {
                                if (controller.text.isNotEmpty) {
                                  setState(() {
                                    _isTextEditing = false;

                                    final selectedFont = fontsConfig.getFontStyle(selectedFontIndex);
                                    // If isItalic, add italic to textStyle
                                    final finalTextStyle = isItalic
                                        ? selectedFont.textStyle.copyWith(fontStyle: FontStyle.italic)
                                        : selectedFont.textStyle;

                                    // Calculate text size with actual font style
                                    final actualTextStyle = finalTextStyle.copyWith(
                                      fontSize: fontSize,
                                      color: selectedColor,
                                    );
                                    final screenWidth = MediaQuery.of(context).size.width;
                                    final screenHeight = MediaQuery.of(context).size.height;
                                    final maxWidth = screenWidth - 80;
                                    final textPainter = TextPainter(
                                      text: TextSpan(text: controller.text, style: actualTextStyle),
                                      textDirection: TextDirection.ltr,
                                      maxLines: null,
                                    );
                                    textPainter.layout(maxWidth: maxWidth);

                                    // Account for padding (for text with background)
                                    final horizontalPadding = hasBackground ? 20.0 * 2 : 0.0;
                                    final verticalPadding = hasBackground ? 4.0 * 2 : 0.0;
                                    final totalWidth = textPainter.width + horizontalPadding;
                                    final totalHeight = textPainter.height + verticalPadding;

                                    // Position at exact center of screen
                                    final overlay = TextOverlay(
                                      text: controller.text,
                                      color: selectedColor,
                                      backgroundColor: hasBackground ? backgroundColor : null,
                                      fontSize: fontSize,
                                      textStyle: finalTextStyle,
                                      fontIndex: selectedFontIndex,
                                      isItalic: isItalic,
                                      offset: existing?.offset ?? Offset(
                                        (screenWidth - totalWidth) / 2,
                                        (screenHeight - totalHeight) / 2,
                                      ),
                                    );

                                    if (existingIndex != null) {
                                      _textOverlays[existingIndex] = overlay;
                                    } else {
                                      _textOverlays.add(overlay);
                                    }
                                  });
                                } else {
                                  setState(() => _isTextEditing = false);
                                }
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    'packages/story_editor_pro/assets/icons/check.svg',
                                    width: 24,
                                    height: 24,
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

                      // Center area - Text input
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          // Text area - each line as separate box (invisible TextField + visible lines)
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              // TextField'a focus ver
                              FocusScope.of(context).requestFocus(FocusNode());
                            },
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // If background exists, also subtract horizontal padding (20*2=40)
                                  final bgPadding = hasBackground ? 40.0 : 0.0;
                                  final maxWidth = constraints.maxWidth - 40 - bgPadding;
                                  final text = controller.text;

                                  // Calculate lines - use the same method
                                  List<String> lines = _calculateTextLines(text, getTextStyle(), maxWidth);

                                  // If no text or empty, show TextField
                                  if (lines.isEmpty) {
                                    return IntrinsicWidth(
                                      child: Container(
                                        padding: hasBackground
                                            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 4)
                                            : EdgeInsets.zero,
                                        decoration: hasBackground
                                            ? BoxDecoration(
                                                color: backgroundColor,
                                                borderRadius: BorderRadius.circular(25),
                                              )
                                            : null,
                                        child: TextField(
                                          controller: controller,
                                          autofocus: true,
                                          style: getTextStyle(),
                                          textAlign: textAlign,
                                          maxLines: null,
                                          decoration: InputDecoration(
                                            hintText: 'Enter text...',
                                            hintStyle: TextStyle(
                                              color: Colors.white38,
                                              fontSize: fontSize,
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onChanged: (value) {
                                            setDialogState(() {});
                                          },
                                        ),
                                      ),
                                    );
                                  }

                                  // Calculate maximum line count based on screen height
                                  final availableHeight = constraints.maxHeight;
                                  final lineHeight = fontSize + 12; // Font size + padding
                                  final maxVisibleLines = (availableHeight / lineHeight).floor().clamp(3, 15);

                                  // If line count exceeds limit, only show last lines
                                  final visibleLines = lines.length > maxVisibleLines
                                      ? lines.sublist(lines.length - maxVisibleLines)
                                      : lines;

                                  // If text exists, show each line as separate box
                                  return Stack(
                                    children: [
                                      // Visible lines
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: visibleLines.asMap().entries.map((entry) {
                                          final idx = entry.key;
                                          final line = entry.value;
                                          return Transform.translate(
                                            offset: Offset(0, idx * -6.0),
                                            child: IntrinsicWidth(
                                              child: Container(
                                                padding: hasBackground
                                                    ? const EdgeInsets.symmetric(horizontal: 20, vertical: 4)
                                                    : EdgeInsets.zero,
                                                decoration: hasBackground
                                                    ? BoxDecoration(
                                                        color: backgroundColor,
                                                        borderRadius: BorderRadius.circular(25),
                                                      )
                                                    : null,
                                                child: Text(
                                                  line.isEmpty ? ' ' : line,
                                                  style: getTextStyle().copyWith(height: 1.1),
                                                  textAlign: textAlign,
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                      // Invisible TextField (for keyboard)
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity: 0,
                                          child: TextField(
                                            controller: controller,
                                            autofocus: true,
                                            style: getTextStyle(),
                                            textAlign: textAlign,
                                            maxLines: null,
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                            ),
                                            onChanged: (value) {
                                              setDialogState(() {});
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Bottom section - Instagram style (fixed above keyboard)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom > 0
                              ? 8
                              : MediaQuery.of(context).viewPadding.bottom + 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Font size slider (horizontal)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.text_fields, color: Colors.white54, size: 18),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white38,
                                      thumbColor: Colors.white,
                                      overlayColor: Colors.white24,
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    ),
                                    child: Slider(
                                      value: fontSize,
                                      min: 16,
                                      max: 64,
                                      onChanged: (value) {
                                        setDialogState(() => fontSize = value);
                                      },
                                    ),
                                  ),
                                ),
                                const Icon(Icons.text_fields, color: Colors.white, size: 24),
                              ],
                            ),
                          ),

                          // Tab bar area - Font styles OR Colors
                          SizedBox(
                            height: 44,
                            child: openPicker == 'color'
                                // Text color picker
                                ? ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    children: _colors.map((color) => GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedColor = color;
                                        });
                                      },
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: selectedColor == color ? Colors.white : Colors.transparent,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                    )).toList(),
                                  )
                                : openPicker == 'bgColor'
                                    // Background color picker
                                    ? ListView(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        children: _colors.map((color) => GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              backgroundColor = color;
                                            });
                                          },
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: backgroundColor == color ? Colors.white : Colors.transparent,
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                        )).toList(),
                                      )
                                    // Font styles (from config)
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        itemCount: fontStyles.length,
                                        itemBuilder: (context, index) {
                                          final isSelected = selectedFontIndex == index;
                                          final fontConfig = fontStyles[index];
                                          return GestureDetector(
                                            onTap: () {
                                              setDialogState(() => selectedFontIndex = index);
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(horizontal: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isSelected ? Colors.white : Colors.transparent,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                fontConfig.name,
                                                style: fontConfig.toTextStyle(
                                                  fontSize: 14,
                                                  color: isSelected ? Colors.black : Colors.white,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                          const SizedBox(height: 8),

                          // Toolbar - at bottom
                          Container(
                            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Aa - Font button
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      openPicker = null; // Return to font tab
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: openPicker == null ? Colors.white : Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Aa',
                                        style: TextStyle(
                                          color: openPicker == null ? Colors.black : Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Color picker
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      openPicker = openPicker == 'color' ? null : 'color';
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: openPicker == 'color' ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple],
                                          ),
                                          border: Border.all(color: openPicker == 'color' ? Colors.black : Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Italic //A
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() => isItalic = !isItalic);
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isItalic ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '//A',
                                        style: TextStyle(
                                          color: isItalic ? Colors.black : Colors.white,
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Background A (dotted border)
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      if (openPicker == 'bgColor') {
                                        // If color picker is open, close it and disable background
                                        openPicker = null;
                                        hasBackground = false;
                                      } else if (hasBackground) {
                                        // If background exists, open color picker
                                        openPicker = 'bgColor';
                                      } else {
                                        // If no background, enable it and show color picker
                                        hasBackground = true;
                                        openPicker = 'bgColor';
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: openPicker == 'bgColor' ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: CustomPaint(
                                      painter: DottedBorderPainter(
                                        color: openPicker == 'bgColor' ? Colors.black : Colors.white,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'A',
                                          style: TextStyle(
                                            color: openPicker == 'bgColor' ? Colors.black : Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
                ),
              );
            },
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Save to gallery
  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);

    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to convert image');

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Save to temp file
      final tempDir = Directory.systemTemp;
      final fileName = 'story_edited_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      // Save to gallery
      await PhotoManager.editor.saveImageWithPath(
        file.path,
        title: fileName,
      );

      if (mounted) {
        _showSavedModal();
      }
    } catch (e) {
      debugPrint('Save to gallery error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save to gallery: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  /// Default profile icon when no image URL is provided
  Widget _buildDefaultProfileIcon() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade800,
      ),
      child: Center(
        child: SvgPicture.asset(
          'packages/story_editor_pro/assets/icons/profile-circle.svg',
          width: 32,
          height: 32,
          colorFilter: const ColorFilter.mode(
            Colors.white54,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  /// Show saved modal - closes after configured delay
  void _showSavedModal() {
    final config = context.storyEditorConfig;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (dialogContext) {
        // Auto close after configured delay
        Future.delayed(config.savedModalAutoCloseDelay, () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  config.strings.editorSaved,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveAndComplete({
    bool toStory = true,
    bool closeFriends = false,
    List<CloseFriend> selectedFriends = const [],
  }) async {
    setState(() => _isSaving = true);

    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Render boundary not found');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to convert image');

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = Directory.systemTemp;
      final fileName = 'story_edited_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        // Create StoryResult
        final storyResult = await StoryResult.fromFile(
          file.path,
          mediaType: StoryMediaType.image,
        );

        // Create StoryShareResult
        final shareResult = StoryShareResult(
          story: storyResult,
          shareTarget: closeFriends ? ShareTarget.closeFriends : ShareTarget.story,
          selectedFriends: selectedFriends,
        );

        // Call onShare callback if provided
        widget.onShare?.call(shareResult);

        // Return share result (backwards compatible map format)
        Navigator.pop(context, {
          'path': file.path,
          'toStory': toStory,
          'closeFriends': closeFriends,
          'selectedFriends': selectedFriends.map((f) => f.toJson()).toList(),
          'shareResult': shareResult,
        });
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }
}

/// CustomPainter that draws a triangle-shaped vertical slider
class TriangleSliderPainter extends CustomPainter {
  final double value; // 0-1 range
  final Color activeColor;
  final double brushSize; // Brush size (2-20)

  TriangleSliderPainter({
    required this.value,
    required this.activeColor,
    required this.brushSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Background triangle (gray) - wide at top, narrow at bottom
    final bgPath = Path()
      ..moveTo(0, 0) // Top left
      ..lineTo(width, 0) // Top right
      ..lineTo(width / 2, height) // Bottom center (narrow)
      ..close();

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawPath(bgPath, bgPaint);

    // Active part (colored) - fills from bottom to top
    // value=0 -> not filled at all (bottom), value=1 -> fully filled (top)
    final activeStartY = height * (1 - value); // Y where active part starts

    // Triangle width at this Y point
    final widthAtY = (1 - activeStartY / height) * width;
    final activeLeft = (width - widthAtY) / 2;

    final activePath = Path()
      ..moveTo(activeLeft, activeStartY) // Left point
      ..lineTo(activeLeft + widthAtY, activeStartY) // Right point
      ..lineTo(width / 2, height) // Bottom center
      ..close();

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(activePath, activePaint);

    // Slider indicator (round) - proportional to brush size
    final indicatorY = height * (1 - value);
    final indicatorX = width / 2;

    // Indicator size based on brush size (4-16 range)
    final indicatorRadius = 4 + (brushSize - 2) / 18 * 12;

    // Shadow effect
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(indicatorX + 1, indicatorY + 2), indicatorRadius, shadowPaint);

    // White outer ring (thicker)
    final outerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(indicatorX, indicatorY), indicatorRadius + 3, outerBorderPaint);

    // Active color circle
    final indicatorPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(indicatorX, indicatorY), indicatorRadius, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant TriangleSliderPainter oldDelegate) {
    return oldDelegate.value != value ||
           oldDelegate.activeColor != activeColor ||
           oldDelegate.brushSize != brushSize;
  }
}

/// CustomPainter that draws a dotted border
class DottedBorderPainter extends CustomPainter {
  final Color color;

  DottedBorderPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const double dashWidth = 4;
    const double dashSpace = 3;
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    double distance = 0;

    while (distance < metrics.length) {
      final start = metrics.getTangentForOffset(distance)?.position;
      distance += dashWidth;
      final end = metrics.getTangentForOffset(distance)?.position;
      if (start != null && end != null) {
        canvas.drawLine(start, end, paint);
      }
      distance += dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant DottedBorderPainter oldDelegate) => oldDelegate.color != color;
}

class TextOverlay {
  final String text;
  final Color color;
  final Color? backgroundColor;
  final LinearGradient? backgroundGradient;
  final double fontSize;
  final TextStyle textStyle;
  final Offset offset;
  final double scale;
  final int fontIndex;
  final bool isItalic;

  TextOverlay({
    required this.text,
    required this.color,
    this.backgroundColor,
    this.backgroundGradient,
    this.fontSize = 24,
    required this.textStyle,
    required this.offset,
    this.scale = 1.0,
    this.fontIndex = 0,
    this.isItalic = false,
  });

  TextOverlay copyWith({
    String? text,
    Color? color,
    Color? backgroundColor,
    LinearGradient? backgroundGradient,
    double? fontSize,
    TextStyle? textStyle,
    Offset? offset,
    double? scale,
    int? fontIndex,
    bool? isItalic,
  }) {
    return TextOverlay(
      text: text ?? this.text,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
      fontSize: fontSize ?? this.fontSize,
      textStyle: textStyle ?? this.textStyle,
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      fontIndex: fontIndex ?? this.fontIndex,
      isItalic: isItalic ?? this.isItalic,
    );
  }

  /// Return TextStyle with color and size
  TextStyle toTextStyle({List<Shadow>? shadows}) {
    return textStyle.copyWith(
      color: color,
      fontSize: fontSize,
      shadows: shadows,
    );
  }
}

class DrawingPath {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final BrushType brushType;

  DrawingPath({
    List<Offset>? points,
    required this.color,
    required this.strokeWidth,
    this.brushType = BrushType.normal,
  }) : points = points ?? [];
}

class DrawingPainter extends CustomPainter {
  final List<DrawingPath> paths;
  final List<DrawingPath>? erasedPaths; // For erased lines

  DrawingPainter({required this.paths, this.erasedPaths});

  @override
  void paint(Canvas canvas, Size size) {
    // Use saveLayer so eraser BlendMode.clear works
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (final path in paths) {
      if (path.points.isEmpty) continue;

      switch (path.brushType) {
        case BrushType.normal:
          _drawNormal(canvas, path);
          break;
        case BrushType.arrow:
          _drawArrow(canvas, path);
          break;
        case BrushType.marker:
          _drawMarker(canvas, path);
          break;
        case BrushType.glow:
          _drawGlow(canvas, path);
          break;
        case BrushType.eraser:
          _drawEraser(canvas, path);
          break;
        case BrushType.chalk:
          _drawChalk(canvas, path);
          break;
      }
    }

    canvas.restore();
  }

  /// Normal straight line
  void _drawNormal(Canvas canvas, DrawingPath path) {
    final paint = Paint()
      ..color = path.color
      ..strokeWidth = path.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (path.points.length == 1) {
      canvas.drawCircle(path.points.first, path.strokeWidth / 2, paint);
    } else {
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  /// Arrow-tipped line
  void _drawArrow(Canvas canvas, DrawingPath path) {
    final paint = Paint()
      ..color = path.color
      ..strokeWidth = path.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (path.points.length < 2) {
      if (path.points.isNotEmpty) {
        canvas.drawCircle(path.points.first, path.strokeWidth / 2, paint);
      }
      return;
    }

    // Draw the line
    final drawPath = Path();
    drawPath.moveTo(path.points.first.dx, path.points.first.dy);
    for (int i = 1; i < path.points.length; i++) {
      drawPath.lineTo(path.points[i].dx, path.points[i].dy);
    }
    canvas.drawPath(drawPath, paint);

    // Draw arrow head
    final lastPoint = path.points.last;
    final secondLast = path.points[path.points.length > 5 ? path.points.length - 5 : 0];
    final angle = (lastPoint - secondLast).direction;
    final arrowSize = path.strokeWidth * 2.5;

    final arrowPath = Path();
    arrowPath.moveTo(lastPoint.dx, lastPoint.dy);
    arrowPath.lineTo(
      lastPoint.dx - arrowSize * math.cos(angle - 0.5),
      lastPoint.dy - arrowSize * math.sin(angle - 0.5),
    );
    arrowPath.moveTo(lastPoint.dx, lastPoint.dy);
    arrowPath.lineTo(
      lastPoint.dx - arrowSize * math.cos(angle + 0.5),
      lastPoint.dy - arrowSize * math.sin(angle + 0.5),
    );
    canvas.drawPath(arrowPath, paint);
  }

  /// Marker/Highlighter style (broken edge, semi-transparent)
  void _drawMarker(Canvas canvas, DrawingPath path) {
    final paint = Paint()
      ..color = path.color.withValues(alpha: 0.5)
      ..strokeWidth = path.strokeWidth * 2
      ..strokeCap = StrokeCap.square // Square tip
      ..strokeJoin = StrokeJoin.bevel // Broken corner
      ..style = PaintingStyle.stroke;

    if (path.points.length == 1) {
      canvas.drawRect(
        Rect.fromCenter(center: path.points.first, width: path.strokeWidth * 2, height: path.strokeWidth),
        paint..style = PaintingStyle.fill,
      );
    } else {
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  /// Glow/Neon effect line
  void _drawGlow(Canvas canvas, DrawingPath path) {
    if (path.points.isEmpty) return;

    // Outer glow layers - bright light in selected color
    for (int i = 4; i >= 1; i--) {
      final glowPaint = Paint()
        ..color = path.color.withValues(alpha: 0.15 + (0.15 * (4 - i)))
        ..strokeWidth = path.strokeWidth + (i * 8)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i * 4.0);

      if (path.points.length == 1) {
        canvas.drawCircle(path.points.first, (path.strokeWidth + i * 8) / 2, glowPaint);
      } else {
        final drawPath = Path();
        drawPath.moveTo(path.points.first.dx, path.points.first.dy);
        for (int j = 1; j < path.points.length; j++) {
          drawPath.lineTo(path.points[j].dx, path.points[j].dy);
        }
        canvas.drawPath(drawPath, glowPaint);
      }
    }

    // Middle layer - selected color more intense
    final middlePaint = Paint()
      ..color = path.color.withValues(alpha: 0.9)
      ..strokeWidth = path.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (path.points.length == 1) {
      canvas.drawCircle(path.points.first, path.strokeWidth / 2, middlePaint);
    } else {
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, middlePaint);
    }

    // Main line (bright white center)
    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..strokeWidth = path.strokeWidth * 0.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (path.points.length == 1) {
      canvas.drawCircle(path.points.first, path.strokeWidth * 0.2, corePaint);
    } else {
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, corePaint);
    }
  }

  /// Eraser - transparent/white line
  void _drawEraser(Canvas canvas, DrawingPath path) {
    final paint = Paint()
      ..color = Colors.transparent
      ..strokeWidth = path.strokeWidth * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.clear;

    if (path.points.length == 1) {
      canvas.drawCircle(path.points.first, path.strokeWidth, paint);
    } else {
      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, paint);
    }
  }

  /// Chalk effect (rough, textured)
  void _drawChalk(Canvas canvas, DrawingPath path) {
    if (path.points.isEmpty) return;

    final random = math.Random(42); // Fixed seed for consistency

    for (int i = 0; i < path.points.length; i++) {
      final point = path.points[i];

      // Main point
      final paint = Paint()
        ..color = path.color.withValues(alpha: 0.7 + random.nextDouble() * 0.3)
        ..style = PaintingStyle.fill;

      // Randomly scattered points
      for (int j = 0; j < 5; j++) {
        final offsetX = (random.nextDouble() - 0.5) * path.strokeWidth;
        final offsetY = (random.nextDouble() - 0.5) * path.strokeWidth;
        final size = path.strokeWidth * 0.2 * (0.5 + random.nextDouble());

        canvas.drawCircle(
          Offset(point.dx + offsetX, point.dy + offsetY),
          size,
          paint,
        );
      }
    }

    // Also draw line for rough edge effect
    if (path.points.length > 1) {
      final linePaint = Paint()
        ..color = path.color.withValues(alpha: 0.5)
        ..strokeWidth = path.strokeWidth * 0.3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final drawPath = Path();
      drawPath.moveTo(path.points.first.dx, path.points.first.dy);
      for (int i = 1; i < path.points.length; i++) {
        drawPath.lineTo(path.points[i].dx, path.points[i].dy);
      }
      canvas.drawPath(drawPath, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) => true;
}

/// Movable image overlay - for gradient+text image from Create Mode
class ImageOverlay {
  final String imagePath;
  final Offset offset;
  final double scale;
  final String? text;
  final LinearGradient? gradient;

  ImageOverlay({
    required this.imagePath,
    required this.offset,
    this.scale = 0.6,
    this.text,
    this.gradient,
  });

  ImageOverlay copyWith({
    String? imagePath,
    Offset? offset,
    double? scale,
    String? text,
    LinearGradient? gradient,
  }) {
    return ImageOverlay(
      imagePath: imagePath ?? this.imagePath,
      offset: offset ?? this.offset,
      scale: scale ?? this.scale,
      text: text ?? this.text,
      gradient: gradient ?? this.gradient,
    );
  }
}
