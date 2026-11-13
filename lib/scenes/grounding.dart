import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
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
    drawGradientBg(c, kDuskTop, kDuskBottom, grain: 0.7);
    if (_i >= kSteps.length) return;
    const cx = kW / 2;

    // slow, quiet glow at the top (breathing rhythm, ~10 s per cycle)
    final pulse = 0.5 + 0.5 * math.sin(_t * 0.63);
    drawGlow(c, const Offset(cx, 100), 200 * (0.45 + 0.12 * pulse), kGlowOrange,
        strength: 150, opacity: (120 + 70 * pulse) / 255);

    final step = kSteps[_i];
    final a = math.min(1.0, _stepT / 0.8);

    drawText(c, step.label.toUpperCase(), 20, kDuskDim, const Offset(cx, 180), alpha: a);

    var y = 225.0;
    for (final line in wrapText(step.main, 34, true, 640)) {
      drawText(c, line, 34, kDuskText, Offset(cx, y), bold: true, alpha: a);
      y += 42;
    }
    y += 28;
    for (final line in wrapText(step.hint, 22, false, 640)) {
      drawText(c, line, 22, kDuskDim, Offset(cx, y), alpha: a * 0.9);
      y += 29;
    }

    // progress dots (no numbers, nothing to "fail")
    const n = 7;
    final x0 = cx - (n - 1) * 14;
    for (var k = 0; k < n; k++) {
      final col = k <= _i ? const Color(0xFFF0BE96) : const Color(0xFF6E5882);
      c.drawCircle(Offset(x0 + k * 28, 452), 5, Paint()..color = col);
    }

    // companion keeps you company in the corner
    Companion.I.draw(c, const Offset(810, 480), 130, mood: 'calm');
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
            rect: Rect.fromLTWH(kW / 2 - 150, 480, 300, 60),
            title: 'Done',
            color: kDark,
            hoverColor: kDarkHover,
            textColor: kDuskText,
            titleSize: 26,
            onTap: _advance,
          ),
          CalmButton(
            rect: Rect.fromLTWH(kW / 2 - 90, 550, 180, 38),
            title: 'Skip this one',
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
            titleSize: 18,
            onTap: _advance,
          ),
          CalmButton(
            rect: Rect.fromLTWH(24, 24, 110, 40),
            title: 'Leave',
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
            titleSize: 18,
            onTap: () => Nav.I.go('home'),
          ),
          SoundButton(
            rect: Rect.fromLTWH(kW - 124, 72, 100, 36),
            color: kSoft,
            hoverColor: kSoftHover,
            textColor: kDuskDim,
          ),
        ],
      ),
    );
  }
}
