package com.storyeditorpro

import android.graphics.*
import android.graphics.SurfaceTexture
import android.media.*
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

/**
 * GPU-accelerated video overlay compositor (no FFmpeg).
 *
 * Pipeline:
 *   MediaExtractor → MediaCodec decoder → SurfaceTexture (GPU texture)
 *   → OpenGL: blend video + overlay textures → encoder Surface
 *   → MediaCodec encoder → MediaMuxer
 *
 * No CPU pixel copying. No YUV conversion. No JPEG encode/decode.
 * Entire compositing runs on GPU via OpenGL ES 2.0.
 * Audio is passthrough-muxed in single pass (no temp file).
 */
class VideoOverlayProcessor {

    companion object {
        private const val TAG = "VideoOverlayProcessor"
        private const val TIMEOUT_US = 2500L // Low timeout for aggressive polling
    }

    fun exportVideoWithOverlay(
        videoPath: String,
        overlayImagePath: String,
        outputPath: String,
        onProgress: ((Double) -> Unit)? = null
    ): String? {
        Log.d(TAG, "========================================")
        Log.d(TAG, "Starting GPU-accelerated video overlay export")
        Log.d(TAG, "Video: $videoPath")
        Log.d(TAG, "Overlay: $overlayImagePath")
        Log.d(TAG, "Output: $outputPath")
        Log.d(TAG, "========================================")

        if (!File(videoPath).exists()) {
            Log.e(TAG, "Video file does not exist")
            return null
        }

        val overlayDecodeStart = System.currentTimeMillis()
        val overlayBitmap = BitmapFactory.decodeFile(overlayImagePath)
        if (overlayBitmap == null) {
            Log.e(TAG, "Failed to decode overlay image")
            return null
        }
        Log.d(TAG, "Overlay decoded: ${overlayBitmap.width}x${overlayBitmap.height} in ${System.currentTimeMillis() - overlayDecodeStart}ms")

        File(outputPath).delete()

        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var renderer: TextureRenderer? = null
        var decoderSurfaceTexture: SurfaceTexture? = null
        var decoderSurface: Surface? = null
        var muxerStarted = false
        var videoMuxTrackIndex = -1
        var audioMuxTrackIndex = -1

        try {
            val startTime = System.currentTimeMillis()

            // 1. Extract video metadata
            videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)

            val videoTrackIndex = findTrack(videoExtractor, "video/")
            if (videoTrackIndex < 0) {
                Log.e(TAG, "No video track found")
                overlayBitmap.recycle()
                return null
            }

            videoExtractor.selectTrack(videoTrackIndex)
            val inputFormat = videoExtractor.getTrackFormat(videoTrackIndex)

            val inputWidth = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
            val inputHeight = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
            val rotation = if (inputFormat.containsKey(MediaFormat.KEY_ROTATION)) {
                inputFormat.getInteger(MediaFormat.KEY_ROTATION)
            } else 0
            val durationUs = if (inputFormat.containsKey(MediaFormat.KEY_DURATION)) {
                inputFormat.getLong(MediaFormat.KEY_DURATION)
            } else 0L
            val frameRate = if (inputFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE)
            } else 30

            // Output dimensions (swap if rotated 90/270)
            val outputWidth: Int
            val outputHeight: Int
            if (rotation == 90 || rotation == 270) {
                outputWidth = (inputHeight / 16) * 16
                outputHeight = (inputWidth / 16) * 16
            } else {
                outputWidth = (inputWidth / 16) * 16
                outputHeight = (inputHeight / 16) * 16
            }

            Log.d(TAG, "Input: ${inputWidth}x${inputHeight}, rotation=$rotation")
            Log.d(TAG, "Output: ${outputWidth}x${outputHeight}, fps=$frameRate, duration=${durationUs/1000}ms")

            // Scale overlay with aspect ratio preserved (cover + center crop)
            val scaledOverlay = scaleOverlayCoverCrop(overlayBitmap, outputWidth, outputHeight)
            overlayBitmap.recycle()

            onProgress?.invoke(0.05)

