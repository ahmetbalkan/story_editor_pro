package com.storyeditorpro

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.view.Surface
import androidx.camera.core.*
import androidx.camera.video.*
import androidx.camera.video.VideoCapture
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class StoryEditorProPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private lateinit var textureRegistry: TextureRegistry

    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService? = null

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var previewWidth = 0
    private var previewHeight = 0

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1001
        private const val GALLERY_PERMISSION_REQUEST_CODE = 1002
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "story_editor_pro")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        textureRegistry = flutterPluginBinding.textureRegistry
        cameraExecutor = Executors.newSingleThreadExecutor()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkPermission" -> checkPermission(result)
            "requestPermission" -> requestPermission(result)
            "checkGalleryPermission" -> checkGalleryPermission(result)
            "requestGalleryPermission" -> requestGalleryPermission(result)
            "initializeCamera" -> initializeCamera(call, result)
            "takePicture" -> takePicture(result)
            "switchCamera" -> switchCamera(result)
            "setFlashMode" -> setFlashMode(call, result)
            "setZoomLevel" -> setZoomLevel(call, result)
            "getLastGalleryImage" -> getLastGalleryImage(result)
            "startVideoRecording" -> startVideoRecording(call, result)
            "stopVideoRecording" -> stopVideoRecording(result)
            "createBoomerang" -> createBoomerang(call, result)
            "createBoomerangFromFrames" -> createBoomerangFromFrames(call, result)
            "exportVideoWithOverlay" -> exportVideoWithOverlay(call, result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    private fun createBoomerang(call: MethodCall, result: Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val loopCount = call.argument<Int>("loopCount") ?: 3
        val fps = call.argument<Int>("fps") ?: 30

        if (inputPath == null || outputPath == null) {
            result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
            return
        }

        // Background thread'de işle
        cameraExecutor?.execute {
            try {
                val processor = BoomerangProcessor()
                val output = processor.createBoomerang(
                    inputPath = inputPath,
                    outputPath = outputPath,
                    loopCount = loopCount,
                    fps = fps
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("BOOMERANG_FAILED", "Failed to create boomerang", null)
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("BOOMERANG_ERROR", e.message, null)
                }
            }
        }
    }

    private fun createBoomerangFromFrames(call: MethodCall, result: Result) {
        val frameDir = call.argument<String>("frameDir")
        val outputPath = call.argument<String>("outputPath")
        val fps = call.argument<Int>("fps") ?: 30
        val loopCount = call.argument<Int>("loopCount") ?: 3

        if (frameDir == null || outputPath == null) {
            result.error("INVALID_ARGS", "frameDir and outputPath are required", null)
            return
        }

        // Background thread'de işle
        cameraExecutor?.execute {
            try {
                val processor = BoomerangProcessor()
                val output = processor.createBoomerangFromFrames(
                    frameDir = frameDir,
                    outputPath = outputPath,
                    fps = fps,
                    loopCount = loopCount
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("BOOMERANG_FAILED", "Failed to create boomerang from frames", null)
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("BOOMERANG_ERROR", e.message, null)
                }
            }
        }
    }

    private fun getLastGalleryImage(result: Result) {
        activity?.runOnUiThread {
            try {
                val projection = arrayOf(
                    android.provider.MediaStore.Images.Media._ID,
                    android.provider.MediaStore.Images.Media.DATA
                )
                val cursor = context.contentResolver.query(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    null,
                    null,
                    "${android.provider.MediaStore.Images.Media.DATE_ADDED} DESC"
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        val columnIndex = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATA)
                        val imagePath = it.getString(columnIndex)
                        result.success(imagePath)
                    } else {
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                result.error("GALLERY_ERROR", "Failed to get last image: ${e.message}", null)
            }
        }
    }

    private fun checkPermission(result: Result) {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        result.success(hasPermission)
    }

    private fun requestPermission(result: Result) {
        activity?.let {
            ActivityCompat.requestPermissions(
                it,
                arrayOf(android.Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST_CODE
            )
            result.success(true)
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun checkGalleryPermission(result: Result) {
        val hasPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.READ_MEDIA_IMAGES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
        result.success(hasPermission)
    }

    private fun requestGalleryPermission(result: Result) {
        activity?.let {
            val permission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                android.Manifest.permission.READ_MEDIA_IMAGES
            } else {
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            }
            ActivityCompat.requestPermissions(
                it,
                arrayOf(permission),
                GALLERY_PERMISSION_REQUEST_CODE
            )
            result.success(true)
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun initializeCamera(call: MethodCall, result: Result) {
        val facing = call.argument<String>("facing") ?: "back"
        lensFacing = if (facing == "front") CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK

        activity?.let { act ->
            val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

            cameraProviderFuture.addListener({
                try {
                    cameraProvider = cameraProviderFuture.get()

                    textureEntry = textureRegistry.createSurfaceTexture()
                    val surfaceTexture = textureEntry!!.surfaceTexture()

                    val rotation = act.windowManager.defaultDisplay.rotation
                    val targetRotation = when (rotation) {
                        Surface.ROTATION_0 -> Surface.ROTATION_0
                        Surface.ROTATION_90 -> Surface.ROTATION_90
                        Surface.ROTATION_180 -> Surface.ROTATION_180
                        Surface.ROTATION_270 -> Surface.ROTATION_270
                        else -> Surface.ROTATION_0
                    }

                    // Hedef çözünürlük: 1080x1920 (Full HD Portrait)
                    previewWidth = 1080
                    previewHeight = 1920

                    // Preview - YÜKSEK KALİTE için targetResolution belirt
                    preview = Preview.Builder()
                        .setTargetResolution(android.util.Size(1080, 1920))
                        .setTargetRotation(targetRotation)
                        .build()
                        .also {
                            it.setSurfaceProvider { request ->
                                val width = request.resolution.width
                                val height = request.resolution.height

                                surfaceTexture.setDefaultBufferSize(width, height)
                                val surface = Surface(surfaceTexture)
                                request.provideSurface(surface, cameraExecutor!!) { }

                                // Preview boyutunu güncelle
                                previewWidth = width
                                previewHeight = height
                            }
                        }

                    // ImageCapture - MAXIMUM QUALITY + 1080p hedef
                    imageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                        .setTargetResolution(android.util.Size(1080, 1920))
                        .setTargetRotation(targetRotation)
                        .build()

                    // Video recording - FHD (1080p) kalite
                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.fromOrderedList(
                                listOf(Quality.FHD, Quality.HD, Quality.SD),
                                FallbackStrategy.higherQualityOrLowerThan(Quality.FHD)
                            )
                        )
                        .build()
                    videoCapture = VideoCapture.withOutput(recorder)

                    val cameraSelector = CameraSelector.Builder()
                        .requireLensFacing(lensFacing)
                        .build()

                    cameraProvider?.unbindAll()

                    camera = cameraProvider?.bindToLifecycle(
                        act as LifecycleOwner,
                        cameraSelector,
                        preview,
                        imageCapture,
                        videoCapture
                    )

                    val resultMap = hashMapOf<String, Any>(
                        "textureId" to textureEntry!!.id(),
                        "previewWidth" to previewWidth,
                        "previewHeight" to previewHeight
                    )

                    result.success(resultMap)
                } catch (e: Exception) {
                    result.error("CAMERA_ERROR", "Failed to initialize camera: ${e.message}", null)
                }
            }, ContextCompat.getMainExecutor(context))
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun takePicture(result: Result) {
        val imageCapture = imageCapture ?: run {
            result.error("CAMERA_NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        val photoFile = File(context.cacheDir, "story_${System.currentTimeMillis()}.jpg")

        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

        imageCapture.takePicture(
            outputOptions,
            cameraExecutor!!,
            object : ImageCapture.OnImageSavedCallback {
                override fun onError(exc: ImageCaptureException) {
                    activity?.runOnUiThread {
                        result.error("CAPTURE_ERROR", "Failed to capture image: ${exc.message}", null)
                    }
                }

                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    val correctedPath = correctImageOrientation(photoFile.absolutePath)
                    activity?.runOnUiThread {
                        result.success(correctedPath)
                    }
                }
            }
        )
    }

    private fun correctImageOrientation(imagePath: String): String {
        try {
            val exif = ExifInterface(imagePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            val bitmap = BitmapFactory.decodeFile(imagePath)
            val matrix = Matrix()

            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            }

            if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                matrix.preScale(-1f, 1f)
            }

            val rotatedBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )

            FileOutputStream(imagePath).use { out ->
                rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            }

            bitmap.recycle()
            rotatedBitmap.recycle()

        } catch (e: Exception) {
            e.printStackTrace()
        }
        return imagePath
    }

    private fun switchCamera(result: Result) {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }

        activity?.let { act ->
            try {
                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()

                cameraProvider?.unbindAll()

                camera = cameraProvider?.bindToLifecycle(
                    act as LifecycleOwner,
                    cameraSelector,
                    preview,
                    imageCapture
                )

                result.success(true)
            } catch (e: Exception) {
                result.error("SWITCH_ERROR", "Failed to switch camera: ${e.message}", null)
            }
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun setFlashMode(call: MethodCall, result: Result) {
        val mode = call.argument<String>("mode") ?: "off"
        val flashMode = when (mode) {
            "on" -> ImageCapture.FLASH_MODE_ON
            "auto" -> ImageCapture.FLASH_MODE_AUTO
            else -> ImageCapture.FLASH_MODE_OFF
        }
        imageCapture?.flashMode = flashMode
        result.success(true)
    }

    private fun setZoomLevel(call: MethodCall, result: Result) {
        val level = call.argument<Double>("level") ?: 1.0
        camera?.cameraControl?.setZoomRatio(level.toFloat())
        result.success(true)
    }

    private fun exportVideoWithOverlay(call: MethodCall, result: Result) {
        val videoPath = call.argument<String>("videoPath")
        val overlayImagePath = call.argument<String>("overlayImagePath")
        val outputPath = call.argument<String>("outputPath")

        if (videoPath == null || overlayImagePath == null || outputPath == null) {
            result.error("INVALID_ARGS",
                "videoPath, overlayImagePath and outputPath are required", null)
            return
        }

        // Use a dedicated thread (cameraExecutor may be null if camera is disposed)
        Thread {
            try {
                val processor = VideoOverlayProcessor()
                val output = processor.exportVideoWithOverlay(
                    videoPath = videoPath,
                    overlayImagePath = overlayImagePath,
                    outputPath = outputPath
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("EXPORT_FAILED",
                            "Failed to export video with overlay", null)
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("EXPORT_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private var videoResultCallback: Result? = null
    private var currentVideoPath: String? = null

    @androidx.annotation.OptIn(androidx.camera.video.ExperimentalPersistentRecording::class)
    private fun startVideoRecording(call: MethodCall, result: Result) {
        val outputPath = call.argument<String>("outputPath")
        if (outputPath == null) {
            result.error("INVALID_ARGS", "Output path required", null)
            return
        }

        if (videoCapture == null) {
            result.error("NOT_INITIALIZED", "Video capture not initialized", null)
            return
        }

        if (recording != null) {
            result.error("ALREADY_RECORDING", "Already recording", null)
            return
        }

        currentVideoPath = outputPath
        val outputFile = File(outputPath)
        val outputOptions = FileOutputOptions.Builder(outputFile).build()

        recording = videoCapture!!.output
            .prepareRecording(context, outputOptions)
            .start(ContextCompat.getMainExecutor(context)) { event ->
                when (event) {
                    is VideoRecordEvent.Start -> {
                        // Recording started
                    }
                    is VideoRecordEvent.Finalize -> {
                        if (event.hasError()) {
                            videoResultCallback?.error("RECORDING_ERROR", "Recording failed: ${event.cause?.message}", null)
                        } else {
                            videoResultCallback?.success(currentVideoPath)
                        }
                        videoResultCallback = null
                        recording = null
                    }
                }
            }

        result.success(true)
    }

    private fun stopVideoRecording(result: Result) {
        if (recording == null) {
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        videoResultCallback = result
        recording?.stop()
    }

    private fun dispose(result: Result) {
        recording?.stop()
        recording = null
        cameraProvider?.unbindAll()
        textureEntry?.release()
        cameraExecutor?.shutdown()
        result.success(true)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        cameraProvider?.unbindAll()
        textureEntry?.release()
        cameraExecutor?.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
