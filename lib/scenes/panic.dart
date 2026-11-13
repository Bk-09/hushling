import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const double kInhale = 4.0;
const double kExhaleStart = 6.0;
const double kExhaleMax = 8.0;
const int kCyclesBeforeContinue = 5;

const double _baseY = 412; // where the flame sits in the bowl
const double _glowY = 300;

/// Teardrop outline: round at the bottom, pointed and swaying at the tip.
Path flamePath(double cx, double baseY, double w, double h, double t, double sway, double seed) {
  const n = 40;
  final right = <Offset>[];
  final left = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final u = i / n;
    double wd;
    if (u < 0.35) {
      final q = (u - 0.35) / 0.35;
      wd = w * math.sqrt(math.max(0.0, 1 - q * q));
    } else {
      wd = w * math.pow(1 - (u - 0.35) / 0.65, 1.5).toDouble();
    }
    var off = sway * (u * u) * math.sin(t * 1.3 + seed);
    off += 2.0 * u * math.sin(t * 5.1 + seed * 2); // tiny flicker
    final y = baseY - u * h;
    right.add(Offset(cx + off + wd, y));
    left.add(Offset(cx + off - wd, y));
  }
  final pts = <Offset>[...right, ...left.reversed];
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i].dy);
  }
  path.close();
  return path;
}

class PanicScene extends StatefulWidget {
  const PanicScene({super.key});

  @override
  State<PanicScene> createState() => _PanicSceneState();
}

class _PanicSceneState extends State<PanicScene> with SceneLoop {
  double _t = 0;
  int _cycle = 0;
  String _phase = 'in';
  double _phaseT = 0;
  double _level = 0;
  bool _needStart = true;
  bool _showContinue = false;

  double _exhaleLen() => math.min(kExhaleMax, kExhaleStart + 0.5 * _cycle);

  @override
  void initState() {
    super.initState();
    // build the breath sounds in the background so nothing stutters later
    Sound.warmBreath(kInhale, [for (var c = 0; c < 6; c++) math.min(kExhaleMax, kExhaleStart + 0.5 * c)]);
    startLoop();
  }

  @override
  void dispose() {
    Sound.stopBreath();
    stopLoop();
    super.dispose();
  }

  @override
  void onTick(double dt) {
    if (_needStart) {
      _needStart = false;
      Sound.playCycle(kInhale, _exhaleLen());
    }
    _t += dt;
    _phaseT += dt;
    var length = _phase == 'in' ? kInhale : _exhaleLen();
    if (_phaseT >= length) {
      _phaseT -= length;
      if (_phase == 'in') {
        _phase = 'out';
      } else {
        _phase = 'in';
        _cycle += 1;
        Sound.playCycle(kInhale, _exhaleLen()); // one sound per whole breath
      }
      length = _phase == 'in' ? kInhale : _exhaleLen();
    }
    final p = _phaseT / length;
    _level = _phase == 'in' ? ease(p) : 1 - ease(p);
    if (!_showContinue && _cycle >= kCyclesBeforeContinue) {
      setState(() => _showContinue = true);
    }
  }

  void _draw(Canvas c) {
    drawGradientBg(c, kDuskTop, kDuskBottom, grain: 0.7);
    const cx = kW / 2;
    final t = _t, lvl = _level;

    // soft glow behind the flame
    final g = 0.55 + 0.6 * lvl;
    drawGlow(c, const Offset(cx, _glowY), 300 * g, kGlowOrange, strength: 170, opacity: (110 + 110 * lvl) / 255);

    // bowl
    c.drawOval(Rect.fromLTWH(cx - 95, _baseY - 16, 190, 44), Paint()..color = const Color(0xFF583E68));
    c.drawOval(Rect.fromLTWH(cx - 80, _baseY - 12, 160, 24), Paint()..color = const Color(0xFF3C2C52));

    // companion sits beside the flame, eyes closed, breathing with you
    Companion.I.draw(c, const Offset(cx - 255, 355), 150, mood: 'sleepy', breath: lvl);

    // flame: three layers, outer to inner
    final size = 0.62 + 0.5 * lvl;
    final flicker = 1 + 0.02 * math.sin(t * 7) + 0.015 * math.sin(t * 11.3);
    final h = 210 * size * flicker, w = 62 * size;
    const layers = <List<Object>>[
      [1.00, Color(0xFFF6965C), 235],
      [0.72, Color(0xFFFFC478), 240],
      [0.42, Color(0xFFFFEEC8), 245],
    ];
    for (var k = 0; k < layers.length; k++) {
      final scale = layers[k][0] as double;
      final color = layers[k][1] as Color;
      final alpha = layers[k][2] as int;
      final path = flamePath(cx, _baseY - (1 - scale) * 14, w * scale, h * scale, t, 7, k * 0.7);
      c.drawPath(path, Paint()..color = color.withAlpha(alpha));
    }

    // words
    final fadeIn = math.min(1.0, _t / 2.0);
    drawText(c, '${Companion.I.name} is here with you. This will pass.', 26, kDuskDim, const Offset(cx, 60),
        alpha: fadeIn);
    final phaseFade = math.min(1.0, _phaseT / 0.8);
    drawText(c, _phase == 'in' ? 'Breathe in' : 'Slowly let it go', 40, kDuskText, const Offset(cx, 490),
        bold: true, alpha: phaseFade);
  }

  @override
  Widget build(BuildContext context) {
    return EscScope(
      onEsc: () => Nav.I.go('home'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: paintLayer(_draw)),
          CalmButton(
            rect: Rect.fromLTWH(24, 540, 130, 44),
            title: 'Leave',
            color: kDark,
            hoverColor: kDarkHover,
            textColor: kDuskText,
            titleSize: 20,
            onTap: () => Nav.I.go('home'),
          ),
          SoundButton(
            rect: Rect.fromLTWH(kW - 124, 72, 100, 36),
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
          ),
          if (_showContinue)
            CalmButton(
              rect: Rect.fromLTWH(kW / 2 - 150, 530, 300, 56),
              title: 'Continue gently',
              color: kDark,
              hoverColor: kDarkHover,
              textColor: kDuskText,
              titleSize: 24,
              onTap: () => Nav.I.go('grounding'),
            ),
        ],
      ),
    );
  }
}