            // 2. Setup encoder (lower bitrate for faster encoding)
            val bitRate = minOf(4_000_000, outputWidth * outputHeight * 2) // 4Mbps max, adaptive
            val encoderFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, outputWidth, outputHeight
            ).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            }

            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val encoderInputSurface = encoder.createInputSurface()
            encoder.start()

            // 3. Setup OpenGL renderer (connects to encoder's Surface)
            renderer = TextureRenderer()
            renderer.init(encoderInputSurface, outputWidth, outputHeight)
            renderer.setOverlayBitmap(scaledOverlay)
            scaledOverlay.recycle()

            // 4. Setup decoder (output to SurfaceTexture → OES texture on GPU)
            decoderSurfaceTexture = SurfaceTexture(renderer.getVideoTextureId())
            decoderSurfaceTexture.setDefaultBufferSize(inputWidth, inputHeight)
            decoderSurface = Surface(decoderSurfaceTexture)

            decoder = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(inputFormat, decoderSurface, null, 0) // Decode directly to Surface (GPU)
            decoder.start()

            // 5. Setup muxer - directly to output (single pass with audio)
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            // 5b. Setup audio extractor for single-pass muxing
            audioExtractor = MediaExtractor()
            audioExtractor.setDataSource(videoPath)
            val audioTrackIndex = findTrack(audioExtractor, "audio/")
            var hasAudio = false
            var audioFormat: MediaFormat? = null
            if (audioTrackIndex >= 0) {
                audioExtractor.selectTrack(audioTrackIndex)
                audioFormat = audioExtractor.getTrackFormat(audioTrackIndex)
                hasAudio = true
                Log.d(TAG, "Audio track found, will mux in single pass")
            }

            val decoderBufferInfo = MediaCodec.BufferInfo()
            val encoderBufferInfo = MediaCodec.BufferInfo()

            var inputDone = false
            var decoderDone = false
            var frameCount = 0
            val totalFrames = if (durationUs > 0) (durationUs * frameRate / 1_000_000).toInt() else 100

            // Frame available synchronization
            val frameSyncObject = Object()
            var frameAvailable = false

            decoderSurfaceTexture.setOnFrameAvailableListener {
                synchronized(frameSyncObject) {
                    frameAvailable = true
                    frameSyncObject.notifyAll()
                }
            }

            val setupTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "Setup complete in ${setupTime}ms, starting GPU pipeline (single-pass)...")

            // 6. Main decode-render-encode loop (aggressive polling)
            while (!decoderDone) {
                // Feed as many input buffers as possible (non-blocking)
                if (!inputDone) {
                    var feedMore = true
                    while (feedMore) {
                        val inputBufIndex = decoder.dequeueInputBuffer(0) // Non-blocking
                        if (inputBufIndex >= 0) {
                            val inputBuf = decoder.getInputBuffer(inputBufIndex)!!
                            val sampleSize = videoExtractor.readSampleData(inputBuf, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(inputBufIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                                feedMore = false
                            } else {
                                decoder.queueInputBuffer(inputBufIndex, 0, sampleSize,
                                    videoExtractor.sampleTime, 0)
                                videoExtractor.advance()
                            }
                        } else {
                            feedMore = false
                        }
                    }
                }

                // Get decoded output
                val decoderStatus = decoder.dequeueOutputBuffer(decoderBufferInfo, TIMEOUT_US)
                when {
                    decoderStatus == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // Also drain encoder while waiting for decoder
                        drainEncoder(encoder, encoderBufferInfo, muxer!!, videoMuxTrackIndex, audioMuxTrackIndex, muxerStarted, hasAudio, audioFormat).let {
                            videoMuxTrackIndex = it.first
                            audioMuxTrackIndex = it.second
                            muxerStarted = it.third
                        }
                    }
                    decoderStatus == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(TAG, "Decoder format changed")
                    }
                    decoderStatus >= 0 -> {
                        val isEos = (decoderBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        val doRender = decoderBufferInfo.size > 0

                        // Release output buffer to Surface (renders to SurfaceTexture on GPU)
                        decoder.releaseOutputBuffer(decoderStatus, doRender)

                        if (doRender) {
                            // Wait for frame to arrive at SurfaceTexture
                            synchronized(frameSyncObject) {
                                while (!frameAvailable) {
                                    frameSyncObject.wait(2000)
                                    if (!frameAvailable) {
                                        Log.w(TAG, "Frame wait timeout")
                                        break
                                    }
                                }
                                frameAvailable = false
                            }

                            // GPU render: video texture + overlay texture → encoder surface
                            val presentationTimeNs = decoderBufferInfo.presentationTimeUs * 1000L
                            renderer.drawFrame(decoderSurfaceTexture, presentationTimeNs)

                            frameCount++
                            if (frameCount % 30 == 0 || frameCount == 1) {
                                onProgress?.invoke(0.05 + 0.90 * frameCount / maxOf(totalFrames, 1))
                            }
                        }

                        if (isEos) {
                            encoder.signalEndOfInputStream()
                            decoderDone = true
                            Log.d(TAG, "Decoder EOS, total frames: $frameCount")
                        }

                        // Drain encoder output
                        drainEncoder(encoder, encoderBufferInfo, muxer!!, videoMuxTrackIndex, audioMuxTrackIndex, muxerStarted, hasAudio, audioFormat).let {
                            videoMuxTrackIndex = it.first
                            audioMuxTrackIndex = it.second
                            muxerStarted = it.third
                        }
                    }
                }
            }

            // Final encoder drain
            drainEncoderFinal(encoder, encoderBufferInfo, muxer!!, videoMuxTrackIndex, muxerStarted)

            val encodeTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "GPU encode complete: $frameCount frames in ${encodeTime}ms (${if (encodeTime > 0) frameCount * 1000 / encodeTime else 0} fps)")

            // 7. Mux audio samples directly (single pass - no temp file)
            if (hasAudio && audioMuxTrackIndex >= 0) {
                val audioBuf = ByteBuffer.allocate(256 * 1024)
                val audioInfo = MediaCodec.BufferInfo()
                var audioSamples = 0
                while (true) {
                    val size = audioExtractor.readSampleData(audioBuf, 0)
                    if (size < 0) break
                    audioInfo.offset = 0
                    audioInfo.size = size
                    audioInfo.presentationTimeUs = audioExtractor.sampleTime
                    audioInfo.flags = audioExtractor.sampleFlags
                    muxer.writeSampleData(audioMuxTrackIndex, audioBuf, audioInfo)
                    audioExtractor.advance()
                    audioSamples++
                }
                Log.d(TAG, "Audio muxed: $audioSamples samples")
            }

            // Cleanup
            renderer.release(); renderer = null
            decoderSurfaceTexture.release(); decoderSurfaceTexture = null
            decoderSurface?.release(); decoderSurface = null
            try { decoder.stop(); decoder.release() } catch (_: Exception) {}
            try { encoder.stop(); encoder.release() } catch (_: Exception) {}
            try { if (muxerStarted) muxer.stop(); muxer.release() } catch (_: Exception) {}
            videoExtractor.release()
            audioExtractor?.release()
            decoder = null; encoder = null; muxer = null; videoExtractor = null; audioExtractor = null

            val totalTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "Export complete in ${totalTime}ms!")
            onProgress?.invoke(1.0)
            return outputPath

        } catch (e: Exception) {
            Log.e(TAG, "Export failed", e)
            return null
        } finally {
            try { renderer?.release() } catch (_: Exception) {}
            try { decoderSurfaceTexture?.release() } catch (_: Exception) {}
            try { decoderSurface?.release() } catch (_: Exception) {}
            try { decoder?.stop(); decoder?.release() } catch (_: Exception) {}
            try { encoder?.stop(); encoder?.release() } catch (_: Exception) {}
            try { if (muxerStarted) muxer?.stop(); muxer?.release() } catch (_: Exception) {}
            try { videoExtractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
        }
    }

    /**
     * Scale overlay with cover + center crop to preserve aspect ratio
     */
    private fun scaleOverlayCoverCrop(overlay: Bitmap, targetWidth: Int, targetHeight: Int): Bitmap {
        val srcRatio = overlay.width.toFloat() / overlay.height
        val dstRatio = targetWidth.toFloat() / targetHeight

        val scaledWidth: Int
        val scaledHeight: Int
        if (srcRatio > dstRatio) {
            scaledHeight = targetHeight
            scaledWidth = (overlay.width.toFloat() * targetHeight / overlay.height).toInt()
        } else {
            scaledWidth = targetWidth
            scaledHeight = (overlay.height.toFloat() * targetWidth / overlay.width).toInt()
        }

        val scaled = Bitmap.createScaledBitmap(overlay, scaledWidth, scaledHeight, true)
        val cropX = (scaledWidth - targetWidth) / 2
        val cropY = (scaledHeight - targetHeight) / 2
        val result = Bitmap.createBitmap(scaled, cropX, cropY, targetWidth, targetHeight)
        if (result !== scaled) scaled.recycle()

        Log.d(TAG, "Overlay: ${overlay.width}x${overlay.height} → ${targetWidth}x${targetHeight}")
        return result
    }

    private fun drainEncoder(
        encoder: MediaCodec, bufferInfo: MediaCodec.BufferInfo,
        muxer: MediaMuxer, videoTrackIndex: Int, audioTrackIndex: Int,
        muxerStarted: Boolean, hasAudio: Boolean, audioFormat: MediaFormat?
    ): Triple<Int, Int, Boolean> {
        var vIdx = videoTrackIndex
        var aIdx = audioTrackIndex
        var started = muxerStarted

        while (true) {
            val outIdx = encoder.dequeueOutputBuffer(bufferInfo, 0) // Non-blocking
            when {
                outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!started) {
                        vIdx = muxer.addTrack(encoder.outputFormat)
                        if (hasAudio && audioFormat != null) {
                            aIdx = muxer.addTrack(audioFormat)
                        }
                        muxer.start()
                        started = true
                    }
                }
                outIdx >= 0 -> {
                    val data = encoder.getOutputBuffer(outIdx)!!
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) bufferInfo.size = 0
                    if (bufferInfo.size > 0 && started) {
                        data.position(bufferInfo.offset)
                        data.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(vIdx, data, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(outIdx, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        }
        return Triple(vIdx, aIdx, started)
    }

    private fun drainEncoderFinal(
        encoder: MediaCodec, bufferInfo: MediaCodec.BufferInfo,
        muxer: MediaMuxer, trackIndex: Int, muxerStarted: Boolean
    ) {
        while (true) {
            val outIdx = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            if (outIdx >= 0) {
                val data = encoder.getOutputBuffer(outIdx)!!
                if (bufferInfo.size > 0 && muxerStarted) {
                    data.position(bufferInfo.offset)
                    data.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(trackIndex, data, bufferInfo)
                }
                encoder.releaseOutputBuffer(outIdx, false)
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                continue
            }
        }
    }

    private fun findTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith(mimePrefix) == true) return i
        }
        return -1
    }
}
