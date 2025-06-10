import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_camera/ImagePreviewPage.dart';
import 'package:permission_handler/permission_handler.dart';

const platform = MethodChannel('native_camera');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Camera Dynamic Resolution',
      home: const CameraPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  Map<String, List<Size>> groupedResolutions = {};
  String? selectedAspectRatio;
  Size? selectedResolution;
  int? _textureId;
  String? lastCapturedImagePath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final granted = await requestCameraPermission();
    if (!granted) {
      // Handle permission denied
      return;
    }
    final resolutions = await fetchGroupedResolutions();
    setState(() {
      groupedResolutions = resolutions;
      selectedAspectRatio = groupedResolutions.keys.firstOrNull;
      selectedResolution = groupedResolutions[selectedAspectRatio]?.first;
    });
    if (selectedResolution != null) {
      await openCamera(selectedResolution!);
    }
  }

  Future<bool> requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    return status.isGranted;
  }

  Future<Map<String, List<Size>>> fetchGroupedResolutions() async {
    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getSupportedResolutions',
      );
      final resolutions = result.map((e) {
        return Size(
          (e['width'] as int).toDouble(),
          (e['height'] as int).toDouble(),
        );
      }).toList();

      Map<String, List<Size>> grouped = {};
      for (final size in resolutions) {
        final ratio = size.width / size.height;
        final ratioStr = _aspectRatioLabel(ratio);
        grouped.putIfAbsent(ratioStr, () => []).add(size);
      }

      grouped.forEach((key, list) {
        list.sort((a, b) => a.width.compareTo(b.width));
      });

      return grouped;
    } catch (e) {
      debugPrint('Error fetching resolutions: $e');
      return {};
    }
  }

  String _aspectRatioLabel(double ratio) {
    if ((ratio - 4 / 3).abs() < 0.1) return '4:3';
    if ((ratio - 16 / 9).abs() < 0.1) return '16:9';
    if ((ratio - 1).abs() < 0.1) return '1:1';
    return ratio.toStringAsFixed(2);
  }

  Future<void> openCamera(Size resolution) async {
    try {
      if (_textureId == null) {
        final textureId = await platform.invokeMethod('openCamera', {
          'width': resolution.width.toInt(),
          'height': resolution.height.toInt(),
        });
        setState(() {
          _textureId = textureId;
        });
      } else {
        await platform.invokeMethod('changeResolution', {
          'width': resolution.width.toInt(),
          'height': resolution.height.toInt(),
        });
      }
    } catch (e) {
      debugPrint('Error opening/changing camera resolution: $e');
    }
  }

  Future<void> takePicture() async {
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
    try {
      final String imagePath = await platform.invokeMethod('takePicture');

      if (imagePath.isNotEmpty) {
        await ImageGallerySaverPlus.saveFile(imagePath);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ImagePreviewPage(imagePath: imagePath),
          ),
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take picture: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolutions = selectedAspectRatio != null
        ? groupedResolutions[selectedAspectRatio] ?? []
        : [];

    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Camera Resolution')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Aspect Ratio:"),
            DropdownButton<String>(
              value: selectedAspectRatio,
              isExpanded: true,
              items: groupedResolutions.keys
                  .map(
                    (ratio) =>
                        DropdownMenuItem(value: ratio, child: Text(ratio)),
                  )
                  .toList(),
              onChanged: (value) async {
                setState(() {
                  selectedAspectRatio = value;
                  final list = groupedResolutions[value] ?? [];
                  selectedResolution = list.isNotEmpty ? list.first : null;
                });
                if (selectedResolution != null) {
                  await openCamera(selectedResolution!);
                }
              },
            ),
            const SizedBox(height: 10),
            const Text("Resolution:"),
            DropdownButton<Size>(
              value: selectedResolution,
              isExpanded: true,
              hint: const Text("Select resolution"),
              items: resolutions.map((res) {
                return DropdownMenuItem<Size>(
                  value: res,
                  child: Text('${res.width.toInt()} x ${res.height.toInt()}'),
                );
              }).toList(),
              onChanged: (value) async {
                setState(() {
                  selectedResolution = value;
                });
                if (value != null) {
                  await openCamera(value);
                }
              },
            ),
            const SizedBox(height: 20),
            if (_textureId != null && selectedResolution != null)
              AspectRatio(
                aspectRatio:
                    selectedResolution!.height / selectedResolution!.width,
                child: Texture(textureId: _textureId!),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: takePicture,
              child: const Text('Take Picture'),
            ),
            if (lastCapturedImagePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Last captured image:'),
                    SizedBox(
                      height: 200,
                      child: Image.file(File(lastCapturedImagePath!)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
