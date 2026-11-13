// Sprite companions with smooth, procedural motion (core/pets.py).
//
// Each pet is a flat PNG (assets/pets/<id>.png, 512x512, transparent). Flat pictures cannot move
// their ears, so every frame is a smooth transform of the picture: breathing squash, sway, hop,
// hover, swim, wobble. <id>_blink.png / <id>_happy.png (when present) make it blink and smile.
//
// To add a pet: drop the PNG(s) into assets/pets/ and add an entry to assets/pets/pets.json:
//   ["<id>", "Display name", "land", "cats", hasBlink, hasHappy]
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'palette.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'util.dart';

class PetInfo {
  final String id;
  final String name;
  final String motion; // land, bird, float, swim, blob, crawl
  final String group; // cats, dogs, small, birds, magic
  final bool hasBlink;
  final bool hasHappy;
  const PetInfo(this.id, this.name, this.motion, this.group, this.hasBlink, this.hasHappy);
}

class Motion {
  final double sx, sy, rot, dx, dy;
  final bool bottom; // true: anchored at the feet, false: anchored at the centre
  const Motion(this.sx, this.sy, this.rot, this.dx, this.dy, this.bottom);
}

class Pets {
  static const String defaultPet = 'orange-tabby';
  static const double blinkEvery = 4.6; // seconds between blinks
  static const double blinkTime = 0.22; // how long each blink lasts
  static const double halo = 0.30; // soft white glow behind each pet (0 = off)
  static const double foot = 28 / 512; // empty margin under the feet in each PNG

  static final List<PetInfo> all = <PetInfo>[];
  static final List<String> popular = <String>[];
  static final Map<String, PetInfo> byId = <String, PetInfo>{};

  static const List<List<String>> groups = <List<String>>[
    ['popular', 'Popular'],
    ['cats', 'Cats'],
    ['dogs', 'Dogs'],
    ['small', 'Small'],
    ['birds', 'Birds'],
    ['magic', 'Fantasy'],
  ];
  static const Set<String> _flutter = {'bee', 'blue-butterfly', 'monarch', 'dragonfly', 'hummingbird', 'fairy'};
  static const Map<String, double> _tempo = {
    'calm': 1.0, 'happy': 1.25, 'excited': 1.5, 'proud': 1.2, 'sleepy': 0.6, 'sad': 0.7,
  };

  static Future<void> init() async {
    try {
      final txt = await rootBundle.loadString('assets/pets/pets.json');
      final d = jsonDecode(txt) as Map<String, dynamic>;
      for (final p in (d['pets'] as List)) {
        final l = p as List;
        final info = PetInfo(l[0] as String, l[1] as String, l[2] as String, l[3] as String,
            l.length > 4 && l[4] == true, l.length > 5 && l[5] == true);
        all.add(info);
        byId[info.id] = info;
      }
      for (final p in (d['popular'] as List)) {
        popular.add(p as String);
      }
    } catch (_) {}
  }

  static bool available(String id) => byId.containsKey(id);
  static String nameOf(String id) => byId[id]?.name ?? id;

  static List<String> inGroup(String group) {
    if (group == 'popular') return popular.where((p) => byId.containsKey(p)).toList();
    return all.where((p) => p.group == group).map((p) => p.id).toList();
  }

  // ------------------------------------------------------------------ motion (pure maths)
  static Motion motion(String id, double t, {double? breath, String mood = 'calm', double hop = 0.0}) {
    final kind = byId[id]?.motion ?? 'land';
    final k = _tempo[mood] ?? 1.0;
    final b = breath == null ? math.sin(t * 1.5 * k) : (breath * 2.0 - 1.0); // -1..1
    double sx = 1.0, sy = 1.0, rot = 0.0, dx = 0.0, dy = 0.0;
    var bottom = true;
    switch (kind) {
      case 'land':
        sy += 0.032 * b;
        sx -= 0.016 * b;
        rot = 1.1 * math.sin(t * 0.8 * k);
        break;
      case 'bird':
        sy += 0.022 * b;
        sx -= 0.010 * b;
        rot = 2.2 * math.sin(t * 1.3 * k);
        dy = -0.010 * math.pow(math.max(0.0, math.sin(t * 2.4 * k)), 6).toDouble();
        break;
      case 'crawl':
        final s = math.sin(t * 1.3 * k);
        sx += 0.040 * s;
        sy -= 0.026 * s;
        rot = 0.8 * math.sin(t * 0.7 * k);
        break;
      case 'blob':
        final s = math.sin(t * 2.2 * k);
        sy += 0.090 * s;
        sx -= 0.070 * s;
        dy = -0.030 * math.pow(math.max(0.0, math.sin(t * 2.2 * k + 1.2)), 2).toDouble();
        break;
      case 'float':
        bottom = false;
        dy = 0.035 * math.sin(t * 1.6 * k);
        dx = 0.012 * math.sin(t * 0.9 * k);
        rot = 4.0 * math.sin(t * 1.1 * k);
        sy += 0.018 * b;
        if (_flutter.contains(id)) sx += 0.060 * math.sin(t * 11.0);
        break;
      case 'swim':
        bottom = false;
        dx = 0.030 * math.sin(t * 0.8 * k);
        dy = 0.025 * math.sin(t * 1.3 * k);
        rot = 5.0 * math.sin(t * 0.8 * k + 1.0);
        sx += 0.030 * math.sin(t * 2.6 * k);
        sy += 0.012 * b;
        break;
    }
    if (mood == 'sleepy') sy *= 0.985;
    if (hop > 0.0) {
      // hop: 0..1 progress of one jump
      final h = math.min(1.0, hop);
      dy -= 0.12 * math.sin(math.pi * h);
      final edge = math.max(0.0, 1.0 - math.min(h, 1.0 - h) * 7.0); // squash on take-off / landing
      sy -= 0.10 * edge;
      sx += 0.07 * edge;
    }
    return Motion(sx, sy, rot, dx, dy, bottom);
  }

