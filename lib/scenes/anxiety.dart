// The anxiety scene: a quiet moonlit pond (port of scenes/anxiety.py).
// Gentle level: tap the water, let worries float away on leaves.
// Deeper level: "Lotus Echo", a gentle listen-and-echo game with no wrong answers.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/levels.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const Color _skyTop = Color(0xFF7068B0);
const Color _skyBottom = Color(0xFFEEB6B0);
const Color _waterTop = Color(0xFF9C9AD4);
const Color _waterBottom = Color(0xFFC69ABA);

const Rect _pond = Rect.fromLTWH(70, 380, 800, 210);
const double _pcx = 70 + 800 / 2;
const double _pcy = 380 + 210 / 2;
const double _prx = 800 / 2;
const double _pry = 210 / 2;

const List<double> _penta = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50];
const double _leafLife = 27.0;
const double _fadeStart = 8.0;
const int _maxWorry = 44;

const List<String> _lines = [
  'Nothing to do here. Just be.',
  'Tap the water, if you like.',
  "There's no hurry at all.",
  '{n} is right here with you.',
  'You can stay as long as you want.',
  'Notice the quiet.',
  'Whatever you feel is allowed to be here.',
  'Watch the fireflies drift.',
];

// x, y, pad width, flower size (0 = no flower), phase   (Gentle level)
const List<List<double>> _padsRaw = [
  [300, 470, 74, 30, 0.0],
  [410, 522, 56, 0, 1.0],
  [560, 452, 66, 26, 2.2],
  [690, 506, 76, 32, 3.4],
  [235, 522, 50, 0, 4.1],
  [805, 470, 52, 0, 5.0],
];

// ---- Deeper level: Lotus Echo (tune these to make it easier or harder) ----
const List<List<double>> _echo = [
  [200, 500],
  [320, 452],
  [470, 520],
  [620, 450],
  [740, 505],
];
const List<double> _echoNotes = [523.25, 587.33, 659.25, 783.99, 880.00];
const double _hitR = 52;
const int _startLen = 3;
const int _maxLen = 7;
const double _step = 0.85;
const double _hintAfter = 10.0;
const List<String> _doneLines = ['Lovely.', 'Beautifully echoed.', 'Nicely done. No rush.'];

Color _c(int r, int g, int b, [int a = 255]) => Color.fromARGB(a, r, g, b);

bool _inPond(double x, double y, [double margin = 0.92]) =>
    math.pow((x - _pcx) / _prx, 2) + math.pow((y - _pcy) / _pry, 2) <= margin * margin;

void _ellipse(Canvas c, double x, double y, double rx, double ry, Color col) {
  c.drawOval(Rect.fromCenter(center: Offset(x, y), width: math.max(2, rx * 2), height: math.max(2, ry * 2)),
      Paint()..color = col);
}

void _drawPad(Canvas c, double x, double y0, double w, double t, double ph) {
  final y = y0 + 1.5 * math.sin(t * 0.9 + ph);
  final h = w * 0.36;
  _ellipse(c, x, y + 3, w / 2, h / 2, _c(118, 112, 170));
  _ellipse(c, x, y, w / 2, h / 2, _c(122, 190, 164));
  _ellipse(c, x - w * 0.08, y - h * 0.10, w * 0.32, h * 0.28, _c(150, 210, 180));
  c.drawLine(
      Offset(x, y),
      Offset(x + w * 0.46, y + h * 0.12),
      Paint()
        ..color = _c(96, 160, 140)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
}

Path _petalOutline(double x, double y, double dx, double dy, double len, double w) {
  final px = -dy, py = dx;
  final s1 = <Offset>[];
  final s2 = <Offset>[];
  for (var i = 0; i < 13; i++) {
    final tt = i / 12;
    final along = tt * len;
    final wd = math.sin(math.pi * tt) * w * (1 - 0.3 * tt);
    final cx = x + along * dx, cy = y + along * dy;
    s1.add(Offset(cx + wd * px, cy + wd * py));
    s2.add(Offset(cx - wd * px, cy - wd * py));
  }
  final pts = <Offset>[...s1, ...s2.reversed];
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    p.lineTo(pts[i].dx, pts[i].dy);
  }
  p.close();
  return p;
}

