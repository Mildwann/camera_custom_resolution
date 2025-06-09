package com.example.open_camera

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Bundle
import android.os.Environment
import android.util.Size
import android.util.SparseIntArray
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "native_camera"

    private lateinit var cameraManager: CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSize: Size? = null
    private var imageReader: ImageReader? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportedResolutions" -> {
                    val resolutions = getSupportedResolutions()
                    result.success(resolutions)
                }
                "openCamera" -> {
                    val width = call.argument<Int>("width") ?: 640
                    val height = call.argument<Int>("height") ?: 480
                    openCamera(width, height, result)
                }
                "changeResolution" -> {
                    val width = call.argument<Int>("width") ?: 640
                    val height = call.argument<Int>("height") ?: 480
                    changeResolution(width, height, result)
                }
                "takePicture" -> {
                    takePicture(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupImageReader() {
        imageReader = ImageReader.newInstance(previewSize!!.width, previewSize!!.height, android.graphics.ImageFormat.JPEG, 1)
        imageReader!!.setOnImageAvailableListener({ reader ->
            val image = reader.acquireNextImage()
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)

            val file = createImageFile()
            file.writeBytes(bytes)

            image.close()
            pendingResult?.success(file.absolutePath)
            pendingResult = null
        }, null)
    }

    private fun openCamera(width: Int, height: Int, result: MethodChannel.Result) {
        val cameraId = cameraManager.cameraIdList[0]
        previewSize = Size(width, height)

        closeCamera()

        surfaceTextureEntry = flutterEngine?.renderer?.createSurfaceTexture()
        if (surfaceTextureEntry == null) {
            result.error("UNAVAILABLE", "Failed to create SurfaceTexture", null)
            return
        }

        setupImageReader()

        val surfaceTexture = surfaceTextureEntry!!.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(previewSize!!.width, previewSize!!.height)
        val surface = Surface(surfaceTexture)

        try {
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCaptureSession(surface, result)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    result.error("ERROR", "Camera error: $error", null)
                }
            }, null)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Camera permission denied", null)
        }
    }

    private fun createCaptureSession(surface: Surface, result: MethodChannel.Result?) {
        try {
            val captureRequestBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureRequestBuilder.addTarget(surface)
            imageReader?.surface?.let {
                captureRequestBuilder.addTarget(it)
            }

            cameraDevice!!.createCaptureSession(listOf(surface, imageReader?.surface).filterNotNull(), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    captureRequestBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                    captureSession!!.setRepeatingRequest(captureRequestBuilder.build(), null, null)

                    result?.success(surfaceTextureEntry!!.id())
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    result?.error("ERROR", "Failed to configure capture session", null)
                }
            }, null)
        } catch (e: CameraAccessException) {
            result?.error("ERROR", e.message, null)
        }
    }

    private fun takePicture(result: MethodChannel.Result) {
        if (cameraDevice == null || captureSession == null || imageReader == null) {
            result.error("ERROR", "Camera not ready or ImageReader not initialized", null)
            return
        }

        pendingResult = result

        try {
            val captureBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            captureBuilder.addTarget(imageReader!!.surface)
            captureBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)

            val rotation = windowManager.defaultDisplay.rotation
            val characteristics = cameraManager.getCameraCharacteristics(cameraDevice!!.id)
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val jpegOrientation = (ORIENTATIONS[rotation] + sensorOrientation + 270) % 360
            captureBuilder.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation)

            captureSession!!.stopRepeating()
            captureSession!!.abortCaptures()
            captureSession!!.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, resultCapture: TotalCaptureResult) {
                    super.onCaptureCompleted(session, request, resultCapture)
                    createCaptureSession(Surface(surfaceTextureEntry!!.surfaceTexture()), null)
                }
            }, null)
        } catch (e: CameraAccessException) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun changeResolution(width: Int, height: Int, result: MethodChannel.Result) {
        if (cameraDevice == null || surfaceTextureEntry == null) {
            result.error("ERROR", "Camera not opened", null)
            return
        }
        previewSize = Size(width, height)

        val surfaceTexture = surfaceTextureEntry!!.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(previewSize!!.width, previewSize!!.height)
        val surface = Surface(surfaceTexture)

        captureSession?.close()
        createCaptureSession(surface, result)
    }

    private fun getSupportedResolutions(): List<Map<String, Int>> {
        val cameraId = cameraManager.cameraIdList[0]
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = map?.getOutputSizes(SurfaceTexture::class.java) ?: arrayOf()

        return sizes.map { size -> mapOf("width" to size.width, "height" to size.height) }
    }

    private fun createImageFile(): File {
        val dir = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
        if (!dir!!.exists()) {
            dir.mkdirs()
        }
        val fileName = "IMG_${System.currentTimeMillis()}.jpg"
        return File(dir, fileName)
    }

    private fun closeCamera() {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        surfaceTextureEntry?.release()
        surfaceTextureEntry = null
    }

    override fun onDestroy() {
        super.onDestroy()
        closeCamera()
    }

    companion object {
        private val ORIENTATIONS = SparseIntArray().apply {
            append(Surface.ROTATION_0, 90)
            append(Surface.ROTATION_90, 0)
            append(Surface.ROTATION_180, 270)
            append(Surface.ROTATION_270, 180)
        }
    }
}
