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
  bool isRearCamera = true;
  bool isFlashOn = false;

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
        final String? ratioStr = _aspectRatioLabel(size.width / size.height);
        if (ratioStr != null && ratioStr.isNotEmpty) {
          grouped.putIfAbsent(ratioStr, () => []).add(size);
        }
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

  String? _aspectRatioLabel(double ratio) {
    if ((ratio - 4 / 3).abs() < 0.1) return '4:3';
    if ((ratio - 16 / 9).abs() < 0.1) return '16:9';
    if ((ratio - 1).abs() < 0.1) return '1:1';
    return null;
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
        setState(() {
          lastCapturedImagePath = imagePath;
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take picture: ${e.message}')),
      );
    }
  }

  void _showSettingsSheet(BuildContext context) {
    final resolutions = selectedAspectRatio != null
        ? groupedResolutions[selectedAspectRatio] ?? []
        : [];

    showModalBottomSheet(
      backgroundColor: const Color(0xFF222222),
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              Text("Aspect Ratio:", style: TextStyle(color: Colors.white70)),
              DropdownButton<String>(
                dropdownColor: const Color(0xFF333333),
                value: selectedAspectRatio,
                isExpanded: true,
                style: const TextStyle(color: Colors.white),
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
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 12),

              Text("Resolution:", style: TextStyle(color: Colors.white70)),
              DropdownButton<Size>(
                dropdownColor: const Color(0xFF333333),
                value: selectedResolution,
                isExpanded: true,
                style: const TextStyle(color: Colors.white),
                hint: const Text(
                  "Select resolution",
                  style: TextStyle(color: Colors.white70),
                ),
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
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // กล้อง Preview
            Column(
              children: [
                if (_textureId != null && selectedResolution != null)
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio:
                            selectedResolution!.height /
                            selectedResolution!.width,
                        child: Texture(textureId: _textureId!),
                      ),
                    ),
                  )
                else
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),

            // Top bar
            Positioned(
              top: 0,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () => _showSettingsSheet(context),
                  ),
                  IconButton(
                    icon: Icon(
                      isFlashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white70,
                    ),
                    onPressed: () async {
                      try {
                        await platform.invokeMethod('toggleFlash');
                        setState(() {
                          isFlashOn = !isFlashOn;
                        });
                      } catch (e) {
                        debugPrint('Error toggling flash: $e');
                      }
                    },
                  ),
                ],
              ),
            ),

            // Bottom bar
            // Bottom bar
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ซ้าย: Placeholder (ไม่แสดงอะไรแต่ยังเว้นที่ไว้ให้ตรงกลางสมดุล)
                  const SizedBox(width: 48),

                  // ปุ่มถ่ายภาพ
                  GestureDetector(
                    onTap: takePicture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[400]!, width: 2),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),

                  // ขวา: Flip Camera
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white70),
                    onPressed: () async {
                      try {
                        final textureId = await platform.invokeMethod(
                          'switchCamera',
                        );
                        setState(() {
                          isRearCamera = !isRearCamera;
                          _textureId = textureId;
                        });
                      } catch (e) {
                        debugPrint('Error switching camera: $e');
                      }
                    },
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