void _petal(Canvas c, double x, double y, double angDeg, double length, double wmax, Color col) {
  final a = angDeg * math.pi / 180;
  final dx = math.sin(a), dy = -math.cos(a);
  c.drawPath(_petalOutline(x, y, dx, dy, length, wmax), Paint()..color = col);
  final light = Color.fromARGB(col.alpha, math.min(255, col.red + 18), math.min(255, col.green + 18),
      math.min(255, col.blue + 18));
  c.drawPath(_petalOutline(x, y, dx, dy, length * 0.80, wmax * 0.5), Paint()..color = light);
}

/// o = 0 (closed bud) .. 1 (fully open). Blooms and closes very slowly.
void _drawLotus(Canvas c, double x, double y, double size, double o0) {
  final o = o0 * o0 * (3 - 2 * o0);
  final spread = 0.16 + 0.84 * o;
  final rows = <List<Object>>[
    [<double>[-64, 64], _c(238, 166, 202), 0.92],
    [<double>[-40, 40], _c(245, 186, 214), 1.00],
    [<double>[-18, 18], _c(251, 206, 226), 1.06],
    [<double>[0], _c(255, 228, 238), 1.00],
  ];
  for (final row in rows) {
    final angs = row[0] as List<double>;
    final col = row[1] as Color;
    final ls = row[2] as double;
    for (final a in angs) {
      _petal(c, x, y, a * spread, size * ls, size * 0.30 * (0.75 + 0.25 * o), col);
    }
  }
  if (o > 0.5) {
    _ellipse(c, x, y - size * 0.10, size * 0.14, size * 0.10, _c(255, 226, 150));
  }
}

void _drawRing(Canvas c, double lx, double ly, double age, double strength) {
  for (var k = 0; k < 3; k++) {
    final a = age - k * 0.5;
    if (a <= 0) continue;
    final rad = a * 52;
    final ry = rad * 0.30;
    if (ry < 3) continue;
    final al = 150 * strength * math.pow(math.max(0.0, 1 - a / 3.8), 1.5) * (1 - 0.22 * k);
    if (al <= 1) continue;
    c.drawOval(
        Rect.fromCenter(center: Offset(lx, ly), width: 2 * rad, height: 2 * ry),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _c(255, 255, 255, al.round().clamp(0, 255)));
  }
}

// ================================================================ things in the scene
class _Firefly {
  late final double ax, ay, rx, ry, s1, s2, s3, p1, p2, p3, size;
  double pullX = 0, pullY = 0;

  _Firefly(math.Random r) {
    double u(double a, double b) => a + r.nextDouble() * (b - a);
    ax = u(40, kW - 40);
    ay = u(80, 520);
    rx = u(25, 70);
    ry = u(14, 40);
    s1 = u(0.10, 0.26);
    s2 = u(0.12, 0.30);
    s3 = u(0.7, 1.6);
    p1 = u(0, 6.28);
    p2 = u(0, 6.28);
    p3 = u(0, 6.28);
    size = u(0.75, 1.2);
  }

  Offset pos(double t) => Offset(ax + rx * math.sin(t * s1 + p1), ay + ry * math.sin(t * s2 + p2));
}

class _Star {
  final double x, y, r, sp, ph;
  const _Star(this.x, this.y, this.r, this.sp, this.ph);
}

class _Ripple {
  final double x, y, t0, strength;
  _Ripple(this.x, this.y, this.t0, this.strength);
}

/// A worry written on a leaf. It only exists on screen: nothing is ever saved.
class _WorryLeaf {
  final List<String> lines;
  final double w, h;
  final double t0;
  double nextTrail;

  _WorryLeaf._(this.lines, this.w, this.h, this.t0) : nextTrail = t0 + 1.5;

