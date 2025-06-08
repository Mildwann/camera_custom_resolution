import 'dart:io';
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

  final Map<String, List<Size>> aspectRatioToResolutions = {
    '4:3': [
      Size(640, 480), // VGA
      Size(800, 600), // SVGA
      Size(1024, 768), // XGA
      Size(1280, 960), // SXGA-
      Size(1600, 1200), // UXGA
    ],
    '16:9': [
      Size(854, 480), // FWVGA
      Size(1280, 720), // HD (720p)
      Size(1920, 1080), // Full HD (1080p)
      Size(2560, 1440), // QHD / 2K
      Size(3840, 2160), // 4K UHD
    ],
    '1:1': [
      Size(480, 480), // Square low res
      Size(720, 720), // Medium square
      Size(1080, 1080), // Full HD square
    ],
  };

  @override
  void initState() {
    super.initState();
    _selectedAspectRatio = aspectRatioToResolutions.keys.first;
    _selectedResolution =
        aspectRatioToResolutions[_selectedAspectRatio!]!.first;
    _initializeCameraController();
  }

  double get aspectRatio {
    if (_selectedResolution == null) return 4 / 3;
    return _selectedResolution!.width / _selectedResolution!.height;
  }

  Future<void> _initializeCameraController() async {
    if (mounted) {
      try {
        await _controller.dispose();
      } catch (_) {
        // ignore error if _controller not initialized
      }
    }

    _controller = CameraController(widget.camera, ResolutionPreset.max);
    _initializeControllerFuture = _controller.initialize();
    await _initializeControllerFuture;
    setState(() {});
  }

  void _onAspectRatioChanged(String? newRatio) {
    if (newRatio == null) return;
    setState(() {
      _selectedAspectRatio = newRatio;
      _selectedResolution = aspectRatioToResolutions[newRatio]!.first;
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

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DisplayPictureScreen(imagePath: imagePath),
          ),
        );
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
      appBar: AppBar(
        title: const Text('Camera with Aspect Ratio & Resolution'),
      ),
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
                  items: aspectRatioToResolutions.keys.map((ratio) {
                    return DropdownMenuItem(value: ratio, child: Text(ratio));
                  }).toList(),
                  onChanged: _onAspectRatioChanged,
                ),
                const SizedBox(height: 8),
                const Text('เลือกความละเอียดภาพถ่าย'),
                DropdownButton<Size>(
                  value: _selectedResolution,
                  items: aspectRatioToResolutions[_selectedAspectRatio]!.map((
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