  // ------------------------------------------------------------------ sprite loading / cache
  static final Map<String, ui.Image> _img = <String, ui.Image>{};
  static final Set<String> _requested = <String>{};

  /// The picture, or null while it is still loading (it starts loading on the first ask).
  static ui.Image? sprite(String id, String variant) {
    final key = '$id|$variant';
    final hit = _img.remove(key);
    if (hit != null) {
      _img[key] = hit; // keep recently used pictures at the end
      return hit;
    }
    if (_requested.add(key)) _load(id, variant, key);
    return null;
  }

  static Future<void> preload(String id) async {
    await _load(id, '', '$id|');
    final info = byId[id];
    if (info != null && info.hasBlink) await _load(id, 'blink', '$id|blink');
    if (info != null && info.hasHappy) await _load(id, 'happy', '$id|happy');
  }

  static Future<void> _load(String id, String variant, String key) async {
    if (_img.containsKey(key)) return;
    _requested.add(key);
    try {
      final file = variant.isEmpty ? '$id.png' : '${id}_$variant.png';
      final data = await rootBundle.load('assets/pets/$file');
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      _img[key] = await _withHalo(frame.image);
      while (_img.length > 48) {
        final oldest = _img.keys.first;
        _img.remove(oldest);
        _requested.remove(oldest); // can be loaded again later
      }
    } catch (_) {
      // stays in _requested so a missing picture is not retried every frame
    }
  }

  /// Adds the soft white glow behind the pet (it hides hard pixel edges).
  static Future<ui.Image> _withHalo(ui.Image img) async {
    if (halo <= 0) return img;
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
    c.saveLayer(
      Rect.fromLTWH(-40, -40, w + 80, h + 80),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8)
        ..color = Color.fromARGB(a8(halo), 255, 255, 255),
    );
    c.drawImage(img, Offset.zero,
        Paint()..colorFilter = const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn));
    c.restore();
    c.drawImage(img, Offset.zero, Paint());
    return rec.endRecording().toImage(img.width, img.height);
  }

  static int _hash(String s) {
    var h = 7;
    for (final u in s.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return h;
  }

  // ------------------------------------------------------------------ drawing
  /// Draws a living pet. [center] = middle of its square box, [size] = box side. Returns false
  /// while the picture is still loading. [t] == 0 draws the still picture used in grids.
  static bool draw(Canvas canvas, String id, Offset center, double size, double t,
      {double? breath, String mood = 'calm', double hop = 0.0, bool shadow = true}) {
    var variant = '';
    final info = byId[id];
    if (t > 0 && info != null) {
      if (mood == 'happy' && info.hasHappy) {
        variant = 'happy'; // ^ ^ happy eyes while being petted or cheering
      } else if (info.hasBlink) {
        if (mood == 'sleepy') {
          variant = 'blink'; // eyes closed
        } else {
          final p = (t + (_hash(id) % 1000) / 250.0) % blinkEvery;
          if (p < blinkTime) variant = 'blink'; // a quick blink every few seconds
        }
      }
    }
    ui.Image? img;
    if (variant.isNotEmpty) img = sprite(id, variant);
    img ??= sprite(id, '');
    if (img == null) return false;

    final m = motion(id, t, breath: breath, mood: mood, hop: hop);
    final cx = center.dx, cy = center.dy;
    final ground = cy + size / 2.0 - foot * size; // where the feet touch
    if (shadow) {
      final lift = !m.bottom;
      final sw = size * (lift ? 0.38 : 0.55) * (1.0 - 0.25 * math.min(1.0, m.dy < 0 ? -m.dy * 5.0 : 0.0));
      final gy = ground + (lift ? size * 0.10 : 0.0);
      drawSoftEllipse(canvas, Offset(cx, gy), sw, math.max(6.0, sw / 5.0), kText, 70);
    }
    final w = size * m.sx;
    final h = size * m.sy;
    canvas.save();
    final Rect dst;
    if (m.bottom) {
      canvas.translate(cx + m.dx * size, ground + m.dy * size);
      dst = Rect.fromLTWH(-w / 2, -h, w, h);
    } else {
      canvas.translate(cx + m.dx * size, cy + m.dy * size);
      dst = Rect.fromLTWH(-w / 2, -h / 2, w, h);
    }
    if (m.rot.abs() > 0.05) canvas.rotate(-m.rot * math.pi / 180.0); // pygame rotates counter-clockwise
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    return true;
  }

  /// Static picture for picker grids.
  static bool drawThumb(Canvas canvas, String id, Offset center, double size) {
    final img = sprite(id, '');
    if (img == null) return false;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: center, width: size, height: size),
      Paint()..filterQuality = FilterQuality.medium,
    );
    return true;
  }
}
