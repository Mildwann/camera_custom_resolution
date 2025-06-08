import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:open_camera/screens/camera_screen.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Camera Demo',
      home: CameraScreen(camera: cameras.first),
      debugShowCheckedModeBanner: false,
    );
  }
}
