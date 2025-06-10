package com.example.open_camera

import android.content.ContentValues
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.*
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "native_camera"

    private lateinit var cameraManager: CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSize: Size? = null
    private var imageReader: ImageReader? = null
    

    // Handler สำหรับ ImageReader callback
    private val backgroundHandler: Handler by lazy {
        val thread = HandlerThread("CameraBackground").also { it.start() }
        Handler(thread.looper)
    }

    private lateinit var methodChannelResult: MethodChannel.Result

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
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
                    openCamera(width, height, result, flutterEngine)
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

    private fun getSupportedResolutions(): List<Map<String, Int>> {
        try {
            val cameraId = cameraManager.cameraIdList[0] // กล้องหลัง
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val sizes = map?.getOutputSizes(SurfaceTexture::class.java) ?: arrayOf()
            return sizes.map { size -> mapOf("width" to size.width, "height" to size.height) }
        } catch (e: Exception) {
            Log.e("NativeCamera", "Error getting supported resolutions: ${e.message}")
            return emptyList()
        }
    }

    private fun openCamera(width: Int, height: Int, result: MethodChannel.Result, flutterEngine: FlutterEngine) {
        val cameraId = cameraManager.cameraIdList[0]
        previewSize = Size(width, height)

        closeCamera()

        surfaceTextureEntry = flutterEngine.renderer.createSurfaceTexture()

        if (surfaceTextureEntry == null) {
            result.error("UNAVAILABLE", "Failed to create SurfaceTexture", null)
            return
        }

        // สร้าง ImageReader สำหรับถ่ายภาพความละเอียดเท่ากับ preview
        imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1)
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            val buffer: ByteBuffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            saveImage(bytes)
            image.close()
        }, backgroundHandler)

        val surfaceTexture = surfaceTextureEntry!!.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(previewSize!!.width, previewSize!!.height)
        val previewSurface = Surface(surfaceTexture)
        val captureSurface = imageReader!!.surface

        try {
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCaptureSessionWithImageReader(previewSurface, captureSurface, result)
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
            }, backgroundHandler)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Camera permission denied", null)
        } catch (e: CameraAccessException) {
            result.error("ERROR", "Failed to open camera: ${e.message}", null)
        }
    }

    private fun createCaptureSessionWithImageReader(previewSurface: Surface, captureSurface: Surface, result: MethodChannel.Result?) {
        try {
            val captureRequestBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureRequestBuilder.addTarget(previewSurface)

            cameraDevice!!.createCaptureSession(listOf(previewSurface, captureSurface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    try {
                        captureRequestBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                        captureSession!!.setRepeatingRequest(captureRequestBuilder.build(), null, backgroundHandler)
                        result?.success(surfaceTextureEntry!!.id())
                    } catch (e: CameraAccessException) {
                        result?.error("ERROR", "Failed to start preview: ${e.message}", null)
                    }
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    result?.error("ERROR", "Failed to configure capture session", null)
                }
            }, backgroundHandler)
        } catch (e: CameraAccessException) {
            result?.error("ERROR", e.message, null)
        }
    }

    private fun changeResolution(width: Int, height: Int, result: MethodChannel.Result) {
        if (cameraDevice == null || surfaceTextureEntry == null) {
            result.error("ERROR", "Camera not opened", null)
            return
        }
        previewSize = Size(width, height)

        // ปิด ImageReader เดิมแล้วสร้างใหม่
        imageReader?.close()
        imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1)
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            val buffer: ByteBuffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            saveImage(bytes)
            image.close()
        }, backgroundHandler)

        val surfaceTexture = surfaceTextureEntry!!.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(previewSize!!.width, previewSize!!.height)
        val previewSurface = Surface(surfaceTexture)
        val captureSurface = imageReader!!.surface

        captureSession?.close()
        createCaptureSessionWithImageReader(previewSurface, captureSurface, result)
    }

    private var takePictureResult: MethodChannel.Result? = null

private fun takePicture(result: MethodChannel.Result) {
    if (cameraDevice == null || captureSession == null || imageReader == null) {
        result.error("ERROR", "Camera not ready", null)
        return
    }

    takePictureResult = result // store result for later

    try {
        val captureBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
        captureBuilder.addTarget(imageReader!!.surface)
        captureBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)

        captureSession!!.stopRepeating()

        captureSession!!.capture(captureBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, resultCapture: TotalCaptureResult) {
                super.onCaptureCompleted(session, request, resultCapture)
                try {
                    val previewRequestBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    previewRequestBuilder.addTarget(Surface(surfaceTextureEntry!!.surfaceTexture()))
                    previewRequestBuilder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                    session.setRepeatingRequest(previewRequestBuilder.build(), null, backgroundHandler)
                } catch (e: CameraAccessException) {
                    Log.e("NativeCamera", "Error restarting preview: $e")
                }
            }
        }, backgroundHandler)

    } catch (e: CameraAccessException) {
        result.error("ERROR", "Failed to capture picture: ${e.message}", null)
    }
}


 private fun saveImage(bytes: ByteArray) {
    val filename = "IMG_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.jpg"
    var savedPath: String? = null

    try {
        val originalBitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)

        val cameraId = cameraManager.cameraIdList[0]
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val orientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0

        val matrix = android.graphics.Matrix()
        matrix.postRotate(orientation.toFloat())
        val rotatedBitmap = android.graphics.Bitmap.createBitmap(
            originalBitmap,
            0,
            0,
            originalBitmap.width,
            originalBitmap.height,
            matrix,
            true
        )

        val outputStream = java.io.ByteArrayOutputStream()
        rotatedBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 100, outputStream)
        val rotatedBytes = outputStream.toByteArray()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val picturesDir = File(getExternalFilesDir(Environment.DIRECTORY_PICTURES), "MyCameraApp")
            if (!picturesDir.exists()) picturesDir.mkdirs()

            val file = File(picturesDir, filename)
            FileOutputStream(file).use { it.write(rotatedBytes) }

            savedPath = file.absolutePath
            Log.d("NativeCamera", "Saved rotated image to $savedPath")
        } else {
            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val file = File(picturesDir, filename)
            FileOutputStream(file).use { it.write(rotatedBytes) }

            val intent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            intent.data = android.net.Uri.fromFile(file)
            sendBroadcast(intent)

            savedPath = file.absolutePath
            Log.d("NativeCamera", "Saved rotated image to $savedPath")
        }

        takePictureResult?.success(savedPath)
        takePictureResult = null

    } catch (e: Exception) {
        Log.e("NativeCamera", "Failed to save rotated image: ${e.message}")
        takePictureResult?.error("ERROR", "Failed to save image: ${e.message}", null)
        takePictureResult = null
    }
}



    private fun closeCamera() {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        surfaceTextureEntry?.release()
        surfaceTextureEntry = null
        imageReader?.close()
        imageReader = null
    }

    override fun onDestroy() {
        super.onDestroy()
        closeCamera()
    }
}