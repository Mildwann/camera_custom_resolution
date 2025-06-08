package com.example.open_camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

class CameraPreviewActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "custom_camera"
    }

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePicture" -> {
                    val width = call.argument<Int>("width") ?: 1080
                    val height = call.argument<Int>("height") ?: 1920

                    if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                        != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), 101)
                        result.error("PERMISSION_DENIED", "Camera permission not granted", null)
                        return@setMethodCallHandler
                    }

                    takeCustomPicture(width, height, result)
                }

                "getSupportedResolutions" -> {
                    val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                    val cameraId = cameraManager.cameraIdList[0]
                    val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                    val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    val sizes = configMap?.getOutputSizes(ImageFormat.JPEG) ?: emptyArray()

                    val list = sizes.map {
                        mapOf("width" to it.width, "height" to it.height)
                    }
                    result.success(list)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun takeCustomPicture(width: Int, height: Int, result: MethodChannel.Result) {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList[0]

        handlerThread = HandlerThread("CameraThread").also { it.start() }
        handler = Handler(handlerThread!!.looper)

        val imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1)
        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            val buffer: ByteBuffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            image.close()

            val file = File(getExternalFilesDir(null), "custom_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { it.write(bytes) }

            closeCamera()

            result.success(file.absolutePath)
        }, handler)

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Camera permission not granted", null)
            return
        }

        cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                cameraDevice = camera

                camera.createCaptureSession(
                    listOf(imageReader.surface),
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            captureSession = session
                            try {
                                val requestBuilder = cameraDevice!!.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                                requestBuilder.addTarget(imageReader.surface)

                                session.capture(requestBuilder.build(), object : CameraCaptureSession.CaptureCallback() {
                                    override fun onCaptureCompleted(
                                        session: CameraCaptureSession,
                                        request: CaptureRequest,
                                        result: TotalCaptureResult
                                    ) {
                                        super.onCaptureCompleted(session, request, result)
                                        closeCamera()
                                    }
                                }, handler)

                            } catch (e: CameraAccessException) {
                                result.error("CAPTURE_FAILED", e.message, null)
                            }
                        }

                        override fun onConfigureFailed(session: CameraCaptureSession) {
                            result.error("CONFIGURE_FAILED", "Camera session configuration failed", null)
                        }
                    },
                    handler
                )
            }

            override fun onDisconnected(camera: CameraDevice) {
                closeCamera()
                result.error("CAMERA_DISCONNECTED", "Camera disconnected", null)
            }

            override fun onError(camera: CameraDevice, error: Int) {
                closeCamera()
                result.error("CAMERA_ERROR", "Camera error code: $error", null)
            }
        }, handler)
    }

    private fun closeCamera() {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
    }
}
