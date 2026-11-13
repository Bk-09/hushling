// Small shared helpers: clock, easing, colours, text and soft shapes.
// Everything the Python app did with pygame.draw / numpy surfaces is done here with a Canvas.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'palette.dart';

/// Set to 'Nunito' after you add the font files (see pubspec.yaml). null = the system font.
const String? kFontFamily = null;

/// pygame font sizes are pixel heights; Flutter sizes are em sizes. This keeps text the same size.
const double kFontScale = 0.80;

/// True on phones and tablets (on-screen keyboard), false on desktop and web.
bool get isMobilePlatform =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

final Stopwatch _clock = Stopwatch()..start();

/// Seconds since the app started (like pygame.time.get_ticks() / 1000).
double nowSeconds() => _clock.elapsedMicroseconds / 1000000.0;

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

int a8(double a01) {
  final v = (a01 * 255).round();
  return v < 0 ? 0 : (v > 255 ? 255 : v);
}

/// Smooth 0->1 curve, gentle at both ends (cosine).
double ease(double p) => 0.5 - 0.5 * math.cos(math.pi * clampD(p, 0, 1));

/// Smoothstep.
double smooth(double p) {
  final q = clampD(p, 0, 1);
  return q * q * (3 - 2 * q);
}

/// A soft overshoot: grows a little past full size, then settles.
double popCurve(double p) {
  final q = clampD(p, 0, 1);
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final d = q - 1;
  return 1 + c3 * d * d * d + c1 * d * d;
}

Color withA(Color c, double alpha01) => c.withAlpha(a8(alpha01));

Color lerpColor(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

// ---------------------------------------------------------------- dates (ISO yyyy-mm-dd)
String isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String isoToday() => isoOf(DateTime.now());

DateTime? parseIso(String s) {
  try {
    final p = s.split('-');
    if (p.length != 3) return null;
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  } catch (_) {
    return null;
  }
}

/// Whole days from [a] to [b] (both ISO strings). null if either is invalid.
int? daysBetween(String a, String b) {
  final da = parseIso(a);
  final db = parseIso(b);
  if (da == null || db == null) return null;
  return db.difference(da).inDays;
}

/// Like Python's date.today().toordinal().
int todayOrdinal() {
  final n = DateTime.now();
  return DateTime.utc(n.year, n.month, n.day).difference(DateTime.utc(1, 1, 1)).inDays + 1;
}

const List<String> _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Wed 12 Nov"
String niceDate(String iso) {
  final d = parseIso(iso);
  if (d == null) return '';
  return '${_wd[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')} ${_mo[d.month - 1]}';
}

// ---------------------------------------------------------------- text
TextStyle calmTextStyle(double size, {bool bold = false, Color color = kText}) => TextStyle(
      fontSize: size * kFontScale,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontFamily: kFontFamily,
      height: 1.0,
      decoration: TextDecoration.none,
    );

TextPainter _layout(String s, double size, bool bold, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: calmTextStyle(size, bold: bold, color: color)),
    textDirection: TextDirection.ltr,
  );
  tp.layout();
  return tp;
}

double textWidth(String s, double size, {bool bold = false}) =>
    _layout(s, size, bold, kText).width;

/// Draws text centred on [center]. [alpha] is 0..1 (the colour itself should be opaque).
void drawText(Canvas c, String s, double size, Color color, Offset center,
    {bool bold = false, double alpha = 1.0}) {
  if (alpha <= 0 || s.isEmpty) return;
  final tp = _layout(s, size, bold, alpha >= 1.0 ? color : color.withAlpha(a8(alpha)));
  tp.paint(c, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
}

/// Draws text with its left edge at [x] and vertical middle at [cy].
void drawTextLeft(Canvas c, String s, double size, Color color, double x, double cy,
    {bool bold = false}) {
  if (s.isEmpty) return;
  final tp = _layout(s, size, bold, color);
  tp.paint(c, Offset(x, cy - tp.height / 2));
}

List<String> wrapText(String text, double size, bool bold, double maxW) {
  final lines = <String>[];
  var cur = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final test = cur.isEmpty ? word : '$cur $word';
    if (textWidth(test, size, bold: bold) <= maxW) {
      cur = test;
    } else {
      if (cur.isNotEmpty) lines.add(cur);
      cur = word;
    }
  }
  lines.add(cur);
  return lines;
}

// ---------------------------------------------------------------- soft shapes
/// A soft round glow (like make_glow in the Python app). [strength] is 0..255.
void drawGlow(Canvas c, Offset center, double radius, Color color,
    {double strength = 150, double opacity = 1.0}) {
  if (radius < 1 || opacity <= 0) return;
  const n = 8;
  final colors = <Color>[];
  final stops = <double>[];
  for (var i = 0; i <= n; i++) {
    final u = i / n;
    final a = math.pow(1 - u, 1.6).toDouble() * strength / 255.0 * opacity;
    colors.add(color.withAlpha(a8(a)));
    stops.add(u);
  }
  final paint = Paint()..shader = ui.Gradient.radial(center, radius, colors, stops);
  c.drawCircle(center, radius, paint);
}

