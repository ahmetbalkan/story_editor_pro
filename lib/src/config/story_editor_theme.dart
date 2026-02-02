import 'package:flutter/material.dart';
import 'story_editor_icons.dart';
import 'story_editor_gradients.dart';

/// Theme configuration for Story Editor Pro
class StoryEditorTheme {
  // ============ Primary Colors ============

  /// Primary color used throughout the editor (buttons, highlights)
  final Color primaryColor;

  /// Secondary color for accents
  final Color? secondaryColor;

  // ============ Background Colors ============

  /// Main background color
  final Color backgroundColor;

  /// Surface color for cards, dialogs
  final Color surfaceColor;

  /// Overlay color for darker surfaces
  final Color overlayColor;

  // ============ Text Colors ============

  /// Primary text color
  final Color textColor;

  /// Secondary/muted text color
  final Color textSecondaryColor;

  /// Hint text color
  final Color hintColor;

  // ============ State Colors ============

  /// Recording indicator color (red dot)
  final Color recordingColor;

  /// Switch/toggle active color
  final Color switchActiveColor;

  /// Error color
  final Color errorColor;

  /// Success color
  final Color successColor;

  // ============ Drawing Colors ============

  /// Color palette for drawing tools
  final List<Color> drawingColors;

  // ============ Boomerang Gradient ============

  /// Gradient colors for boomerang button/indicator
  final List<Color> boomerangGradientColors;

  // ============ Share Button ============

  /// Share button color (default: Instagram blue #0095F6)
  final Color shareButtonColor;

  // ============ Sub-configurations ============

  /// Icon configuration
  final StoryEditorIcons icons;

  /// Gradient presets configuration
  final StoryEditorGradients gradients;

  const StoryEditorTheme({
    // Primary Colors
    this.primaryColor = const Color(0xFFC13584),
    this.secondaryColor,

    // Background Colors
    this.backgroundColor = const Color(0xFF121212),
    this.surfaceColor = const Color(0xFF1E1E1E),
    this.overlayColor = const Color(0xFF2A2A2A),

    // Text Colors
    this.textColor = Colors.white,
    this.textSecondaryColor = Colors.white70,
    this.hintColor = Colors.white54,

    // State Colors
    this.recordingColor = const Color(0xFFFF3B30),
    this.switchActiveColor = const Color(0xFF007AFF),
    this.errorColor = Colors.red,
    this.successColor = const Color(0xFF1DB954),

    // Drawing Colors
    this.drawingColors = const [
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

    // Boomerang Gradient
    this.boomerangGradientColors = const [
      Color(0xFFF77737),
      Color(0xFFE1306C),
      Color(0xFFC13584),
    ],

    // Share Button
    this.shareButtonColor = const Color(0xFF0095F6),

    // Sub-configurations
    this.icons = const StoryEditorIcons(),
    this.gradients = const StoryEditorGradients(),
  });

  /// Create a copy with modified values
  StoryEditorTheme copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? overlayColor,
    Color? textColor,
    Color? textSecondaryColor,
    Color? hintColor,
    Color? recordingColor,
    Color? switchActiveColor,
    Color? errorColor,
    Color? successColor,
    List<Color>? drawingColors,
    List<Color>? boomerangGradientColors,
    Color? shareButtonColor,
    StoryEditorIcons? icons,
    StoryEditorGradients? gradients,
  }) {
    return StoryEditorTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      overlayColor: overlayColor ?? this.overlayColor,
      textColor: textColor ?? this.textColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      hintColor: hintColor ?? this.hintColor,
      recordingColor: recordingColor ?? this.recordingColor,
      switchActiveColor: switchActiveColor ?? this.switchActiveColor,
      errorColor: errorColor ?? this.errorColor,
      successColor: successColor ?? this.successColor,
      drawingColors: drawingColors ?? this.drawingColors,
      boomerangGradientColors: boomerangGradientColors ?? this.boomerangGradientColors,
      shareButtonColor: shareButtonColor ?? this.shareButtonColor,
      icons: icons ?? this.icons,
      gradients: gradients ?? this.gradients,
    );
  }
}
