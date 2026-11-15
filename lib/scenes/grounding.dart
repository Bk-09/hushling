import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

class _Step {
  final String label;
  final String main;
  final String hint;
  const _Step(this.label, this.main, this.hint);
}

// (label, main prompt, hint with many options so it fits any place)
const List<_Step> kSteps = [
  _Step('Your body', 'Notice where your body is being held right now.',
      'A chair, a seat, a bed, the floor, the ground, your feet inside your shoes. Feel the support under you.'),
  _Step('Touch', 'Find something you can touch.',
      'Your clothes, your own hands, a table, a bag strap, your phone. Notice how it feels: warm, smooth, rough, soft.'),
  _Step('See', 'Look around slowly. Find three things you can see.',
      "Anything at all, near or far, any colour. You don't need to say them out loud."),
  _Step('Hear', 'Listen for two sounds.',
      'A fan, voices, traffic, birds, footsteps, music, your own breathing. Quiet counts too.'),
  _Step('The air', 'Notice the air around you.', 'Any smell, or none at all. Notice the temperature on your skin.'),
  _Step('Where you are', 'Silently say where you are, and what day it is.',
      "Plain facts, like: I'm on a bus. It's Saturday. I'm at my desk. I'm at home."),
  _Step('Just this moment', 'Tell yourself: right now, in this moment, I am okay.',
      'Say it in any language, in your own words.'),
];

// One soft little chime per step: climbs gently, then settles back on the home note (C)
const List<double> kStepNotes = [523.25, 587.33, 659.25, 783.99, 880.00, 659.25, 523.25];

class GroundingScene extends StatefulWidget {
  const GroundingScene({super.key});

  @override
  State<GroundingScene> createState() => _GroundingSceneState();
}

class _GroundingSceneState extends State<GroundingScene> with SceneLoop {
  int _i = 0;
  double _t = 0;
  double _stepT = 0;

  @override
  void initState() {
    super.initState();
    Sound.warmMusic(); // the landing lullaby builds in the background while you ground yourself
    startLoop();
  }

  @override
  void dispose() {
    stopLoop();
    super.dispose();
  }

  void _advance() {
    if (_i >= kSteps.length) return;
    Sound.chime([kStepNotes[math.min(_i, kStepNotes.length - 1)]]);
    setState(() {
      _i += 1;
      _stepT = 0;
    });
    if (_i >= kSteps.length) {
      Companion.I.grow();
      Nav.I.go('landing');
    }
  }

  @override
  void onTick(double dt) {
    _t += dt;
    _stepT += dt;
  }

  void _draw(Canvas c) {
    drawGradientBg(c, kDuskTop, kDuskBottom, grain: 0.7, w: Layout.w, h: Layout.h);
    if (_i >= kSteps.length) return;
    final port = Layout.portrait;
    final cx = Layout.w / 2;
    final textW = port ? 520.0 : 640.0;
    final ext = port ? ((Layout.h - 1000) * 0.3).clamp(0.0, 90.0).toDouble() : 0.0; // spare height on tall phones

    // slow, quiet glow at the top (breathing rhythm, ~10 s per cycle)
    final pulse = 0.5 + 0.5 * math.sin(_t * 0.63);
    drawGlow(c, Offset(cx, port ? 190 + ext : 100), (port ? 240 : 200) * (0.45 + 0.12 * pulse), const Color(0xFF4FA3FF),
        strength: 150, opacity: (120 + 70 * pulse) / 255);

    final step = kSteps[_i];
    final a = math.min(1.0, _stepT / 0.8);

    drawText(c, step.label.toUpperCase(), 20, kDuskDim, Offset(cx, port ? 320 + ext : 180), alpha: a);

    final mainSize = port ? 36.0 : 34.0, hintSize = port ? 24.0 : 22.0;
    var y = port ? 372.0 + ext : 225.0;
    for (final line in wrapText(step.main, mainSize, true, textW)) {
      drawText(c, line, mainSize, kDuskText, Offset(cx, y), bold: true, alpha: a);
      y += port ? 46 : 42;
    }
    y += 28;
    for (final line in wrapText(step.hint, hintSize, false, textW)) {
      drawText(c, line, hintSize, kDuskDim, Offset(cx, y), alpha: a * 0.9);
      y += port ? 32 : 29;
    }

    // progress dots (no numbers, nothing to "fail")
    const n = 7;
    final x0 = cx - (n - 1) * 14;
    final dotsY = port ? Layout.h - 240 : 452.0;
    for (var k = 0; k < n; k++) {
      final col = k <= _i ? const Color(0xFF8FCBFF) : const Color(0xFF3A4D80);
      c.drawCircle(Offset(x0 + k * 28, dotsY), 5, Paint()..color = col);
    }

    // companion keeps you company (in the glow at the top on a phone, in the corner on a wide screen)
    if (port) {
      Companion.I.draw(c, Offset(cx, 190 + ext), 170, mood: 'calm');
    } else {
      Companion.I.draw(c, const Offset(810, 480), 130, mood: 'calm');
    }
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
            rect: port ? Rect.fromLTWH(40, Layout.h - 200, 520, 76) : Rect.fromLTWH(kW / 2 - 150, 480, 300, 60),
            title: 'Done',
            color: kDark,
            hoverColor: kDarkHover,
            textColor: kDuskText,
            titleSize: 26,
            onTap: _advance,
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(40, Layout.h - 108, 250, 44) : Rect.fromLTWH(kW / 2 - 200, 550, 190, 38),
            title: 'Skip this one',
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
            titleSize: 18,
            onTap: _advance,
          ),
          // a clear way on to the last step, so nobody has to find it by finishing every prompt
          CalmButton(
            rect: port ? Rect.fromLTWH(310, Layout.h - 108, 250, 44) : Rect.fromLTWH(kW / 2 + 10, 550, 190, 38),
            title: 'Next: gentle landing',
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskText,
            titleSize: 18,
            onTap: () => Nav.I.go('landing'),
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(24, 50, 110, 40) : Rect.fromLTWH(24, 24, 110, 40),
            title: 'Leave',
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
            titleSize: 18,
            onTap: () => Nav.I.go('home'),
          ),
          SoundButton(
            rect: port ? Rect.fromLTWH(Layout.w - 124, 56, 100, 36) : Rect.fromLTWH(kW - 124, 72, 100, 36),
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
          ),
        ],
      ),
    );
  }
}
