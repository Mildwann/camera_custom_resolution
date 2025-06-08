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

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "custom_camera"
    }

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

                    takeCustomPicture(width, height) { filePath ->
                        result.success(filePath)
                    }
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

    private fun takeCustomPicture(width: Int, height: Int, callback: (String) -> Unit) {
        val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cameraManager.cameraIdList[0]

        val handlerThread = HandlerThread("CameraThread")
        handlerThread.start()
        val handler = Handler(handlerThread.looper)

        val imageReader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1)
        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            val buffer: ByteBuffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            image.close()

            val file = File(getExternalFilesDir(null), "custom_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { it.write(bytes) }
            callback(file.absolutePath)
        }, handler)

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return

        cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                requestBuilder.addTarget(imageReader.surface)

                camera.createCaptureSession(
                    listOf(imageReader.surface),
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            session.capture(requestBuilder.build(), null, handler)
                        }

                        override fun onConfigureFailed(session: CameraCaptureSession) {}
                    },
                    handler
                )
            }

            override fun onDisconnected(camera: CameraDevice) {}
            override fun onError(camera: CameraDevice, error: Int) {}
        }, handler)
    }
}
