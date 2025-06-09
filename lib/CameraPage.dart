import 'package:flutter/material.dart';
import 'package:open_camera/main.dart';
import 'package:open_camera/preview_page.dart';
import 'package:permission_handler/permission_handler.dart';

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
  String? lastImagePath;

  @override
  void initState() {
    super.initState();
    requestCameraPermission().then((granted) async {
      if (granted) {
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
    });
  }

  Future<void> takePicture() async {
    try {
      final String imagePath = await platform.invokeMethod('takePicture');
      setState(() {
        lastImagePath = imagePath;
      });
      if (imagePath.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewPage(imagePath: imagePath),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
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
        final ratio = (size.width / size.height);
        final ratioStr = _aspectRatioLabel(ratio);

        // เพิ่มกรองแค่ 3 อัตราส่วนนี้
        if (ratioStr == '4:3' || ratioStr == '16:9' || ratioStr == '1:1') {
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

  void _showResolutionDialog() {
    final resolutions = selectedAspectRatio != null
        ? groupedResolutions[selectedAspectRatio] ?? []
        : [];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text(
            'Select Resolution',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: resolutions.length,
              itemBuilder: (context, index) {
                final res = resolutions[index];
                final isSelected = res == selectedResolution;
                return ListTile(
                  title: Text(
                    '${res.width.toInt()} x ${res.height.toInt()}',
                    style: TextStyle(
                      color: isSelected ? Colors.orangeAccent : Colors.white,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      selectedResolution = res;
                    });
                    openCamera(res);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolutions = selectedAspectRatio != null
        ? groupedResolutions[selectedAspectRatio] ?? []
        : [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Dynamic Camera Resolution',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (groupedResolutions.keys.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  dropdownColor: Colors.grey[900],
                  value: selectedAspectRatio,
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedAspectRatio = newValue;
                      selectedResolution = groupedResolutions[newValue]?.first;
                    });
                    if (selectedResolution != null) {
                      openCamera(selectedResolution!);
                    }
                  },
                  items: groupedResolutions.keys.map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_textureId != null)
            AspectRatio(
              aspectRatio: selectedResolution != null
                  ? selectedResolution!.width / selectedResolution!.height
                  : 4 / 3,
              child: Texture(textureId: _textureId!),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showResolutionDialog,
            icon: const Icon(Icons.settings),
            label: const Text('Change Resolution'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: takePicture,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take Picture'),
          ),
        ],
      ),
    );
  }
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
