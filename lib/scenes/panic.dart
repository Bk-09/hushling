import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/palette.dart';
import '../core/scene_art.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const double kInhale = 4.0;
const double kExhaleStart = 6.0;
const double kExhaleMax = 8.0;
const int kCyclesBeforeContinue = 5;

const double _baseY = 430; // where the flame's base sits (wide layout)

const Color _glowBlue = Color(0xFF3C8CFF);
const Color _emberBlue = Color(0xFF9CD2FF);
const double _flameAspect = 562 / 794; // width / height of assets/scenes/flame.jpg
const double _flameBase = 0.955; // how far down the picture the flame's base sits
const int _strips = 40;

/// Draws the blue flame picture. It is a black-background photo, so it is added to the scene
/// (BlendMode.plus): black adds nothing and the flame simply glows. The picture is drawn in thin
/// horizontal strips that sway more towards the tip, so the flame flows instead of staying rigid.
void drawBlueFlame(Canvas c, double cx, double baseY, double height, double t, double lvl) {
  final img = SceneArt.get('flame.jpg');
  if (img == null) return;
  final flicker = 1 + 0.015 * math.sin(t * 7) + 0.010 * math.sin(t * 11.3);
  final h = height * flicker;
  final w = height * _flameAspect;
  final top = baseY - h * _flameBase;
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final paint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromARGB(a8(0.74 + 0.26 * lvl), 255, 255, 255);
  for (var i = 0; i < _strips; i++) {
    final v0 = i / _strips, v1 = (i + 1) / _strips; // 0 = top of the picture
    final u = 1.0 - (v0 + v1) / 2; // 0 at the base .. 1 at the tip
    final dx = w * 0.045 * u * u * math.sin(t * 1.25 + u * 2.4) + w * 0.008 * u * math.sin(t * 4.3 + u * 5.0);
    c.drawImageRect(
      img,
      Rect.fromLTRB(0, v0 * ih, iw, v1 * ih),
      Rect.fromLTWH(cx - w / 2 + dx, top + v0 * h, w, h / _strips),
      paint,
    );
  }
}

/// Tiny blue sparks that drift up from the flame.
void drawEmbers(Canvas c, double cx, double baseY, double height, double t) {
  for (var i = 0; i < 16; i++) {
    final ph = (t * (0.05 + 0.02 * (i % 3)) + i * 0.173) % 1.0;
    final x = cx + math.sin(i * 12.9898 + t * 0.4) * height * 0.20 * (0.4 + ph);
    final y = baseY - height * 0.12 - ph * height * 1.05;
    drawGlow(c, Offset(x, y), 3.0 + (i % 4), _emberBlue, strength: 255, opacity: math.sin(math.pi * ph) * 0.8);
  }
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
    drawGradientBg(c, kDuskTop, kDuskBottom, grain: 0.7, w: Layout.w, h: Layout.h);
    final port = Layout.portrait;
    final cx = Layout.w / 2;
    final baseY = port ? Layout.h * 0.60 : _baseY;
    final t = _t, lvl = _level;
    final size = 0.62 + 0.5 * lvl; // the flame swells as you breathe in
    final fh = (port ? 400.0 : 300.0) * size; // flame picture height

    // soft blue glow behind the flame, and a faint pool of light under it
    final g = 0.55 + 0.6 * lvl;
    drawGlow(c, Offset(cx, baseY - fh * 0.36), (port ? 330 : 250) * g, _glowBlue,
        strength: 170, opacity: (95 + 110 * lvl) / 255);
    drawSoftEllipse(c, Offset(cx, baseY + 6), fh * 0.80, math.max(14.0, fh * 0.07), _glowBlue, 70 + 60 * lvl);

    // companion sits beside the flame, eyes closed, breathing with you
    Companion.I.draw(c, port ? Offset(cx - 215, baseY + 20) : Offset(cx - 285, 355), port ? 150 : 140,
        mood: 'sleepy', breath: lvl);

    drawBlueFlame(c, cx, baseY, fh, t, lvl);
    drawEmbers(c, cx, baseY, fh, t);

    // words
    final fadeIn = math.min(1.0, _t / 2.0);
    final msg = '${Companion.I.name} is here with you. This will pass.';
    if (port) {
      var my = 104.0;
      for (final line in wrapText(msg, 28, false, 520)) {
        drawText(c, line, 28, kDuskDim, Offset(cx, my), alpha: fadeIn);
        my += 38;
      }
    } else {
      drawText(c, msg, 26, kDuskDim, Offset(cx, 60), alpha: fadeIn);
    }
    final phaseFade = math.min(1.0, _phaseT / 0.8);
    drawText(c, _phase == 'in' ? 'Breathe in' : 'Slowly let it go', port ? 46 : 40, kDuskText,
        Offset(cx, port ? baseY + 120 : 490),
        bold: true, alpha: phaseFade);
  }

  @override
  Widget build(BuildContext context) {
    final port = Layout.portrait;
    return EscScope(
      onEsc: () => Nav.I.go('home'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: paintLayer(_draw)),
          CalmButton(
            rect: port ? Rect.fromLTWH(40, Layout.h - 120, 150, 56) : Rect.fromLTWH(24, 540, 130, 44),
            title: 'Leave',
            color: kDark,
            hoverColor: kDarkHover,
            textColor: kDuskText,
            titleSize: 20,
            onTap: () => Nav.I.go('home'),
          ),
          SoundButton(
            rect: port ? Rect.fromLTWH(Layout.w - 124, 60, 100, 36) : Rect.fromLTWH(kW - 124, 72, 100, 36),
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
          ),
          // always visible, so first-time users can see there is more after the breathing;
          // it becomes the brighter "Continue gently" once a few breaths have passed
          CalmButton(
              rect: port ? Rect.fromLTWH(210, Layout.h - 120, 350, 56) : Rect.fromLTWH(kW / 2 - 150, 530, 300, 56),
              title: _showContinue ? 'Continue gently' : 'Next: grounding',
              color: _showContinue ? kDark : kSoft,
              hoverColor: _showContinue ? kDarkHover : kSoftHover,
              textColor: kDuskText,
              titleSize: _showContinue ? 24 : 21,
              onTap: () => Nav.I.go('grounding'),
            ),
        ],
      ),
    );
  }
}
