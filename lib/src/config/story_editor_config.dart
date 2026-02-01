import 'package:flutter/material.dart';
import 'story_editor_strings.dart';
import 'story_editor_theme.dart';
import 'story_editor_fonts.dart';
import 'story_editor_settings.dart';

/// Main configuration class for Story Editor Pro
/// Pass this to StoryEditorConfigProvider to customize the entire plugin
class StoryEditorConfig {
  /// Localization strings (English defaults)
  final StoryEditorStrings strings;

  /// Theme configuration (colors, icons, gradients)
  final StoryEditorTheme theme;

  /// Font configuration
  final StoryEditorFonts fonts;

  /// Settings callbacks (replaces SharedPreferences)
  final StoryEditorSettings settings;

  // ============ Hands-Free Configuration ============

  /// Available delay options for hands-free mode (in seconds)
  final List<int> handsFreeDelayOptions;

  /// Default hands-free delay in seconds
  final int defaultHandsFreeDelay;

  /// Maximum hands-free recording duration in seconds
  final int maxHandsFreeRecordingSeconds;

  // ============ Video Configuration ============

  /// Maximum video recording duration in seconds
  final int maxVideoRecordingSeconds;

  // ============ Boomerang Configuration ============

  /// Maximum boomerang recording duration in seconds
  final int maxBoomerangSeconds;

  /// Boomerang output FPS (lower = slower playback, higher = faster)
  /// Default: 15 FPS for smooth slow-motion effect
  /// Range: 10-30 recommended
  final int boomerangFps;

  /// Number of times the boomerang loops (forward + backward = 1 loop)
  /// Default: 3 loops
  final int boomerangLoopCount;

  // ============ Gradient Configuration ============

  /// Default gradient balance (0.0 to 1.0)
  /// 0.5 means 50%/50% color distribution
  final double defaultGradientBalance;

  // ============ UI Configuration (High Priority) ============

  /// Recording indicator color (default: Instagram red #FF3B30)
  final Color recordingIndicatorColor;

  /// Boomerang mode gradient colors for shutter button
  final List<Color> boomerangGradientColors;

  /// Story canvas width for export (default: 1080)
  final int storyCanvasWidth;

  /// Story canvas height for export (default: 1920)
  final int storyCanvasHeight;

  /// Screen width breakpoint for responsive UI (default: 700)
  final double smallScreenBreakpoint;

  /// Shutter button size for large screens (default: 90)
  final double shutterButtonSizeLarge;

  /// Shutter button size for small screens (default: 70)
  final double shutterButtonSizeSmall;

  /// Number of images to load per page in gallery (default: 50)
  final int galleryPageSize;

  // ============ Animation Configuration (Medium Priority) ============

  /// Default animation duration for UI transitions
  final Duration animationDuration;

  /// Auto-close delay for saved modal (default: 3 seconds)
  final Duration savedModalAutoCloseDelay;

  /// Thumbnail size for gallery images (default: 200)
  final int thumbnailSize;

  /// Thumbnail quality for gallery images (default: 80, range: 1-100)
  final int thumbnailQuality;

  /// Pulse animation scale for recording indicator (default: 1.15)
  final double pulseAnimationScale;

  const StoryEditorConfig({
    this.strings = const StoryEditorStrings(),
    this.theme = const StoryEditorTheme(),
    this.fonts = const StoryEditorFonts(),
    this.settings = const StoryEditorSettings(),
    this.handsFreeDelayOptions = const [3, 5, 10, 15],
    this.defaultHandsFreeDelay = 3,
    this.maxHandsFreeRecordingSeconds = 60,
    this.maxVideoRecordingSeconds = 60,
    this.maxBoomerangSeconds = 4,
    this.boomerangFps = 15,
    this.boomerangLoopCount = 3,
    this.defaultGradientBalance = 0.5,
    // High Priority UI Config
    this.recordingIndicatorColor = const Color(0xFFFF3B30),
    this.boomerangGradientColors = const [Color(0xFFFF6B35), Color(0xFFFF1744)],
    this.storyCanvasWidth = 1080,
    this.storyCanvasHeight = 1920,
    this.smallScreenBreakpoint = 700,
    this.shutterButtonSizeLarge = 90,
    this.shutterButtonSizeSmall = 70,
    this.galleryPageSize = 50,
    // Medium Priority Animation Config
    this.animationDuration = const Duration(milliseconds: 200),
    this.savedModalAutoCloseDelay = const Duration(seconds: 3),
    this.thumbnailSize = 200,
    this.thumbnailQuality = 80,
    this.pulseAnimationScale = 1.15,
  });

