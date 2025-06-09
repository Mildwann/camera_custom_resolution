import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_camera/CameraPage.dart';

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
