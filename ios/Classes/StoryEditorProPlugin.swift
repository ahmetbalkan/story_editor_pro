import Flutter
import UIKit
import AVFoundation
import Photos

public class StoryEditorProPlugin: NSObject, FlutterPlugin {
    private var registrar: FlutterPluginRegistrar?
    private var textureRegistry: FlutterTextureRegistry?
    private var cameraManager: CameraManager?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "story_editor_pro", binaryMessenger: registrar.messenger())
        let instance = StoryEditorProPlugin()
        instance.registrar = registrar
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private var boomerangProcessor: BoomerangProcessor?
    private var videoOverlayProcessor: VideoOverlayProcessor?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            checkPermission(result: result)
        case "requestPermission":
            requestPermission(result: result)
        case "checkGalleryPermission":
            checkGalleryPermission(result: result)
        case "requestGalleryPermission":
            requestGalleryPermission(result: result)
        case "initializeCamera":
            let args = call.arguments as? [String: Any]
            let facing = args?["facing"] as? String ?? "back"
            initializeCamera(facing: facing, result: result)
        case "takePicture":
            takePicture(result: result)
        case "switchCamera":
            switchCamera(result: result)
        case "setFlashMode":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? String ?? "off"
            setFlashMode(mode: mode, result: result)
        case "setZoomLevel":
            let args = call.arguments as? [String: Any]
            let level = args?["level"] as? Double ?? 1.0
            setZoomLevel(level: level, result: result)
        case "getLastGalleryImage":
            getLastGalleryImage(result: result)
        case "createBoomerang":
            createBoomerang(call: call, result: result)
        case "createBoomerangFromFrames":
            createBoomerangFromFrames(call: call, result: result)
        case "exportVideoWithOverlay":
            exportVideoWithOverlay(call: call, result: result)
        case "dispose":
            dispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func exportVideoWithOverlay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let overlayImagePath = args["overlayImagePath"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS",
                   message: "videoPath, overlayImagePath and outputPath are required",
                   details: nil))
            return
        }

        if videoOverlayProcessor == nil {
            videoOverlayProcessor = VideoOverlayProcessor()
        }

        videoOverlayProcessor?.exportVideoWithOverlay(
            videoPath: videoPath,
            overlayImagePath: overlayImagePath,
            outputPath: outputPath
        ) { output in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "EXPORT_FAILED",
                       message: "Failed to export video with overlay",
                       details: nil))
            }
        }
    }

    private func createBoomerang(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "inputPath and outputPath are required", details: nil))
            return
        }

        let loopCount = args["loopCount"] as? Int ?? 3
        let fps = args["fps"] as? Int ?? 30

        if boomerangProcessor == nil {
            boomerangProcessor = BoomerangProcessor()
        }

        boomerangProcessor?.createBoomerang(
            inputPath: inputPath,
            outputPath: outputPath,
            loopCount: loopCount,
            fps: fps
        ) { output in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "BOOMERANG_FAILED", message: "Failed to create boomerang", details: nil))
            }
        }
    }

    private func createBoomerangFromFrames(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let frameDir = args["frameDir"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "frameDir and outputPath are required", details: nil))
            return
        }

        let fps = args["fps"] as? Int ?? 30
        let loopCount = args["loopCount"] as? Int ?? 3

        if boomerangProcessor == nil {
            boomerangProcessor = BoomerangProcessor()
        }

        boomerangProcessor?.createBoomerangFromFrames(
            frameDir: frameDir,
            outputPath: outputPath,
            fps: fps,
            loopCount: loopCount
        ) { output in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "BOOMERANG_FAILED", message: "Failed to create boomerang from frames", details: nil))
            }
        }
    }

    private func getLastGalleryImage(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async {
                    result(nil)
                }
                return
            }

            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat

            manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: options) { image, _ in
                guard let image = image, let data = image.jpegData(compressionQuality: 0.8) else {
                    DispatchQueue.main.async {
                        result(nil)
                    }
                    return
                }

                let tempDir = NSTemporaryDirectory()
                let fileName = "last_gallery_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                let filePath = (tempDir as NSString).appendingPathComponent(fileName)

                do {
                    try data.write(to: URL(fileURLWithPath: filePath))
                    DispatchQueue.main.async {
                        result(filePath)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "GALLERY_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func checkPermission(result: @escaping FlutterResult) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        result(status == .authorized)
    }

    private func requestPermission(result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }

    private func checkGalleryPermission(result: @escaping FlutterResult) {
        let status = PHPhotoLibrary.authorizationStatus()
        result(status == .authorized || status == .limited)
    }

    private func requestGalleryPermission(result: @escaping FlutterResult) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                result(status == .authorized || status == .limited)
            }
        }
    }

    private func initializeCamera(facing: String, result: @escaping FlutterResult) {
        guard let textureRegistry = textureRegistry else {
            result(FlutterError(code: "NO_TEXTURE_REGISTRY", message: "Texture registry not available", details: nil))
            return
        }

        let position: AVCaptureDevice.Position = facing == "front" ? .front : .back

        cameraManager = CameraManager(textureRegistry: textureRegistry, position: position)
        cameraManager?.initialize { [weak self] textureId, width, height, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "CAMERA_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result([
                        "textureId": textureId,
                        "previewWidth": width,
                        "previewHeight": height
                    ])
                }
            }
        }
    }

    private func takePicture(result: @escaping FlutterResult) {
        cameraManager?.takePicture { path, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(path)
                }
            }
        }
    }

    private func switchCamera(result: @escaping FlutterResult) {
        cameraManager?.switchCamera { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(success)
                }
            }
        }
    }

    private func setFlashMode(mode: String, result: @escaping FlutterResult) {
        cameraManager?.setFlashMode(mode: mode)
        result(true)
    }

    private func setZoomLevel(level: Double, result: @escaping FlutterResult) {
        cameraManager?.setZoomLevel(level: CGFloat(level))
        result(true)
    }

    private func dispose(result: @escaping FlutterResult) {
        cameraManager?.dispose()
        cameraManager = nil
        result(true)
    }
}

