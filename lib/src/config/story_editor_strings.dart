/// Localization strings for Story Editor Pro
/// All strings have English defaults and can be customized for any language
///
/// Naming convention: [screenName][elementName]
/// - settings* = Camera Settings Screen
/// - camera* = Camera Screen
/// - gradient* = Gradient Text Editor
/// - editor* = Story Editor Screen
class StoryEditorStrings {
  // ============ Camera Settings Screen ============
  final String settingsTitle;
  final String settingsControlsSection;
  final String settingsFrontCameraTitle;
  final String settingsFrontCameraSubtitle;
  final String settingsToolsSection;
  final String settingsToolbarPositionTitle;
  final String settingsToolbarPositionSubtitle;
  final String settingsLeftSide;
  final String settingsRightSide;

  // ============ Camera Screen ============
  final String cameraStory;
  final String cameraGallery;
  final String cameraCancel;
  final String cameraDelete;
  final String cameraSettings;
  final String cameraPermissionRequired;
  final String cameraPermissionDescription;
  final String cameraGrantPermission;
  final String cameraGalleryAccessDenied;
  final String cameraNoMediaInGallery;
  final String cameraNoImagesInGallery;
  final String cameraCouldNotOpenGallery;
  final String cameraCouldNotTakePhoto;
  final String cameraCouldNotStartVideo;
  final String cameraCouldNotCreateCollage;
  final String cameraCouldNotCreateBoomerang;
  final String cameraBoomerangProcessingError;
  final String cameraDeletePhoto;
  final String cameraDeletePhotoConfirmation;
  final String cameraCapture;
  final String cameraStartAfter;
  final String cameraProcessingImage;
  final String cameraProcessingVideo;
  final String cameraProcessing;
  final String cameraCreatingBoomerang;
  final String cameraPhoto;
  final String cameraVideo;
  final String cameraBoomerang;

  // ============ Gradient Text Editor ============
  final String gradientBalance;
  final String gradientWriteSomething;
  final String gradientProcessingImage;

  // ============ Story Editor Screen ============
  final String editorImageSettings;
  final String editorOk;
  final String editorShare;
  final String editorCloseFriends;
  final String editorPeopleCount;
  final String editorCouldNotSave;
  final String editorYourStory;
  final String editorFacebookStory;
  final String editorEnterText;
  final String editorSaved;
  final String editorSaving;
  final String editorSharing;

  // ============ Story Editor - Brush Types ============
  final String editorBrushNormal;
  final String editorBrushArrow;
  final String editorBrushMarker;
  final String editorBrushGlow;
  final String editorBrushEraser;
  final String editorBrushChalk;

  const StoryEditorStrings({
    // ─────────────────────────────────────────────────────────────
    // Camera Settings Screen
    // ─────────────────────────────────────────────────────────────
    this.settingsTitle = 'Settings',
    this.settingsControlsSection = 'Controls',
    this.settingsFrontCameraTitle = 'Front Camera Default',
    this.settingsFrontCameraSubtitle = 'Start with front camera when app opens',
    this.settingsToolsSection = 'Camera Tools',
    this.settingsToolbarPositionTitle = 'Toolbar Position',
    this.settingsToolbarPositionSubtitle = 'Choose which side of the screen boomerang, text editor, and frame tools appear.',
    this.settingsLeftSide = 'Left Side',
    this.settingsRightSide = 'Right Side',

    // ─────────────────────────────────────────────────────────────
    // Camera Screen
    // ─────────────────────────────────────────────────────────────
    this.cameraStory = 'Story',
    this.cameraGallery = 'Gallery',
    this.cameraCancel = 'Cancel',
    this.cameraDelete = 'Delete',
    this.cameraSettings = 'Settings',
    this.cameraPermissionRequired = 'Camera Permission Required',
    this.cameraPermissionDescription = 'We need camera access to create stories.',
    this.cameraGrantPermission = 'Grant Permission',
    this.cameraGalleryAccessDenied = 'Gallery access denied',
    this.cameraNoMediaInGallery = 'No media found in gallery',
    this.cameraNoImagesInGallery = 'No images found in gallery',
    this.cameraCouldNotOpenGallery = 'Could not open gallery',
    this.cameraCouldNotTakePhoto = 'Could not take photo',
    this.cameraCouldNotStartVideo = 'Could not start video',
    this.cameraCouldNotCreateCollage = 'Could not create collage',
    this.cameraCouldNotCreateBoomerang = 'Could not create boomerang',
    this.cameraBoomerangProcessingError = 'Error processing boomerang',
    this.cameraDeletePhoto = 'Delete Photo',
    this.cameraDeletePhotoConfirmation = 'Do you want to delete this photo?',
    this.cameraCapture = 'Capture',
    this.cameraStartAfter = 'Start after',
    this.cameraProcessingImage = 'Processing image...',
    this.cameraProcessingVideo = 'Processing video...',
    this.cameraProcessing = 'Processing...',
    this.cameraCreatingBoomerang = 'Creating boomerang...',
    this.cameraPhoto = 'Photo',
    this.cameraVideo = 'Video',
    this.cameraBoomerang = 'Boomerang',

    // ─────────────────────────────────────────────────────────────
    // Gradient Text Editor
    // ─────────────────────────────────────────────────────────────
    this.gradientBalance = 'Balance',
    this.gradientWriteSomething = 'Write something...',
    this.gradientProcessingImage = 'Processing image...',

    // ─────────────────────────────────────────────────────────────
    // Story Editor Screen
    // ─────────────────────────────────────────────────────────────
    this.editorImageSettings = 'Image Settings',
    this.editorOk = 'OK',
    this.editorShare = 'Share',
    this.editorCloseFriends = 'Close Friends',
    this.editorPeopleCount = '0 people',
    this.editorCouldNotSave = 'Could not save',
    this.editorYourStory = 'Your Story',
    this.editorFacebookStory = 'And Facebook Story',
    this.editorEnterText = 'Enter text...',
    this.editorSaved = 'Saved',
    this.editorSaving = 'Saving...',
    this.editorSharing = 'Sharing...',

    // ─────────────────────────────────────────────────────────────
    // Story Editor - Brush Types
    // ─────────────────────────────────────────────────────────────
    this.editorBrushNormal = 'Normal',
    this.editorBrushArrow = 'Arrow',
    this.editorBrushMarker = 'Marker',
    this.editorBrushGlow = 'Glow',
    this.editorBrushEraser = 'Eraser',
    this.editorBrushChalk = 'Chalk',
  });

  /// Format capture text: "Capture: 1/4"
  String formatCaptureText(int current, int total) => '$cameraCapture: $current/$total';

  /// Format start after text: "Start after 3s"
  String formatStartAfter(int seconds) => '$cameraStartAfter ${seconds}s';

  /// Format people count: "5 people"
  String formatPeopleCount(int count) => '$count people';

  /// Format error with details
  String formatError(String baseError, String details) => '$baseError: $details';
}
