import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_camera/face_camera.dart';
import 'package:face_camera/src/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import 'camera_state.dart';

/// The controller for the [FaceCameraController] widget.
class FaceCameraController extends ValueNotifier<CameraState> {
  /// Construct a new [FaceCameraController] instance.
  FaceCameraController({
    this.imageResolution = ImageResolution.medium,
    this.enableAudio = true,
    this.autoCapture = false,
    this.ignoreFacePositioning = false,
    this.orientation = CameraOrientation.portraitUp,
    required this.onCapture,
    this.onFaceDetected,
    this.centerPosition = false,
  }) : super(CameraState.uninitialized());

  /// The desired resolution for the camera.
  final ImageResolution imageResolution;

  /// Set false to disable capture sound.
  final bool enableAudio;

  /// Set true to capture image on face detected.
  final bool autoCapture;

  /// Set true to trigger onCapture even when the face is not well positioned
  final bool ignoreFacePositioning;

  /// Use this to lock camera orientation.
  final CameraOrientation? orientation;

  final void Function(File? image) onCapture;

  /// Callback invoked when camera detects face.
  final void Function(Face? face)? onFaceDetected;

  /// Set true to center face in the camera frame.
  /// centerPosition is only applicable when autoCapture is true.
  /// and using FaceCameraCircle widget.
  final bool centerPosition;

  /// Gets all available camera lens and set current len
  void _getAllAvailableCameraLens() {
    int currentCameraLens = 1;
    final List<CameraLens> availableCameraLens = [];
    for (CameraDescription d in FaceCamera.cameras) {
      final lens = EnumHandler.cameraLensDirectionToCameraLens(d.lensDirection);
      if (lens != null && !availableCameraLens.contains(lens)) {
        availableCameraLens.add(lens);
      }
    }

    value = value.copyWith(
      availableCameraLens: availableCameraLens,
      currentCameraLens: currentCameraLens,
    );
  }

  Future<void> _initCamera() async {
    final cameras = FaceCamera.cameras.where((c) {
      return c.lensDirection ==
          EnumHandler.cameraLensToCameraLensDirection(
            value.availableCameraLens[value.currentCameraLens],
          );
    }).toList();

    if (cameras.isNotEmpty) {
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final cameraController = CameraController(
        frontCamera,
        EnumHandler.imageResolutionToResolutionPreset(imageResolution),
        enableAudio: enableAudio,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await cameraController.initialize().whenComplete(() {
        value = value.copyWith(
          isInitialized: true,
          cameraController: cameraController,
        );
      });

      await cameraController.lockCaptureOrientation(
        EnumHandler.cameraOrientationToDeviceOrientation(orientation),
      );
    }

    startImageStream();
  }

  /// The supplied [zoom] value should be between 1.0 and the maximum supported
  Future<void> setZoomLevel(double zoom) async {
    final CameraController? cameraController = value.cameraController;
    if (cameraController == null) {
      return;
    }
    await cameraController.setZoomLevel(zoom);
  }

  Future<void> changeCameraLens() async {
    value = value.copyWith(
      currentCameraLens: (value.currentCameraLens + 1) % value.availableCameraLens.length,
    );
    _initCamera();
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = value.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      logError('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      logError('A capture is already pending');
      return null;
    }

    try {
      XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
  }

  Future<void> startImageStream() async {
    final CameraController? cameraController = value.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (!cameraController.value.isStreamingImages) {
      await cameraController.startImageStream(_processImage);
    }
  }

  Future<void> stopImageStream() async {
    final CameraController? cameraController = value.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }
  }

  removeRotation(File inputImage) async {
    final img.Image? capturedImage = img.decodeImage(await File(inputImage.path).readAsBytes());
    final img.Image orientedImage = img.bakeOrientation(capturedImage!);
    return await File(inputImage.path).writeAsBytes(img.encodeJpg(orientedImage));
  }

  void _processImage(CameraImage cameraImage) async {
    final CameraController? cameraController = value.cameraController;
    if (!value.alreadyCheckingImage) {
      value = value.copyWith(alreadyCheckingImage: true);
      try {
        await FaceIdentifier.scanImage(
          cameraImage: cameraImage,
          controller: cameraController,
        ).then((result) async {
          value = value.copyWith(detectedFace: result);

          if (result != null) {
            try {
              if (result.face != null) {
                onFaceDetected?.call(result.face);
              }
              if (autoCapture &&
                  (result.wellPositioned || ignoreFacePositioning) &&
                  !centerPosition) {
                captureImage();
              }
              if (autoCapture && centerPosition) {
                final face = result.face;
                if (face != null) {
                  captureImage();
                }
              }
            } catch (e) {
              logError(e.toString());
            }
          }
        });
        value = value.copyWith(alreadyCheckingImage: false);
      } catch (ex, stack) {
        value = value.copyWith(alreadyCheckingImage: false);
        logError('$ex, $stack');
      }
    }
  }

  void captureImage() async {
    final CameraController? cameraController = value.cameraController;
    try {
      cameraController!.stopImageStream().whenComplete(() async {
        takePicture().then((XFile? file) async {
          /// Return image callback
          if (file != null) {
            onCapture.call(File(file.path));
          }
        });
      });
    } catch (e) {
      logError(e.toString());
    }
  }

  // Capture image when press the capture button
  Future<File?> captureControl() async {
    final CameraController? cameraController = value.cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      logError('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      logError('A capture is already pending');
      return null;
    }

    if (cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }

    try {
      XFile? file = await takePicture();
      if (file == null) {
        return null;
      }

      return File(file.path);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  // Initialize camera controller
  Future<void> initialize() async {
    _getAllAvailableCameraLens();
    _initCamera();
  }

  /// Enables controls only when camera is initialized.
  bool get enableControls {
    final CameraController? cameraController = value.cameraController;
    return cameraController != null && cameraController.value.isInitialized;
  }

  /// Dispose the controller.
  ///
  /// Once the controller is disposed, it cannot be used anymore.
  @override
  Future<void> dispose() async {
    final CameraController? cameraController = value.cameraController;

    if (cameraController != null && cameraController.value.isInitialized) {
      cameraController.dispose();
    }
    super.dispose();
  }
}