class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentPosition: AVCaptureDevice.Position

    private var textureRegistry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    private var pixelBuffer: CVPixelBuffer?
    private var latestPixelBuffer: CVPixelBuffer?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var photoCompletionHandler: ((String?, Error?) -> Void)?

    init(textureRegistry: FlutterTextureRegistry, position: AVCaptureDevice.Position) {
        self.textureRegistry = textureRegistry
        self.currentPosition = position
        super.init()
    }

    func initialize(completion: @escaping (Int64, Int, Int, Error?) -> Void) {
        sessionQueue.async { [weak self] in
            self?.setupCamera(completion: completion)
        }
    }

    private func setupCamera(completion: @escaping (Int64, Int, Int, Error?) -> Void) {
        captureSession = AVCaptureSession()

        // YÜKSEK KALİTE: 1080p Full HD preset
        if captureSession?.canSetSessionPreset(.hd1920x1080) == true {
            captureSession?.sessionPreset = .hd1920x1080
        } else if captureSession?.canSetSessionPreset(.high) == true {
            captureSession?.sessionPreset = .high
        } else {
            captureSession?.sessionPreset = .photo
        }

        guard let device = getCamera(for: currentPosition) else {
            completion(-1, 0, 0, NSError(domain: "CameraManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera not available"]))
            return
        }

        currentDevice = device

        // Kamera cihazını 1080p için optimize et
        configureCameraForHighQuality(device: device)

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }

            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1080,
                kCVPixelBufferHeightKey as String: 1920
            ]
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.video.queue"))
            // Yüksek kalite için frame drop'u engelle
            videoOutput?.alwaysDiscardsLateVideoFrames = false

            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }

            photoOutput = AVCapturePhotoOutput()
            // Yüksek çözünürlüklü fotoğraf yakala
            photoOutput?.isHighResolutionCaptureEnabled = true
            if captureSession?.canAddOutput(photoOutput!) == true {
                captureSession?.addOutput(photoOutput!)
            }

            if let connection = videoOutput?.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if currentPosition == .front && connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            textureId = textureRegistry.register(self)

            captureSession?.startRunning()

            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            completion(textureId, Int(dimensions.width), Int(dimensions.height), nil)

        } catch {
            completion(-1, 0, 0, error)
        }
    }

    // Kamerayı yüksek kalite için yapılandır
    private func configureCameraForHighQuality(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // En iyi 1080p formatını bul
            let targetWidth: Int32 = 1920
            let targetHeight: Int32 = 1080

            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

                // 1080p veya daha yüksek çözünürlük
                if dimensions.width >= targetWidth && dimensions.height >= targetHeight {
                    for range in format.videoSupportedFrameRateRanges {
                        if range.maxFrameRate >= 30 {
                            if bestFormat == nil {
                                bestFormat = format
                                bestFrameRateRange = range
                            } else {
                                // Daha uygun boyut bul (1080p'ye yakın)
                                let currentDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription)
                                if dimensions.width <= currentDimensions.width {
                                    bestFormat = format
                                    bestFrameRateRange = range
                                }
                            }
                        }
                    }
                }
            }

            if let format = bestFormat, let frameRateRange = bestFrameRateRange {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(min(frameRateRange.maxFrameRate, 30)))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(min(frameRateRange.maxFrameRate, 30)))
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure camera for high quality: \(error)")
        }
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first
    }

    func takePicture(completion: @escaping (String?, Error?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil, NSError(domain: "CameraManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Photo output not available"]))
            return
        }

        photoCompletionHandler = completion

        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func switchCamera(completion: @escaping (Bool, Error?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else {
                completion(false, NSError(domain: "CameraManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Session not available"]))
                return
            }

            session.beginConfiguration()

            // Remove current input
            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }

            // Switch position
            self.currentPosition = self.currentPosition == .back ? .front : .back

            guard let newDevice = self.getCamera(for: self.currentPosition) else {
                session.commitConfiguration()
                completion(false, NSError(domain: "CameraManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "New camera not available"]))
                return
            }

            self.currentDevice = newDevice

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                }

                if let connection = self.videoOutput?.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if self.currentPosition == .front && connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    } else {
                        connection.isVideoMirrored = false
                    }
                }

                session.commitConfiguration()
                completion(true, nil)
            } catch {
                session.commitConfiguration()
                completion(false, error)
            }
        }
    }

    func setFlashMode(mode: String) {
        // Flash mode is set during photo capture
    }

    func setZoomLevel(level: CGFloat) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            device.videoZoomFactor = min(max(level, 1.0), maxZoom)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }

    func dispose() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            if let textureId = self?.textureId, textureId >= 0 {
                self?.textureRegistry.unregisterTexture(textureId)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pixelBuffer
        textureRegistry.textureFrameAvailable(textureId)
    }
}

extension CameraManager: FlutterTexture {
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCompletionHandler?(nil, error)
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            photoCompletionHandler?(nil, NSError(domain: "CameraManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data"]))
            return
        }

        let tempDir = NSTemporaryDirectory()
        let fileName = "story_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)

        do {
            try imageData.write(to: URL(fileURLWithPath: filePath))
            photoCompletionHandler?(filePath, nil)
        } catch {
            photoCompletionHandler?(nil, error)
        }
    }
}
