// Verifies that exporting the QR preview at a pixelRatio chosen to hit a
// minimum resolution (mirroring the logic now used in the generate/my-QR
// screens) produces a PNG that is actually >= 2048px on a side, lossless,
// and still scans back to the original data.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image/image.dart' as img;

const double _minExportSize = 2048;

Future<Uint8List> _renderQr(WidgetTester tester, double boundarySize) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            width: boundarySize,
            height: boundarySize,
            padding: EdgeInsets.all(boundarySize / 12),
            color: Colors.white,
            child: QrImageView(
              data: 'https://reviewqr.app/#/review/test-shop-id',
              version: QrVersions.auto,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF14181F),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF14181F),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final shortestSide = boundary.size.shortestSide;
  final pixelRatio = shortestSide > 0
      ? (_minExportSize / shortestSide).clamp(1.0, 32.0)
      : 8.0;
  // Real async is required here: toByteData never completes under the fake
  // clock testWidgets runs on, so without runAsync this test hangs forever.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  testWidgets('exported QR PNG meets min resolution and stays scannable',
      (tester) async {
    for (final boundarySize in [240.0, 120.0]) {
      final bytes = await _renderQr(tester, boundarySize);

      // >= 10KB (well above the old low-quality output) and losslessly PNG.
      expect(bytes.length, greaterThan(10 * 1024));
      expect(bytes[0], 0x89); // PNG magic byte
      expect(bytes[1], 0x50); // 'P'

      final decoded = img.decodePng(bytes)!;
      expect(decoded.width, greaterThanOrEqualTo(2048));
      expect(decoded.height, greaterThanOrEqualTo(2048));

      final outFile = File(
        'build/qr_export_test_${boundarySize.toInt()}.png',
      );
      outFile.createSync(recursive: true);
      outFile.writeAsBytesSync(bytes);
      // ignore: avoid_print
      print(
        'boundary=${boundarySize}px -> ${decoded.width}x${decoded.height}, '
        '${bytes.length} bytes -> ${outFile.path}',
      );
    }
  });
}