/// A soft elliptical ground shadow of [w] x [h] centred on [center].
void drawSoftEllipse(Canvas c, Offset center, double w, double h, Color color, double maxAlpha) {
  if (w < 2 || h < 1) return;
  const n = 8;
  final colors = <Color>[];
  final stops = <double>[];
  for (var i = 0; i <= n; i++) {
    final u = i / n;
    colors.add(color.withAlpha(a8(math.pow(1 - u, 1.2).toDouble() * maxAlpha)));
    stops.add(u);
  }
  c.save();
  c.translate(center.dx, center.dy);
  c.scale(1.0, h / w);
  c.drawCircle(Offset.zero, w / 2, Paint()..shader = ui.Gradient.radial(Offset.zero, w / 2, colors, stops));
  c.restore();
}

// ---------------------------------------------------------------- grain + gradients
class Grain {
  static ui.Image? image;

  /// Builds a small tile of fine noise once. The Python app added this noise to every gradient.
  static Future<void> init() async {
    const n = 160;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()));
    final rnd = math.Random(3);
    final buckets = <List<double>>[[], [], [], []];
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final r = rnd.nextInt(8);
        if (r < 4) buckets[r].addAll([x + 0.5, y + 0.5]);
      }
    }
    final cols = <Color>[
      const Color(0x0E000000),
      const Color(0x08000000),
      const Color(0x1CFFFFFF),
      const Color(0x10FFFFFF),
    ];
    for (var i = 0; i < 4; i++) {
      final p = Paint()
        ..color = cols[i]
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false;
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(buckets[i]), p);
    }
    image = await rec.endRecording().toImage(n, n);
  }
}

void drawGrain(Canvas c, Rect r, {double amount = 1.0}) {
  final img = Grain.image;
  if (img == null) return;
  final id = Float64List.fromList(<double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  final p = Paint()..shader = ui.ImageShader(img, TileMode.repeated, TileMode.repeated, id);
  if (amount != 1.0) {
    p.colorFilter = ColorFilter.mode(Color.fromARGB(a8(amount), 255, 255, 255), BlendMode.modulate);
  }
  c.drawRect(r, p);
}

void drawGradientBg(Canvas c, Color top, Color bottom, {double grain = 1.0}) {
  final r = Rect.fromLTWH(0, 0, kW, kH);
  c.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [top, bottom]));
  drawGrain(c, r, amount: grain);
}

/// Grainy pastel gradient with slow drifting colour glows (AmbientBackground).
void drawAmbientBg(Canvas c) {
  drawGradientBg(c, kBgTop, kBgBottom);
  final t = nowSeconds();
  // radius, colour, strength, base x, base y, drift x, drift y, speed, phase
  const blobs = <List<double>>[
    [260, 0, 150, 130, 120, 40, 30, 0.20, 0.0],
    [300, 1, 150, 760, 520, 50, 35, 0.16, 2.0],
    [220, 2, 150, 790, 110, 35, 45, 0.24, 4.0],
    [240, 3, 120, 120, 500, 45, 30, 0.18, 1.0],
    [250, 4, 120, 450, 60, 60, 25, 0.14, 3.0],
  ];
  const cols = <Color>[kGlowPurple, kGlowOrange, kGlowPink, kGlowMint, kGlowSky];
  for (final b in blobs) {
    final x = b[3] + b[5] * math.sin(t * b[7] + b[8]);
    final y = b[4] + b[6] * math.cos(t * b[7] * 0.8 + b[8]);
    drawGlow(c, Offset(x, y), b[0], cols[b[1].toInt()], strength: b[2]);
  }
}

// ---------------------------------------------------------------- panels
/// Frosted-glass panel: translucent white, bright edge, soft shadow.
void drawGlass(Canvas c, Rect r, {double radius = 28, int alpha = 150}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  c.drawRRect(
    rr.shift(const Offset(0, 12)),
    Paint()
      ..color = kText.withAlpha(30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );
  c.drawRRect(rr, Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
  c.drawRRect(
    rr.deflate(1),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Color.fromARGB(math.min(255, alpha + 70), 255, 255, 255),
  );
}

// ---------------------------------------------------------------- little sprites
void drawSparkle(Canvas c, double x, double y, double size, Color color, double alpha255) {
  if (size < 2 || alpha255 <= 0) return;
  final s = size / 64.0;
  const pts = <Offset>[
    Offset(32, 2), Offset(38, 26), Offset(62, 32), Offset(38, 38),
    Offset(32, 62), Offset(26, 38), Offset(2, 32), Offset(26, 26),
  ];
  final path = Path();
  for (var i = 0; i < pts.length; i++) {
    final p = Offset(x + (pts[i].dx - 32) * s, y + (pts[i].dy - 32) * s);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  c.drawPath(path, Paint()..color = color.withAlpha(a8(alpha255 / 255.0)));
}

void drawHeart(Canvas c, double x, double y, double size, double alpha255) {
  if (size < 2 || alpha255 <= 0) return;
  final s = size / 64.0;
  final a = a8(alpha255 / 255.0);
  final col = Paint()..color = const Color(0xFFFF8CAA).withAlpha(a);
  Offset p(double px, double py) => Offset(x + (px - 32) * s, y + (py - 32) * s);
  c.drawCircle(p(20, 24), 14 * s, col);
  c.drawCircle(p(44, 24), 14 * s, col);
  final tri = Path()
    ..moveTo(p(7, 30).dx, p(7, 30).dy)
    ..lineTo(p(57, 30).dx, p(57, 30).dy)
    ..lineTo(p(32, 58).dx, p(32, 58).dy)
    ..close();
  c.drawPath(tri, col);
  c.drawCircle(p(16, 19), 4 * s, Paint()..color = Colors.white.withAlpha((a * 210 / 255).round()));
}