  factory _WorryLeaf(String text, double t0) {
    var lines = wrapText(text, 19, true, 250);
    if (lines.length > 3) lines = lines.sublist(0, 3);
    var tw = 0.0;
    for (final l in lines) {
      tw = math.max(tw, textWidth(l, 19, bold: true));
    }
    final w = math.max(150.0, tw + 80);
    final h = 44.0 + 24 * lines.length;
    return _WorryLeaf._(lines, w, h, t0);
  }

  /// Draws the leaf centred on the origin.
  void draw(Canvas c) {
    final top = <Offset>[];
    final bot = <Offset>[];
    for (var i = 0; i < 29; i++) {
      final tt = i / 28;
      final half = (h / 2) * math.pow(math.sin(math.pi * tt), 0.7);
      final x = -w / 2 + tt * w;
      top.add(Offset(x, -half));
      bot.add(Offset(x, half));
    }
    Path poly(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].dx, pts[i].dy);
      }
      return p..close();
    }

    c.drawPath(poly([...top, ...bot.reversed]), Paint()..color = _c(150, 206, 164));
    c.drawPath(poly([...top, ...top.reversed.map((o) => Offset(o.dx, 0))]), Paint()..color = _c(168, 220, 180));
    final vein = Paint()
      ..color = _c(110, 170, 130)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(-w / 2, 0), Offset(-w / 2 + w * 0.10, 0), vein);
    c.drawLine(Offset(-w / 2 + w * 0.90, 0), Offset(w / 2, 0), vein);
    for (var i = 0; i < lines.length; i++) {
      final cy = (i - (lines.length - 1) / 2) * 24;
      drawText(c, lines[i], 19, _c(46, 86, 66), Offset(0, cy), bold: true);
    }
  }
}

Offset _leafPos(double age) =>
    Offset(250 + 24 * age, 470 + 12 * math.sin(age * 0.8) + 5 * math.sin(age * 0.33));

// ================================================================ the scene
class AnxietyScene extends StatefulWidget {
  const AnxietyScene({super.key});

  @override
  State<AnxietyScene> createState() => _AnxietySceneState();
}

class _AnxietySceneState extends State<AnxietyScene> with SceneLoop {
  final math.Random _rnd = math.Random();
  final TextEditingController _ctl = TextEditingController();

  double _t = 0;
  final List<_Ripple> _ripples = [];
  List<_WorryLeaf> _leaves = [];
  bool _typing = false;
  double _nextAuto = 2.5;
  int _level = 0;
  Offset? _mouse;

  late final List<_Star> _stars;
  late final List<_Firefly> _flies;
  late final List<List<double>> _pads;
  late final List<int> _echoOrder;

  // Lotus Echo
  int _length = _startLen;
  String _st = 'intro';
  double _stT = 0;
  int _taps = 0;
  int _showI = 0;
  double _showT = 0;
  double _lastInput = 0;
  List<double> _lit = List<double>.filled(_echo.length, 0.0);
  List<int> _seq = [];
  String _msg = '';

  @override
  void initState() {
    super.initState();
    final rng = math.Random(11);
    double u(double a, double b) => a + rng.nextDouble() * (b - a);
    const rs = [1.0, 1.0, 1.0, 2.0];
    _stars = [
      for (var i = 0; i < 40; i++)
        _Star(u(10, kW - 10), u(10, 240), rs[rng.nextInt(4)], u(0.4, 1.4), u(0, 6.28)),
    ];
    _flies = [for (var i = 0; i < 14; i++) _Firefly(rng)];
    _pads = [..._padsRaw]..sort((a, b) => a[1].compareTo(b[1]));
    _echoOrder = List<int>.generate(_echo.length, (i) => i)..sort((a, b) => _echo[a][1].compareTo(_echo[b][1]));
    _level = Levels.get('anxiety');
    _resetEcho();
    Sound.warmAmbient();
    startLoop();
  }

  @override
  void dispose() {
    Sound.stopAmbient(1200);
    if (_t >= 30) Companion.I.grow(); // staying a while counts as a day of calming practice
    stopLoop();
    _ctl.dispose();
    super.dispose();
  }

  void _toggleLevel() {
    setState(() {
      _level = Levels.toggle('anxiety');
      _resetEcho();
    });
  }

