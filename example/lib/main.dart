import 'dart:io';

import 'package:flutter/material.dart';

import 'package:face_camera/face_camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FaceCamera.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: BTN(),
        ),
      ),
    );
  }
}

class BTN extends StatelessWidget {
  const BTN({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
        onPressed: () async {
          await FaceCamera.initialize()
              .then((value) => Navigator.push(context, MaterialPageRoute(builder: (context) {
                    return const CameraPage();
                  })));
        },
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Open Camera'));
  }
}

class CameraPage extends StatefulWidget {
  const CameraPage({Key? key}) : super(key: key);

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _capturedImage = ValueNotifier<File?>(null);
  late FaceCameraController controller;

  @override
  void initState() {
    super.initState();
    controller = FaceCameraController(onCapture: (image) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder(
        valueListenable: _capturedImage,
        builder: (context, v, _) {
          if (_capturedImage.value != null) {
            return Center(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Image.file(
                    _capturedImage.value!,
                    width: double.maxFinite,
                    fit: BoxFit.fitWidth,
                  ),
                  ElevatedButton(
                    onPressed: () => _capturedImage.value = null,
                    child: const Text(
                      'Capture Again',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  )
                ],
              ),
            );
          }
          return SmartFaceCamera(
            controller: controller,
            showCaptureControl: true,
            captureControl: (image) {
              _capturedImage.value = image;
            },
          );
        },
      ),
    );
  }
}
