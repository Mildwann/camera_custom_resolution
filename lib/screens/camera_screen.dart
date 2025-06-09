import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_camera/utils/native_channel.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  String? _selectedAspectRatio;
  Size? _selectedResolution;
  Map<String, List<Size>> _aspectRatioToResolutions = {};

  @override
  void initState() {
    super.initState();
    _fetchSupportedResolutions();
  }

  double get aspectRatio {
    if (_selectedResolution == null) return 4 / 3;
    return _selectedResolution!.width / _selectedResolution!.height;
  }

  Future<void> _fetchSupportedResolutions() async {
    List<Size> allResolutions = await NativeCamera.getSupportedResolutions();

    // กรองกลุ่ม aspect ratios
    Map<String, List<Size>> grouped = {};
    for (var size in allResolutions) {
      double ratio = size.width / size.height;
      String key = _approximateAspectRatio(ratio);
      if (key.isEmpty) continue; // ข้ามพวกที่ไม่ใช่ 4:3, 16:9, 1:1
      grouped.putIfAbsent(key, () => []).add(size);
    }

    setState(() {
      _aspectRatioToResolutions = grouped;
      _selectedAspectRatio = grouped.keys.first;
      _selectedResolution = grouped[_selectedAspectRatio!]!.first;
    });

    _initializeCameraController();
  }

  String _approximateAspectRatio(double ratio) {
    const threshold = 0.05;

    if ((ratio - 4 / 3).abs() < threshold) return '4:3';
    if ((ratio - 16 / 9).abs() < threshold) return '16:9';
    if ((ratio - 1.0).abs() < threshold) return '1:1';

    // ไม่จัดกลุ่มอื่น ๆ
    return ''; // หรือ return null แล้วเช็คภายหลัง
  }

  Future<void> _initializeCameraController() async {
    try {
      await _controller.dispose();
    } catch (_) {}
    _controller = CameraController(widget.camera, ResolutionPreset.max);
    _initializeControllerFuture = _controller.initialize();
    await _initializeControllerFuture;
    setState(() {});
  }

  void _onAspectRatioChanged(String? newRatio) {
    if (newRatio == null) return;
    setState(() {
      _selectedAspectRatio = newRatio;
      _selectedResolution = _aspectRatioToResolutions[newRatio]?.first;
    });
    _initializeCameraController();
  }

  void _onResolutionChanged(Size? newResolution) {
    if (newResolution == null) return;
    setState(() {
      _selectedResolution = newResolution;
    });
    _initializeCameraController();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      if (_selectedResolution == null) return;

      await [Permission.storage, Permission.photos].request();

      final imagePath = await NativeCamera.takePictureWithResolution(
        _selectedResolution!.width.toInt(),
        _selectedResolution!.height.toInt(),
      );

      if (imagePath != null && imagePath.isNotEmpty) {
        final result = await ImageGallerySaverPlus.saveFile(
          imagePath,
          name: 'photo_${DateTime.now().millisecondsSinceEpoch}',
          isReturnPathOfIOS: true,
        );
        print("Image saved to gallery: $result");

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DisplayPictureScreen(imagePath: imagePath),
            ),
          );
        }
      } else {
        print('Failed to take picture or image path is empty');
      }
    } catch (e) {
      print('Error taking picture: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera with Dynamic Resolutions')),
      body: (_controller.value.isInitialized)
          ? Column(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: CameraPreview(_controller),
                ),
                const SizedBox(height: 8),
                const Text('เลือกอัตราส่วนภาพ'),
                DropdownButton<String>(
                  value: _selectedAspectRatio,
                  items: _aspectRatioToResolutions.keys.map((ratio) {
                    return DropdownMenuItem(value: ratio, child: Text(ratio));
                  }).toList(),
                  onChanged: _onAspectRatioChanged,
                ),
                const SizedBox(height: 8),
                const Text('เลือกความละเอียดภาพถ่าย'),
                DropdownButton<Size>(
                  value: _selectedResolution,
                  items: _aspectRatioToResolutions[_selectedAspectRatio]?.map((
                    size,
                  ) {
                    return DropdownMenuItem(
                      value: size,
                      child: Text(
                        '${size.width.toInt()} x ${size.height.toInt()}',
                      ),
                    );
                  }).toList(),
                  onChanged: _onResolutionChanged,
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.camera_alt),
        onPressed: _takePicture,
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final String imagePath;
  const DisplayPictureScreen({Key? key, required this.imagePath})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภาพที่ถ่าย')),
      body: Center(child: Image.file(File(imagePath))),
    );
  }
}
