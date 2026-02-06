package com.storyeditorpro

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.*
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * OpenGL/EGL renderer that composites a video texture (from SurfaceTexture/OES)
 * with a static overlay texture (from Bitmap) and renders to an encoder Surface.
 *
 * Pipeline: Decoder → SurfaceTexture (OES texture) → OpenGL blend overlay → Encoder Surface
 * Everything runs on GPU - no CPU pixel copying.
 */
class TextureRenderer {

    companion object {
        private const val TAG = "TextureRenderer"

        // Vertex shader - handles both video and overlay quads
        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            varying vec2 vTexCoord;
            uniform mat4 uTexMatrix;
            void main() {
                gl_Position = aPosition;
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """

        // Fragment shader for OES texture (video frames from SurfaceTexture)
        private const val FRAGMENT_SHADER_OES = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES uTexture;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """

        // Fragment shader for 2D texture (overlay bitmap)
        private const val FRAGMENT_SHADER_2D = """
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D uTexture;
            void main() {
                gl_FragColor = texture2D(uTexture, vTexCoord);
            }
        """

        // Fullscreen quad vertices (x, y)
        private val QUAD_VERTICES = floatArrayOf(
            -1f, -1f,
             1f, -1f,
            -1f,  1f,
             1f,  1f
        )

        // Texture coordinates (s, t) - flipped vertically for correct orientation
        private val QUAD_TEX_COORDS = floatArrayOf(
            0f, 0f,
            1f, 0f,
            0f, 1f,
            1f, 1f
        )
    }

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var programOES = 0
    private var program2D = 0

    private var videoTextureId = 0
    private var overlayTextureId = 0

    private var vertexBuffer: FloatBuffer
    private var texCoordBuffer: FloatBuffer

    private var outputWidth = 0
    private var outputHeight = 0

    init {
        vertexBuffer = createFloatBuffer(QUAD_VERTICES)
        texCoordBuffer = createFloatBuffer(QUAD_TEX_COORDS)
    }

    /**
     * Initialize EGL context and create window surface on the encoder's Surface
     */
    fun init(encoderSurface: Surface, width: Int, height: Int) {
        outputWidth = width
        outputHeight = height

        // 1. Get EGL display
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) throw RuntimeException("eglGetDisplay failed")

        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw RuntimeException("eglInitialize failed")
        }

