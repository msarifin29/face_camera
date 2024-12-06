import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../face_camera.dart';
import 'utils/logger.dart';

class SmartFaceCamera extends StatefulWidget {
  final ImageResolution imageResolution;
  final CameraLens? defaultCameraLens;
  final CameraFlashMode defaultFlashMode;
  final bool enableAudio;
  final bool autoCapture;
  final bool showControls;
  final bool showCaptureControl;
  final bool showFlashControl;
  final bool showCameraLensControl;
  final String? message;
  final TextStyle messageStyle;
  final CameraOrientation? orientation;
  final void Function(File? image) onCapture;
  final void Function(Face? face)? onFaceDetected;
  final Widget? captureControlIcon;
  final CaptureControlBuilder? captureControlBuilder;
  final Widget? lensControlIcon;
  final FlashControlBuilder? flashControlBuilder;
  final MessageBuilder? messageBuilder;
  final IndicatorShape indicatorShape;
  final String? indicatorAssetImage;
  final IndicatorBuilder? indicatorBuilder;

  /// Automatically disable capture control when no face is detected.
  final bool autoDisableCaptureControl;

  const SmartFaceCamera(
      {this.imageResolution = ImageResolution.medium,
      this.defaultCameraLens,
      this.enableAudio = true,
      this.autoCapture = false,
      this.showControls = true,
      this.showCaptureControl = true,
      this.showFlashControl = true,
      this.showCameraLensControl = true,
      this.message,
      this.defaultFlashMode = CameraFlashMode.auto,
      this.orientation = CameraOrientation.portraitUp,
      this.messageStyle = const TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400),
      required this.onCapture,
      this.onFaceDetected,
      @Deprecated('Use [captureControlBuilder]') this.captureControlIcon,
      this.captureControlBuilder,
      this.lensControlIcon,
      this.flashControlBuilder,
      this.messageBuilder,
      this.indicatorShape = IndicatorShape.defaultShape,
      this.indicatorAssetImage,
      this.indicatorBuilder,
      this.autoDisableCaptureControl = false,
      super.key})
      : assert(indicatorShape != IndicatorShape.image || indicatorAssetImage != null,
            'IndicatorAssetImage must be provided when IndicatorShape is set to image.');

  @override
  State<SmartFaceCamera> createState() => _SmartFaceCameraState();
}

