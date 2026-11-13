import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const double _cx = 450, _cy = 275; // centre of the light's path
const double _ax = 270, _ay = 55; // how far it drifts sideways / up and down
const double _baseSpeed = 2 * math.pi / 16; // one figure-eight about every 16 seconds, slowing down
const double _end = 78.0; // seconds until the light comes to rest

class _Prompt {
  final double start;
  final String main;
  final String hint;
  const _Prompt(this.start, this.main, this.hint);
}

// (start second, main prompt, optional hint)  -- keep each start below _end
const List<_Prompt> _prompts = [
  _Prompt(0, 'Follow the light with your eyes. Keep your head still.',
      "If that's uncomfortable, simply rest your gaze on the glow."),
  _Prompt(14, 'Nice and slow. Let your shoulders drop.', ''),
  _Prompt(30, 'Let your jaw soften. Let your hands rest.', ''),
  _Prompt(46, 'Notice your breath, without changing it.', ''),
  _Prompt(62, 'Nothing to fix right now. Nothing to do.', ''),
];

const List<double> _closingChord = [523.25, 659.25, 783.99, 1046.50]; // C, E, G, C

class LandingScene extends StatefulWidget {
  const LandingScene({super.key});

  @override
  State<LandingScene> createState() => _LandingSceneState();
}

class _LandingSceneState extends State<LandingScene> with SceneLoop {
  double _t = 0, _theta = 0, _settle = 0, _trailT = 0;
  List<Offset> _trail = <Offset>[];
  bool _ended = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Sound.warmMusic(); // build the lullaby in the background
    startLoop();
  }

  @override
  void dispose() {
    Sound.stopMusic(800);
    stopLoop();
    super.dispose();
  }

  void _restart() {
    setState(() {
      _t = 0;
      _theta = 0;
      _settle = 0;
      _trail = <Offset>[];
      _trailT = 0;
      _ended = false;
      _done = false;
    });
  }

  Offset _orbPos() {
    final x = _cx + _ax * math.sin(_theta);
    final y = _cy + _ay * math.sin(2 * _theta);
    final s = ease(_settle);
    return Offset(x * (1 - s) + _cx * s, y * (1 - s) + _cy * s);
  }

  @override
  void onTick(double dt) {
    _t += dt;
    final p = math.min(1.0, _t / _end);
    if (_t < _end) {
      _theta += dt * _baseSpeed * (1 - 0.65 * p); // drifts slower and slower
      Sound.ensureMusic();
    } else {
      _settle = math.min(1.0, _settle + dt / 4.0); // glides to the centre and rests
      if (!_ended) {
        _ended = true;
        Sound.stopMusic(5000); // the lullaby fades away...
        Sound.chime(_closingChord); // ...under a soft sparkle
      }
    }
    _trailT += dt;
    if (_trailT >= 0.15) {
      _trailT = 0;
      _trail.add(_orbPos());
      if (_trail.length > 10) _trail = _trail.sublist(_trail.length - 10);
    }
    if (!_done && _t >= _end + 1.5) {
      setState(() => _done = true);
    }
  }

  void _words(Canvas c, String main, String hint, double alpha255) {
    const cx = kW / 2;
    final al = alpha255 / 255.0;
    var y = 100.0;
    for (final line in wrapText(main, 32, true, 640)) {
      drawText(c, line, 32, kDuskText, Offset(cx, y), bold: true, alpha: al);
      y += 40;
    }
    if (hint.isNotEmpty) {
      y += 14;
      for (final line in wrapText(hint, 21, false, 640)) {
        drawText(c, line, 21, kDuskDim, Offset(cx, y), alpha: al * 0.9);
        y += 27;
      }
    }
  }

  void _draw(Canvas c) {
    drawGradientBg(c, kDuskTop, kDuskBottom, grain: 0.7);
    const cx = kW / 2;
    final comp = Companion.I;
    final p = math.min(1.0, _t / _end);

    drawText(c, 'GENTLE LANDING', 18, kDuskDim, const Offset(cx, 44), alpha: 200 / 255);

    // faint trail, to make the light easy to follow
    for (var i = 0; i < _trail.length; i++) {
      final op = (10 + 85 * (i + 1) / math.max(1, _trail.length)) / 255;
      drawGlow(c, _trail[i], 40, const Color(0xFFFFBE8C), strength: 170, opacity: op);
    }

    // the light: a soft halo that pulses very slowly, with a bright centre
    final o = _orbPos();
    final pulse = 0.5 + 0.5 * math.sin(_t * 0.63);
    drawGlow(c, o, 150 * (0.80 - 0.10 * p + 0.06 * pulse), const Color(0xFFFFC896),
        strength: 190, opacity: (150 + 60 * pulse) / 255);
    drawGlow(c, o, 46 * (0.95 + 0.05 * pulse), const Color(0xFFFFF2DC), strength: 255);

    // words
    if (_t >= _end) {
      final a = math.min(1.0, (_t - _end) / 1.5) * 255;
      _words(c, 'You did well. Take all the time you need.', '${comp.name} is proud of you.', a);
    } else {
      var idx = 0;
      for (var i = 0; i < _prompts.length; i++) {
        if (_t >= _prompts[i].start) idx = i;
      }
      final start = _prompts[idx].start;
      final end = idx + 1 < _prompts.length ? _prompts[idx + 1].start : _end;
      final local = _t - start;
      final a = math.max(0.0, math.min(1.0, math.min(local / 1.2, (end - local) / 1.0))) * 255;
      _words(c, _prompts[idx].main, _prompts[idx].hint, a);
    }

    // companion: eyes closed and breathing slowly, then happy at the end
    comp.draw(c, const Offset(110, 465), 130, mood: _t >= _end ? 'happy' : 'sleepy', breath: pulse);
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
          if (_done) ...[
            CalmButton(
              rect: Rect.fromLTWH(kW / 2 - 265, 505, 250, 56),
              title: 'Stay a little longer',
              color: kSoft,
              hoverColor: kSoftHover,
              textColor: kDuskText,
              titleSize: 20,
              onTap: _restart,
            ),
            CalmButton(
              rect: Rect.fromLTWH(kW / 2 + 15, 505, 250, 56),
              title: 'Back home',
              color: kDark,
              hoverColor: kDarkHover,
              textColor: kDuskText,
              titleSize: 24,
              onTap: () => Nav.I.go('home'),
            ),
          ],
        ],
      ),
    );
  }
}