  // ---------------------------------------------------------------- Lotus Echo (Deeper level)
  void _resetEcho() {
    _length = _startLen;
    _st = 'intro';
    _stT = 0;
    _taps = 0;
    _showI = 0;
    _showT = 0;
    _lastInput = 0;
    _lit = List<double>.filled(_echo.length, 0.0);
    _seq = _newSeq();
    _msg = 'Listen to the lotuses, then echo them back. There are no wrong answers.';
  }

  List<int> _newSeq() {
    final seq = <int>[];
    for (var k = 0; k < _length; k++) {
      var n = _rnd.nextInt(_echo.length);
      while (seq.isNotEmpty && n == seq.last) {
        n = _rnd.nextInt(_echo.length);
      }
      seq.add(n);
    }
    return seq;
  }

  void _playNote(int i) {
    _lit[i] = 1.0;
    final x = _echo[i][0], y = _echo[i][1];
    Sound.plink(_echoNotes[i], pan: (x - _pcx) / _prx);
    _spawn(x, y + 12, 0.7);
  }

  void _startShow() {
    _st = 'show';
    _stT = 0;
    _showI = 0;
    _showT = 0;
    _taps = 0;
    _msg = 'Listen...';
    _playNote(_seq[0]);
  }

  void _updateEcho(double dt) {
    _lit = [for (final v in _lit) math.max(0.0, v - dt / 0.7)];
    _stT += dt;
    switch (_st) {
      case 'intro':
        if (_stT >= 3.0) _startShow();
        break;
      case 'show':
        _showT += dt;
        if (_showT >= _step) {
          _showT -= _step;
          _showI += 1;
          if (_showI < _seq.length) {
            _playNote(_seq[_showI]);
          } else {
            _st = 'turn';
            _stT = 0;
            _taps = 0;
            _msg = 'Your turn. Echo it back, in your own time.';
            _lastInput = _t;
          }
        }
        break;
      case 'turn':
        if (_t - _lastInput > _hintAfter && _taps < _seq.length) {
          final nxt = _seq[_taps];
          _lit[nxt] = math.max(_lit[nxt], 0.30 + 0.15 * math.sin(_t * 3));
        }
        break;
      case 'retry':
        if (_stT >= 1.8) _startShow();
        break;
      case 'done':
        if (_stT >= 2.6) {
          _length = math.min(_maxLen, _length + 1);
          _seq = _newSeq();
          _startShow();
        }
        break;
    }
  }

  int? _lotusAt(Offset p) {
    for (var i = 0; i < _echo.length; i++) {
      final x = _echo[i][0], y = _echo[i][1];
      if (math.sqrt(math.pow(p.dx - x, 2) + math.pow(p.dy - (y - 12), 2)) <= _hitR) return i;
    }
    return null;
  }

  void _echoTap(int i) {
    if (_st == 'turn') {
      _playNote(i);
      _lastInput = _t;
      if (i == _seq[_taps]) {
        _taps += 1;
        if (_taps == _seq.length) {
          _st = 'done';
          _stT = 0;
          _msg = _doneLines[_rnd.nextInt(_doneLines.length)];
          Sound.chime([523.25, 659.25, 783.99]);
          Companion.I.cheer(2.0);
        }
      } else {
        _st = 'retry';
        _stT = 0;
        _msg = "That's okay. Let's listen again.";
      }
    } else if (_st == 'intro' || _st == 'done') {
      _playNote(i); // free play: the lotuses still sing, nothing is judged
    }
  }

  // ---------------------------------------------------------------- worries
  void _startTyping() {
    _ctl.clear();
    setState(() => _typing = true);
  }

  void _stopTyping() {
    setState(() => _typing = false);
  }

