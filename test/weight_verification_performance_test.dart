import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:laundry_app/features/staff/screens/weight_verification_screen.dart';

void main() {
  test('watermark generation downscales large camera captures before drawing', () {
    final source = img.Image(width: 4000, height: 3000);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, 255, 200, 180, 255);
      }
    }

    final originalBytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));

    final watermarked = WeightVerificationScreen.generateWatermarkedProofBytes(
      originalBytes,
      'TXN-123456',
      12.5,
      'Aug 13, 2026 11:30 AM',
    );

    expect(watermarked, isNotNull);

    final decoded = img.decodeJpg(watermarked!);
    expect(decoded, isNotNull);
    expect(decoded!.width <= 1280, isTrue);
    expect(decoded.height <= 1280, isTrue);
  });
}