        // 2. Choose config with recordable flag
        val configAttribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE
        )

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0)
        if (numConfigs[0] <= 0) throw RuntimeException("No EGL config found")

        // 3. Create GLES2 context
        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0]!!, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
        if (eglContext == EGL14.EGL_NO_CONTEXT) throw RuntimeException("eglCreateContext failed")

        // 4. Create window surface on encoder's Surface
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0]!!, encoderSurface, surfaceAttribs, 0)
        if (eglSurface == EGL14.EGL_NO_SURFACE) throw RuntimeException("eglCreateWindowSurface failed")

        // 5. Make current
        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            throw RuntimeException("eglMakeCurrent failed")
        }

        // 6. Compile shaders
        programOES = createProgram(VERTEX_SHADER, FRAGMENT_SHADER_OES)
        program2D = createProgram(VERTEX_SHADER, FRAGMENT_SHADER_2D)

        // 7. Create video texture (OES)
        val textures = IntArray(2)
        GLES20.glGenTextures(2, textures, 0)

        videoTextureId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, videoTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        // 8. Create overlay texture (2D)
        overlayTextureId = textures[1]

        Log.d(TAG, "EGL/OpenGL initialized: ${width}x${height}")
    }

    /**
     * Upload overlay bitmap to GPU texture (call once)
     */
    fun setOverlayBitmap(bitmap: Bitmap) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTextureId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)

        Log.d(TAG, "Overlay texture uploaded: ${bitmap.width}x${bitmap.height}")
    }

    /**
     * Get the video texture ID for SurfaceTexture
     */
    fun getVideoTextureId(): Int = videoTextureId

    /**
     * Render one frame: draw video texture + overlay texture, then swap
     */
    fun drawFrame(surfaceTexture: SurfaceTexture, presentationTimeNs: Long) {
        // Update the video texture with latest frame
        surfaceTexture.updateTexImage()

        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        // Draw video frame (OES texture)
        val texMatrix = FloatArray(16)
        surfaceTexture.getTransformMatrix(texMatrix)
        drawTexture(programOES, videoTextureId, GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texMatrix)

        // Draw overlay on top (2D texture with alpha blending)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)

        // Flip Y-axis for overlay: OpenGL texture (0,0)=bottom-left but bitmap (0,0)=top-left
        // Transform: t_new = 1 - t_old → translate(0,1) then scale(1,-1)
        val overlayMatrix = FloatArray(16)
        android.opengl.Matrix.setIdentityM(overlayMatrix, 0)
        android.opengl.Matrix.translateM(overlayMatrix, 0, 0f, 1f, 0f)
        android.opengl.Matrix.scaleM(overlayMatrix, 0, 1f, -1f, 1f)
        drawTexture(program2D, overlayTextureId, GLES20.GL_TEXTURE_2D, overlayMatrix)

        GLES20.glDisable(GLES20.GL_BLEND)

        // Set presentation timestamp and swap
        EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, presentationTimeNs)
        EGL14.eglSwapBuffers(eglDisplay, eglSurface)
    }

    /**
     * Draw a textured quad
     */
    private fun drawTexture(program: Int, textureId: Int, textureTarget: Int, texMatrix: FloatArray) {
        GLES20.glUseProgram(program)

        val posLoc = GLES20.glGetAttribLocation(program, "aPosition")
        val texLoc = GLES20.glGetAttribLocation(program, "aTexCoord")
        val texMatLoc = GLES20.glGetUniformLocation(program, "uTexMatrix")
        val textureLoc = GLES20.glGetUniformLocation(program, "uTexture")

        GLES20.glEnableVertexAttribArray(posLoc)
        vertexBuffer.position(0)
        GLES20.glVertexAttribPointer(posLoc, 2, GLES20.GL_FLOAT, false, 0, vertexBuffer)

        GLES20.glEnableVertexAttribArray(texLoc)
        texCoordBuffer.position(0)
        GLES20.glVertexAttribPointer(texLoc, 2, GLES20.GL_FLOAT, false, 0, texCoordBuffer)

        GLES20.glUniformMatrix4fv(texMatLoc, 1, false, texMatrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(textureTarget, textureId)
        GLES20.glUniform1i(textureLoc, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(posLoc)
        GLES20.glDisableVertexAttribArray(texLoc)
    }

    /**
     * Release all GL/EGL resources
     */
    fun release() {
        if (programOES != 0) { GLES20.glDeleteProgram(programOES); programOES = 0 }
        if (program2D != 0) { GLES20.glDeleteProgram(program2D); program2D = 0 }

        val textures = intArrayOf(videoTextureId, overlayTextureId)
        GLES20.glDeleteTextures(2, textures, 0)

        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            eglSurface = EGL14.EGL_NO_SURFACE
        }
        if (eglContext != EGL14.EGL_NO_CONTEXT) {
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            eglContext = EGL14.EGL_NO_CONTEXT
        }
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglTerminate(eglDisplay)
            eglDisplay = EGL14.EGL_NO_DISPLAY
        }

        Log.d(TAG, "Released")
    }

    // ─── Helpers ───────────────────────────────────────────────

    private fun createProgram(vertexSrc: String, fragmentSrc: String): Int {
        val vs = compileShader(GLES20.GL_VERTEX_SHADER, vertexSrc)
        val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSrc)

        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vs)
        GLES20.glAttachShader(program, fs)
        GLES20.glLinkProgram(program)

        val status = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw RuntimeException("Program link failed: $log")
        }

        GLES20.glDeleteShader(vs)
        GLES20.glDeleteShader(fs)
        return program
    }

    private fun compileShader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("Shader compile failed: $log")
        }
        return shader
    }

    private fun createFloatBuffer(data: FloatArray): FloatBuffer {
        return ByteBuffer.allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .put(data)
            .apply { position(0) }
    }
}