  void _submit() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    _leaves.add(_WorryLeaf(text, _t));
    _ctl.clear();
    setState(() => _typing = false);
    Sound.chime([659.25, 783.99, 1046.50]);
    Companion.I.say("It's floating away. ${Companion.I.name} is right here with you.", 7.0);
  }

  // ---------------------------------------------------------------- water
  void _spawn(double x, double y, [double strength = 1.0]) {
    _ripples.add(_Ripple(x, y, _t, strength));
  }

  void _tapWater(double x, double y) {
    _spawn(x, y, 1.0);
    var i = ((x - _pond.left) / _pond.width * _penta.length).toInt();
    const jit = [-1, 0, 0, 1];
    i = math.max(0, math.min(_penta.length - 1, i + jit[_rnd.nextInt(4)]));
    Sound.plink(_penta[i], pan: (x - _pcx) / _prx);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_typing) return;
    final pos = e.localPosition;
    if (Companion.I.rect.contains(pos)) {
      Companion.I.pet();
      return;
    }
    if (_level == 1) {
      final i = _lotusAt(pos);
      if (i != null) {
        _echoTap(i);
      } else if (_inPond(pos.dx, pos.dy)) {
        _spawn(pos.dx, pos.dy, 0.8); // a silent ripple
      }
    } else if (_inPond(pos.dx, pos.dy)) {
      _tapWater(pos.dx, pos.dy);
    }
  }

  // ---------------------------------------------------------------- update
  @override
  void onTick(double dt) {
    _t += dt;
    Sound.ensureAmbient();

    if (_level == 1) _updateEcho(dt);

    if (_t >= _nextAuto) {
      // a quiet raindrop now and then
      _nextAuto = _t + 5 + _rnd.nextDouble() * 4;
      for (var k = 0; k < 20; k++) {
        final x = _pond.left + _rnd.nextDouble() * _pond.width;
        final y = _pond.top + _rnd.nextDouble() * _pond.height;
        if (_inPond(x, y)) {
          _spawn(x, y, 0.55);
          break;
        }
      }
    }

    for (final leaf in _leaves) {
      // small ripples trail behind a drifting leaf
      if (_t >= leaf.nextTrail) {
        leaf.nextTrail += 2.2;
        final p = _leafPos(_t - leaf.t0);
        if (_inPond(p.dx, p.dy, 1.0)) _spawn(p.dx - 30, p.dy + 6, 0.45);
      }
    }
    _leaves = _leaves.where((lf) => _t - lf.t0 < _leafLife).toList();
    _ripples.removeWhere((r) => _t - r.t0 >= 5.5);

    final m = _mouse; // fireflies are gently curious about the cursor
    for (final f in _flies) {
      final p = f.pos(_t);
      var tx = 0.0, ty = 0.0;
      if (m != null && !_typing) {
        final dx = m.dx - p.dx, dy = m.dy - p.dy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > 1 && d < 200) {
          final k = (1 - d / 200) * 0.8 * math.min(d, 70.0);
          tx = dx / d * k;
          ty = dy / d * k;
        }
      }
      final e = math.min(1.0, dt * 2.2);
      f.pullX += (tx - f.pullX) * e;
      f.pullY += (ty - f.pullY) * e;
    }
  }

  // ---------------------------------------------------------------- drawing
  String _line() {
    final comp = Companion.I;
    if (nowSeconds() < comp.sayUntil) return comp.sayText;
    if (_level == 1) return _msg;
    return _lines[(_t ~/ 13) % _lines.length].replaceAll('{n}', comp.name);
  }

  void _drawBackdrop(Canvas c) {
    drawGradientBg(c, _skyTop, _skyBottom);
    drawGlow(c, const Offset(740, 130), 130, _c(255, 240, 226), strength: 140);
    final hills = <List<Object>>[
      [450.0, 424.0, 540.0, 62.0, _c(148, 138, 196)],
      [140.0, 456.0, 340.0, 92.0, _c(124, 114, 176)],
      [790.0, 448.0, 380.0, 82.0, _c(134, 122, 184)],
    ];
    for (final h in hills) {
      _ellipse(c, h[0] as double, h[1] as double, h[2] as double, h[3] as double, h[4] as Color);
    }
    c.drawCircle(const Offset(740, 130), 26, Paint()..color = _c(255, 248, 238));

    // twinkling stars
    for (final s in _stars) {
      final b = 0.5 + 0.5 * math.sin(_t * s.sp + s.ph);
      final sky = lerpColor(_skyTop, _skyBottom, s.y / kH);
      final col = lerpColor(sky, _c(255, 250, 240), 0.25 + 0.65 * b);
      c.drawCircle(Offset(s.x, s.y), s.r, Paint()..color = col);
    }
  }

  void _drawWater(Canvas c) {
    c.save();
    c.clipPath(Path()..addOval(_pond));
    c.drawRect(
        _pond,
        Paint()
          ..shader = ui_linear(_pond.topCenter, _pond.bottomCenter, _waterTop, _waterBottom));
    drawGrain(c, _pond, amount: 0.8);
    drawSoftEllipse(c, const Offset(740, 452), 170, 60, _c(255, 240, 226), 130);
    for (final r in _ripples) {
      _drawRing(c, r.x, r.y, _t - r.t0, r.strength);
    }
    c.restore();
    // soft bright rim
    c.drawOval(
        _pond.deflate(3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _c(255, 255, 255, 110));
  }

  void _drawLotuses(Canvas c) {
    final t = _t;
    if (_level == 1) {
      for (final i in _echoOrder) {
        final x = _echo[i][0], y = _echo[i][1];
        final ph = i * 1.3;
        _drawPad(c, x, y, 76, t, ph);
        final bob = 1.5 * math.sin(t * 0.9 + ph);
        final fy = y - 76 * 0.36 * 0.10 + bob;
        final lit = _lit[i];
        if (lit > 0.02) {
          final gs = 110 + 50 * lit;
          drawGlow(c, Offset(x, fy - 12), gs / 2, _c(255, 236, 190),
              strength: 230, opacity: math.min(1.0, lit));
        }
        _drawLotus(c, x, fy, 32, 0.75 + 0.25 * math.min(1.0, lit));
      }
    } else {
      for (final p in _pads) {
        final x = p[0], y = p[1], w = p[2], fsize = p[3], ph = p[4];
        _drawPad(c, x, y, w, t, ph);
        if (fsize > 0) {
          final o = 0.5 + 0.5 * math.sin(t * 0.12 + ph);
          final bob = 1.5 * math.sin(t * 0.9 + ph);
          _drawLotus(c, x, y - w * 0.36 * 0.10 + bob, fsize, o);
        }
      }
    }
  }

  void _drawFly(Canvas c, _Firefly f) {
    final p = f.pos(_t);
    final x = p.dx + f.pullX, y = p.dy + f.pullY;
    final b = 0.5 + 0.5 * math.sin(_t * f.s3 + f.p3);
    final gs = math.max(4.0, 40 * f.size * (0.8 + 0.4 * b));
    drawGlow(c, Offset(x, y), gs / 2, _c(255, 232, 160), strength: 210, opacity: (80 + 150 * b) / 255);
    final cs = math.max(3.0, 11 * f.size);
    drawGlow(c, Offset(x, y), cs / 2, _c(255, 250, 220), strength: 255, opacity: (150 + 100 * b) / 255);
  }

  void _draw(Canvas c) {
    final t = _t;
    _drawBackdrop(c);
    _drawWater(c);
    _drawLotuses(c);

    // worry leaves drifting away
    for (final leaf in _leaves) {
      final age = t - leaf.t0;
      final p = _leafPos(age);
      final a = age < _fadeStart ? 1.0 : math.max(0.0, 1 - (age - _fadeStart) / (_leafLife - _fadeStart));
      final r = Rect.fromCenter(center: p, width: leaf.w + 40, height: leaf.h + 40);
      c.saveLayer(r, Paint()..color = _c(255, 255, 255, a8(a)));
      c.translate(p.dx, p.dy);
      c.rotate(-5 * math.sin(age * 0.6) * math.pi / 180);
      leaf.draw(c);
      c.restore();
    }

    for (final f in _flies) {
      _drawFly(c, f);
    }

    Companion.I.draw(c, const Offset(170, 312), 200, sparkles: false);
    drawBubble(c, _line(), kW / 2, 20, maxW: 560, size: 22);
    if (_level == 1 && _st != 'intro') _drawDots(c);
  }

  void _drawDots(Canvas c) {
    final n = _seq.length;
    int filled;
    if (_st == 'show') {
      filled = _showI + 1;
    } else if (_st == 'turn') {
      filled = _taps;
    } else if (_st == 'done') {
      filled = n;
    } else {
      filled = 0;
    }
    final x0 = kW / 2 - (n - 1) * 11;
    for (var k = 0; k < n; k++) {
      final col = k < filled ? _c(255, 228, 164) : _c(206, 194, 232);
      c.drawCircle(Offset(x0 + k * 22, 150), 6, Paint()..color = col);
    }
  }

  void _drawTyping(Canvas c) {
    const cx = kW / 2;
    c.drawRect(const Rect.fromLTWH(0, 0, kW, kH), Paint()..color = _c(36, 24, 70, 120));
    final panel = Rect.fromCenter(center: const Offset(cx, 300), width: 620, height: 290);
    drawGlass(c, panel, radius: 30, alpha: 235);
    drawText(c, "What's weighing on you?", 30, kText, const Offset(cx, 200), bold: true);
    drawText(c, 'Write it down, then let it float away. It is never saved.', 19, kTextDim,
        const Offset(cx, 238));
    c.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(cx - 260, 268, 520, 54), const Radius.circular(22)),
        Paint()..color = kCard);
  }

  @override
  Widget build(BuildContext context) {
    const cx = kW / 2;
    return EscScope(
      onEsc: () {
        if (_typing) {
          _stopTyping();
        } else {
          Nav.I.go('home');
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: MouseRegion(
              onHover: (e) => _mouse = e.localPosition,
              onExit: (_) => _mouse = null,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: (e) => _mouse = e.localPosition,
                child: paintLayer(_draw),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: _typing,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CalmButton(
                  rect: const Rect.fromLTWH(24, 24, 110, 40),
                  title: 'Leave',
                  color: kCalm,
                  hoverColor: kCalmHover,
                  textColor: kTextDim,
                  titleSize: 18,
                  onTap: () => Nav.I.go('home'),
                ),
                SoundButton(
                  rect: const Rect.fromLTWH(kW - 124, 24, 100, 36),
                  color: kCalm,
                  hoverColor: kCalmHover,
                  textColor: kTextDim,
                ),
                CalmButton(
                  rect: const Rect.fromLTWH(kW - 164, 70, 140, 36),
                  title: 'Level: ${Levels.name(_level)}',
                  color: kCalm,
                  hoverColor: kCalmHover,
                  textColor: kTextDim,
                  titleSize: 15,
                  onTap: _toggleLevel,
                ),
                CalmButton(
                  rect: const Rect.fromLTWH(560, 326, 300, 46),
                  title: 'Let a worry float away',
                  color: kCalm,
                  hoverColor: kCalmHover,
                  textColor: kText,
                  titleSize: 20,
                  onTap: _startTyping,
                ),
              ],
            ),
          ),
          if (_typing) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: paintLayer(_drawTyping),
              ),
            ),
            CalmTextField(
              rect: const Rect.fromLTWH(cx - 260, 268, 520, 54),
              controller: _ctl,
              hint: 'Type it here',
              maxLength: _maxWorry,
              fontSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              onSubmit: _submit,
            ),
            CalmButton(
              rect: const Rect.fromLTWH(cx - 215, 352, 200, 54),
              title: 'Let it go',
              color: kAccent,
              hoverColor: kAccentHover,
              textColor: kWhite,
              titleSize: 24,
              onTap: _submit,
            ),
            CalmButton(
              rect: const Rect.fromLTWH(cx + 15, 352, 200, 54),
              title: 'Never mind',
              color: kCard,
              hoverColor: kCardHover,
              textColor: kTextDim,
              titleSize: 22,
              onTap: _stopTyping,
            ),
          ],
        ],
      ),
    );
  }
}

Shader ui_linear(Offset a, Offset b, Color c1, Color c2) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [c1, c2],
    ).createShader(Rect.fromPoints(a, b));
