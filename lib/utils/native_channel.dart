import 'package:flutter/services.dart';

class NativeCamera {
  static const MethodChannel _channel = MethodChannel('custom_camera');

  static Future<List<Size>> getSupportedResolutions() async {
    final List<dynamic> result = await _channel.invokeMethod(
      'getSupportedResolutions',
    );
    return result.map((e) {
      return Size(
        (e['width'] as int).toDouble(),
        (e['height'] as int).toDouble(),
      );
    }).toList();
  }

  static Future<String?> takePictureWithResolution(
    int width,
    int height,
  ) async {
    return await _channel.invokeMethod('takePicture', {
      'width': width,
      'height': height,
    });
  }
}
