import 'package:flutter/material.dart';

import '../../face_camera.dart';

class FacePainter extends CustomPainter {
  final Size imageSize;
  double? scaleX, scaleY;
  final Face? face;

  FacePainter({super.repaint, required this.imageSize, required this.face});

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = (face!.headEulerAngleY! > 10 || face!.headEulerAngleY! < -10)
          ? Colors.blue
          : Colors.green;

    scaleX = size.width / imageSize.width;
    scaleY = size.height / imageSize.height;

    canvas.drawPath(
      _defaultPath(rect: face!.boundingBox, widgetSize: size, scaleX: scaleX, scaleY: scaleY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.face != face;
  }
}

Path _defaultPath({required Rect rect, required Size widgetSize, double? scaleX, double? scaleY}) {
  double cornerExtension = 30.0;

  double left = widgetSize.width - rect.left.toDouble() * scaleX!;
  double right = widgetSize.width - rect.right.toDouble() * scaleX;
  double top = rect.top.toDouble() * scaleY!;
  double bottom = rect.bottom.toDouble() * scaleY;
  return Path()
    ..moveTo(left - cornerExtension, top)
    ..lineTo(left, top)
    ..lineTo(left, top + cornerExtension)
    ..moveTo(right + cornerExtension, top)
    ..lineTo(right, top)
    ..lineTo(right, top + cornerExtension)
    ..moveTo(left - cornerExtension, bottom)
    ..lineTo(left, bottom)
    ..lineTo(left, bottom - cornerExtension)
    ..moveTo(right + cornerExtension, bottom)
    ..lineTo(right, bottom)
    ..lineTo(right, bottom - cornerExtension);
}
