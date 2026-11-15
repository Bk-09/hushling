// Loads the picture files in assets/scenes/ (flame, pond, lotus flowers, ...).
// Ask for a picture every frame: it returns null until it has loaded (the first ask starts the
// load), so scenes simply draw a plain background until the picture is ready.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

class SceneArt {
  static final Map<String, ui.Image> _img = <String, ui.Image>{};
  static final Set<String> _asked = <String>{};

  static ui.Image? get(String file) {
    final hit = _img[file];
    if (hit != null) return hit;
    if (_asked.add(file)) _load(file);
    return null;
  }

  static Future<void> preload(List<String> files) async {
    for (final f in files) {
      await _load(f);
    }
  }

  static Future<void> _load(String file) async {
    if (_img.containsKey(file)) return;
    _asked.add(file);
    try {
      final data = await rootBundle.load('assets/scenes/$file');
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      _img[file] = frame.image;
    } catch (_) {
      // a missing picture is simply never drawn
    }
  }
}

/// Draws the whole picture into [dst].
void drawArt(Canvas c, ui.Image img, Rect dst, {double opacity = 1.0, BlendMode? blend, FilterQuality q = FilterQuality.medium}) {
  final p = Paint()..filterQuality = q;
  if (blend != null) p.blendMode = blend;
  if (opacity < 1.0) p.color = Color.fromARGB((opacity.clamp(0.0, 1.0) * 255).round(), 255, 255, 255);
  c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, p);
}
