// The companion: saving, growth, speech, reactions and drawing (core/companion.py).
// The Python app also had a code-drawn fallback pet for when the sprite pictures are missing.
// All 51 pictures ship with this project, so that fallback is not ported.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'pets.dart';
import 'store.dart';
import 'util.dart';

class Stage {
  final int days;
  final String name;
  final double scale;
  const Stage(this.days, this.name, this.scale);
}

/// (days of use needed, stage name, drawing scale)
const List<Stage> kStages = [
  Stage(0, 'Tiny', 0.74),
  Stage(3, 'Little', 0.83),
  Stage(10, 'Growing', 0.92),
  Stage(30, 'Grown', 1.0),
];

const Map<String, String> kGroupSound = {
  'cats': 'Purr...', 'dogs': 'Woof!', 'small': '*nose wiggle*', 'birds': 'Tweet!',
  'bugs': '*bzzz*', 'sea': '*blub blub*', 'magic': '*sparkle*',
};

const List<String> kGreetings = [
  '{n} is happy you\'re here.',
  'Take a breath. {n} is right here with you.',
  '{n} saved you a quiet spot.',
  'Nothing to fix. {n} is just glad you came.',
];

class _Heart {
  final double dx;
  final double t0;
  _Heart(this.dx, this.t0);
}

class _Spark {
  final double a0, rad, spd, sz;
  final Color col;
  const _Spark(this.a0, this.rad, this.spd, this.col, this.sz);
}

const List<_Spark> _sparks = [
  _Spark(0.3, 0.64, 0.22, Color(0xFFFFE296), 0.13),
  _Spark(1.9, 0.70, -0.18, Color(0xFFFFFFFF), 0.10),
  _Spark(3.4, 0.62, 0.16, Color(0xFFCEBCFF), 0.12),
  _Spark(4.7, 0.68, -0.20, Color(0xFFFFD6E8), 0.09),
  _Spark(5.6, 0.60, 0.19, Color(0xFFBAE8FF), 0.10),
];

class Companion {
  Companion._();
  static final Companion I = Companion._();

  String name = '';
  String petId = Pets.defaultPet;
  int growth = 0;
  String born = '';
  String lastVisit = '';
  String lastGrowDay = '';
  int daysAway = 0;
  double cheerStart = -10.0;
  double cheerUntil = 0.0;
  String sayText = '';
  double sayUntil = 0.0;
  String? pending;
  final List<_Heart> _hearts = <_Heart>[];
  Rect rect = Rect.zero; // where the pet was drawn last frame (for tapping)
  final int _greetIdx = math.Random().nextInt(kGreetings.length);

  bool get exists => name.isNotEmpty;

  // ---------------------------------------------------------------- saving
  void load() {
    final d = Store.getMap('companion');
    if (d == null) return;
    name = _cut(d['name']?.toString() ?? '', 14);
    final pid = d['pet'];
    petId = (pid is String && Pets.byId.containsKey(pid)) ? pid : Pets.defaultPet;
    final g = d['growth'];
    growth = g is int ? g : (g is num ? g.toInt() : 0);
    born = d['born']?.toString() ?? '';
    lastVisit = d['last_visit']?.toString() ?? '';
    lastGrowDay = d['last_grow_day']?.toString() ?? '';
    if (exists) {
      final today = isoToday();
      if (lastVisit.isNotEmpty) {
        daysAway = daysBetween(lastVisit, today) ?? 0;
      }
      lastVisit = today;
      if (born.isEmpty) born = today;
      save();
    }
  }

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

  void save() {
    Store.setMap('companion', {
      'name': name,
      'pet': petId,
      'growth': growth,
      'born': born,
      'last_visit': lastVisit,
      'last_grow_day': lastGrowDay,
    });
  }

  void finishSetup(String newName) {
    final today = isoToday();
    name = newName;
    born = today;
    lastVisit = today;
    save();
  }

  // ---------------------------------------------------------------- growth
  int stageIndex() {
    var idx = 0;
    for (var i = 0; i < kStages.length; i++) {
      if (growth >= kStages[i].days) idx = i;
    }
    return idx;
  }

  int daysTogether() {
    final d = daysBetween(born, isoToday());
    if (d == null) return 1;
    return math.max(1, d + 1);
  }

  /// One growth point per day of using a calming tool. Returns true if it grew.
  bool grow({bool force = false}) {
    final today = isoToday();
    if (!force && lastGrowDay == today) {
      pending = '$name is proud of you.';
      return false;
    }
    final before = stageIndex();
    growth += 1;
    lastGrowDay = today;
    save();
    if (stageIndex() > before) {
      pending = '$name grew bigger today! Thank you for looking after yourself.';
    } else {
      pending = '$name feels a little stronger today.';
    }
    return true;
  }

  // ---------------------------------------------------------------- voice and reactions
  void say(String text, [double seconds = 4.0]) {
    sayText = text;
    sayUntil = nowSeconds() + seconds;
  }

  /// Call when the home screen opens: shows any pending message.
  void arrive() {
    final p = pending;
    if (p != null) {
      say(p, 8.0);
      pending = null;
    }
  }