  /// Create a copy with modified values
  StoryEditorConfig copyWith({
    StoryEditorStrings? strings,
    StoryEditorTheme? theme,
    StoryEditorFonts? fonts,
    StoryEditorSettings? settings,
    List<int>? handsFreeDelayOptions,
    int? defaultHandsFreeDelay,
    int? maxHandsFreeRecordingSeconds,
    int? maxVideoRecordingSeconds,
    int? maxBoomerangSeconds,
    int? boomerangFps,
    int? boomerangLoopCount,
    double? defaultGradientBalance,
    // High Priority UI Config
    Color? recordingIndicatorColor,
    List<Color>? boomerangGradientColors,
    int? storyCanvasWidth,
    int? storyCanvasHeight,
    double? smallScreenBreakpoint,
    double? shutterButtonSizeLarge,
    double? shutterButtonSizeSmall,
    int? galleryPageSize,
    // Medium Priority Animation Config
    Duration? animationDuration,
    Duration? savedModalAutoCloseDelay,
    int? thumbnailSize,
    int? thumbnailQuality,
    double? pulseAnimationScale,
  }) {
    return StoryEditorConfig(
      strings: strings ?? this.strings,
      theme: theme ?? this.theme,
      fonts: fonts ?? this.fonts,
      settings: settings ?? this.settings,
      handsFreeDelayOptions: handsFreeDelayOptions ?? this.handsFreeDelayOptions,
      defaultHandsFreeDelay: defaultHandsFreeDelay ?? this.defaultHandsFreeDelay,
      maxHandsFreeRecordingSeconds: maxHandsFreeRecordingSeconds ?? this.maxHandsFreeRecordingSeconds,
      maxVideoRecordingSeconds: maxVideoRecordingSeconds ?? this.maxVideoRecordingSeconds,
      maxBoomerangSeconds: maxBoomerangSeconds ?? this.maxBoomerangSeconds,
      boomerangFps: boomerangFps ?? this.boomerangFps,
      boomerangLoopCount: boomerangLoopCount ?? this.boomerangLoopCount,
      defaultGradientBalance: defaultGradientBalance ?? this.defaultGradientBalance,
      // High Priority UI Config
      recordingIndicatorColor: recordingIndicatorColor ?? this.recordingIndicatorColor,
      boomerangGradientColors: boomerangGradientColors ?? this.boomerangGradientColors,
      storyCanvasWidth: storyCanvasWidth ?? this.storyCanvasWidth,
      storyCanvasHeight: storyCanvasHeight ?? this.storyCanvasHeight,
      smallScreenBreakpoint: smallScreenBreakpoint ?? this.smallScreenBreakpoint,
      shutterButtonSizeLarge: shutterButtonSizeLarge ?? this.shutterButtonSizeLarge,
      shutterButtonSizeSmall: shutterButtonSizeSmall ?? this.shutterButtonSizeSmall,
      galleryPageSize: galleryPageSize ?? this.galleryPageSize,
      // Medium Priority Animation Config
      animationDuration: animationDuration ?? this.animationDuration,
      savedModalAutoCloseDelay: savedModalAutoCloseDelay ?? this.savedModalAutoCloseDelay,
      thumbnailSize: thumbnailSize ?? this.thumbnailSize,
      thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
      pulseAnimationScale: pulseAnimationScale ?? this.pulseAnimationScale,
    );
  }
}

/// InheritedWidget to provide StoryEditorConfig to the widget tree
class StoryEditorConfigProvider extends InheritedWidget {
  /// The configuration to provide
  final StoryEditorConfig config;

  const StoryEditorConfigProvider({
    super.key,
    required this.config,
    required super.child,
  });

  /// Get the config from context
  static StoryEditorConfig of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<StoryEditorConfigProvider>();
    return provider?.config ?? const StoryEditorConfig();
  }

  /// Get the config from context without listening to changes
  static StoryEditorConfig read(BuildContext context) {
    final provider = context.getInheritedWidgetOfExactType<StoryEditorConfigProvider>();
    return provider?.config ?? const StoryEditorConfig();
  }

  @override
  bool updateShouldNotify(StoryEditorConfigProvider oldWidget) {
    return config != oldWidget.config;
  }
}

/// Extension for easy access to config from BuildContext
extension StoryEditorConfigExtension on BuildContext {
  /// Get the full config
  StoryEditorConfig get storyEditorConfig => StoryEditorConfigProvider.of(this);

  /// Get localization strings
  StoryEditorStrings get storyStrings => storyEditorConfig.strings;

  /// Get theme configuration
  StoryEditorTheme get storyTheme => storyEditorConfig.theme;

  /// Get fonts configuration
  StoryEditorFonts get storyFonts => storyEditorConfig.fonts;

  /// Get settings callbacks
  StoryEditorSettings get storySettings => storyEditorConfig.settings;
}