class _SmartFaceCameraState extends State<SmartFaceCamera>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;

  bool _alreadyCheckingImage = false;

  DetectedFace? _detectedFace;

  int _currentFlashMode = 0;
  final List<CameraFlashMode> _availableFlashMode = [
    CameraFlashMode.off,
    CameraFlashMode.auto,
    CameraFlashMode.always
  ];

  int _currentCameraLens = 0;
  final List<CameraLens> _availableCameraLens = [];

  void _getAllAvailableCameraLens() {
    for (CameraDescription d in FaceCamera.cameras) {
      final lens = EnumHandler.cameraLensDirectionToCameraLens(d.lensDirection);
      if (lens != null && !_availableCameraLens.contains(lens)) {
        _availableCameraLens.add(lens);
      }
    }

    if (widget.defaultCameraLens != null) {
      try {
        _currentCameraLens = _availableCameraLens.indexOf(widget.defaultCameraLens!);
      } catch (e) {
        logError(e.toString());
      }
    }
  }

  Future<void> _initCamera() async {
    final cameras = FaceCamera.cameras
        .where((c) =>
            c.lensDirection ==
            EnumHandler.cameraLensToCameraLensDirection(_availableCameraLens[_currentCameraLens]))
        .toList();

    if (cameras.isNotEmpty) {
      _controller = CameraController(
          cameras.first, EnumHandler.imageResolutionToResolutionPreset(widget.imageResolution),
          enableAudio: widget.enableAudio,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888);

      await _controller!.initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });

      await _changeFlashMode(_availableFlashMode.indexOf(widget.defaultFlashMode));

      await _controller!
          .lockCaptureOrientation(
              EnumHandler.cameraOrientationToDeviceOrientation(widget.orientation))
          .then((_) {
        if (mounted) setState(() {});
      });
    }

    _startImageStream();
  }

  Future<void> _changeFlashMode(int index) async {
    await _controller!
        .setFlashMode(EnumHandler.cameraFlashModeToFlashMode(_availableFlashMode[index]))
        .then((_) {
      if (mounted) setState(() => _currentFlashMode = index);
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _getAllAvailableCameraLens();
    _initCamera();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final CameraController? cameraController = _controller;

    if (cameraController != null && cameraController.value.isInitialized) {
      cameraController.dispose();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      if (cameraController.value.isStreamingImages) {
        cameraController.stopImageStream();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!cameraController.value.isStreamingImages) {
        _startImageStream();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final CameraController? cameraController = _controller;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (cameraController != null && cameraController.value.isInitialized) ...[
          Transform.scale(
            scale: 1.0,
            child: AspectRatio(
              aspectRatio: size.aspectRatio,
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.fitHeight,
                  child: SizedBox(
                    width: size.width,
                    height: size.width * cameraController.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _cameraDisplayWidget(),
                        if (_detectedFace != null) ...[
                          SizedBox(
                              width: cameraController.value.previewSize!.width,
                              height: cameraController.value.previewSize!.height,
                              child: widget.indicatorBuilder?.call(
                                      context,
                                      _detectedFace,
                                      Size(
                                        _controller!.value.previewSize!.height,
                                        _controller!.value.previewSize!.width,
                                      )) ??
                                  CustomPaint(
                                    painter: FacePainter(
                                        face: _detectedFace!.face,
                                        indicatorShape: widget.indicatorShape,
                                        indicatorAssetImage: widget.indicatorAssetImage,
                                        imageSize: Size(
                                          _controller!.value.previewSize!.height,
                                          _controller!.value.previewSize!.width,
                                        )),
                                  ))
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        ] else ...[
          const Text('No Camera Detected',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
              )),
          CustomPaint(
            size: size,
            painter: HolePainter(),
          )
        ],
        if (widget.showControls) ...[
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showFlashControl) ...[_flashControlWidget()],
                  if (widget.showCaptureControl) ...[
                    const SizedBox(width: 15),
                    _captureControlWidget(),
                    const SizedBox(width: 15)
                  ],
                  if (widget.showCameraLensControl) ...[_lensControlWidget()],
                ],
              ),
            ),
          )
        ]
      ],
    );
  }

  /// Render camera.
  Widget _cameraDisplayWidget() {
    final CameraController? cameraController = _controller;
    if (cameraController != null && cameraController.value.isInitialized) {
      return CameraPreview(cameraController, child: Builder(builder: (context) {
        if (widget.messageBuilder != null) {
          return widget.messageBuilder!.call(context, _detectedFace);
        }
        if (widget.message != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 55, vertical: 15),
            child: Text(widget.message!, textAlign: TextAlign.center, style: widget.messageStyle),
          );
        }
        return const SizedBox.shrink();
      }));
    }
    return const SizedBox.shrink();
  }

  /// Enables controls only when camera is initialized.
  bool get _enableControls {
    final CameraController? cameraController = _controller;
    return cameraController != null && cameraController.value.isInitialized;
  }

  /// Determines when to disable the capture control button.
  bool get _disableCapture => widget.autoDisableCaptureControl && _detectedFace?.face == null;

  /// Determines the camera controls color.
  Color? get iconColor => _enableControls ? null : Theme.of(context).disabledColor;

  /// Display the control buttons to take pictures.
  Widget _captureControlWidget() {
    return IconButton(
      icon: widget.captureControlBuilder?.call(context, _detectedFace) ??
          widget.captureControlIcon ??
          CircleAvatar(
              radius: 35,
              foregroundColor:
                  _enableControls && !_disableCapture ? null : Theme.of(context).disabledColor,
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.camera_alt, size: 35),
              )),
      onPressed: _enableControls && !_disableCapture ? _onTakePictureButtonPressed : null,
    );
  }

  /// Display the control buttons to switch between flash modes.
  Widget _flashControlWidget() {
    final icon = _availableFlashMode[_currentFlashMode] == CameraFlashMode.always
        ? Icons.flash_on
        : _availableFlashMode[_currentFlashMode] == CameraFlashMode.off
            ? Icons.flash_off
            : Icons.flash_auto;

    return IconButton(
      icon: widget.flashControlBuilder?.call(context, _availableFlashMode[_currentFlashMode]) ??
          CircleAvatar(
              radius: 25,
              foregroundColor: iconColor,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(icon, size: 25),
              )),
      onPressed: _enableControls
          ? () => _changeFlashMode((_currentFlashMode + 1) % _availableFlashMode.length)
          : null,
    );
  }

  /// Display the control buttons to switch between camera lens.
  Widget _lensControlWidget() {
    return IconButton(
        icon: widget.lensControlIcon ??
            CircleAvatar(
                radius: 25,
                foregroundColor: iconColor,
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(Icons.switch_camera_sharp, size: 25),
                )),
        onPressed: _enableControls
            ? () {
                _currentCameraLens = (_currentCameraLens + 1) % _availableCameraLens.length;
                _initCamera();
              }
            : null);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null) {
      return;
    }

    final CameraController cameraController = _controller!;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  void _onTakePictureButtonPressed() async {
    final CameraController? cameraController = _controller;
    try {
      cameraController!.stopImageStream().whenComplete(() async {
        await Future.delayed(const Duration(milliseconds: 500));
        takePicture().then((XFile? file) {
          /// Return image callback
          if (file != null) {
            widget.onCapture(File(file.path));
          }

          /// Resume image stream after 2 seconds of capture
          Future.delayed(const Duration(seconds: 2)).whenComplete(() {
            if (mounted && cameraController.value.isInitialized) {
              try {
                _startImageStream();
              } catch (e) {
                logError(e.toString());
              }
            }
          });
        });
      });
    } catch (e) {
      logError(e.toString());
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
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
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void _startImageStream() {
    final CameraController? cameraController = _controller;
    if (cameraController != null) {
      cameraController.startImageStream(_processImage);
    }
  }

  void _processImage(CameraImage cameraImage) async {
    final CameraController? cameraController = _controller;
    if (!_alreadyCheckingImage && mounted) {
      _alreadyCheckingImage = true;
      try {
        await FaceIdentifier.scanImage(cameraImage: cameraImage, controller: cameraController)
            .then((result) async {
          setState(() => _detectedFace = result);

          if (result != null) {
            try {
              if (result.wellPositioned) {
                if (widget.onFaceDetected != null) {
                  widget.onFaceDetected!.call(result.face);
                }
                if (widget.autoCapture) {
                  _onTakePictureButtonPressed();
                }
              }
            } catch (e) {
              logError(e.toString());
            }
          }
        });
        _alreadyCheckingImage = false;
      } catch (ex, stack) {
        logError('$ex, $stack');
      }
    }
  }
}