  void cheer([double seconds = 2.0]) {
    final now = nowSeconds();
    cheerStart = now;
    cheerUntil = now + seconds;
  }

  String soundText() {
    final info = Pets.byId[petId];
    if (info != null) return kGroupSound[info.group] ?? '*happy sounds*';
    return '*happy sounds*';
  }

  void pet() {
    cheer(2.5);
    final now = nowSeconds();
    final rnd = math.Random();
    for (var i = 0; i < 3; i++) {
      _hearts.add(_Heart(rnd.nextDouble() * 0.36 - 0.18, now + i * 0.18));
    }
    say('${soundText()} $name loves that.', 3.0);
  }

  String greeting() {
    if (growth == 0 && daysTogether() <= 1) {
      return 'Hi, I\'m $name. I\'ll be right here whenever you need me.';
    }
    if (daysAway >= 2) return '$name missed you. Welcome back, no rush.';
    return kGreetings[_greetIdx].replaceAll('{n}', name);
  }

  String speech() {
    if (nowSeconds() < sayUntil) return sayText;
    return greeting();
  }

  // ---------------------------------------------------------------- drawing
  /// mood: 'calm', 'happy' or 'sleepy' (closed eyes). breath: 0..1 swells gently.
  /// full = true ignores the growth scale (used by the chooser). lite = true skips the hop.
  /// sparkles defaults to on, unless a mood is forced.
  void draw(Canvas canvas, Offset center, double size,
      {String? mood, double breath = 0.0, bool full = false, bool lite = false, bool? sparkles, String? petIdOverride}) {
    final t = nowSeconds();
    final idx = stageIndex();
    final moodArg = mood;
    final m = mood ?? (t < cheerUntil ? 'happy' : 'calm');
    final withSparkles = sparkles ?? (moodArg == null);

    final scale = full ? 1.0 : kStages[idx].scale;
    final s = math.max(30.0, size * scale * (1 + 0.05 * breath));
    final cx = center.dx, cy = center.dy;
    final ground = cy + size / 2;

    final age = t - cheerStart;
    final hopping = age >= 0 && age < 0.7 && !lite;

    final pid = petIdOverride ?? petId;
    final box = s * 1.15;
    final cyBox = ground - box / 2 + Pets.foot * box;
    Pets.draw(canvas, pid, Offset(cx, cyBox), box, lite ? 0.0 : t,
        breath: lite ? 0.5 : (breath != 0.0 ? breath : null), mood: m, hop: hopping ? age / 0.7 : 0.0);
    final r = Rect.fromLTWH(cx - box * 0.4, ground - box * 0.9, box * 0.8, box * 0.9);
    rect = r;

    // floating sparkles
    if (withSparkles && !lite) {
      for (var i = 0; i < _sparks.length; i++) {
        final sp = _sparks[i];
        final a = sp.a0 + t * sp.spd;
        final x = cx + math.cos(a) * s * sp.rad;
        final y = r.center.dy - s * 0.05 + math.sin(a) * s * sp.rad * 0.72;
        final tw = 0.5 + 0.5 * math.sin(t * 1.8 + i * 1.9);
        drawSparkle(canvas, x, y, s * sp.sz * (0.55 + 0.5 * tw), sp.col, 110 + 120 * tw);
      }
    }

    // hearts after petting
    if (_hearts.isNotEmpty && !lite) {
      final alive = <_Heart>[];
      for (final h in _hearts) {
        final ageH = t - h.t0;
        if (ageH < 0) {
          alive.add(h);
          continue;
        }
        if (ageH > 1.9) continue;
        alive.add(h);
        final frac = ageH / 1.9;
        final x = cx + h.dx * s + math.sin(ageH * 3 + h.dx * 10) * 6;
        final y = r.top + s * 0.12 - ageH * s * 0.28;
        drawHeart(canvas, x, y, s * (0.10 + 0.04 * frac), 255 * math.pow(1 - frac, 0.7).toDouble());
      }
      _hearts
        ..clear()
        ..addAll(alive);
    }
  }
}

// ---------------------------------------------------------------- speech bubble
void drawBubble(Canvas canvas, String text, double centerX, double top, {double maxW = 600, double size = 24}) {
  final lines = wrapText(text, size, true, maxW - 48);
  final lh = (size * 1.3).floorToDouble();
  var w = 0.0;
  for (final l in lines) {
    w = math.max(w, textWidth(l, size, bold: true));
  }
  w += 48;
  final h = lines.length * lh + 26;
  final rect = Rect.fromLTWH(centerX - w / 2, top, w, h);
  drawGlass(canvas, rect, radius: 28, alpha: 225);
  final tail = Path()
    ..moveTo(centerX - 14, rect.bottom - 1)
    ..lineTo(centerX + 14, rect.bottom - 1)
    ..lineTo(centerX, rect.bottom + 16)
    ..close();
  canvas.drawPath(tail, Paint()..color = const Color(0xE1FFFFFF));
  for (var i = 0; i < lines.length; i++) {
    drawText(canvas, lines[i], size, kText, Offset(centerX, rect.top + 13 + lh / 2 + i * lh), bold: true);
  }
}
