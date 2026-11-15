// Stress mode: untangle the threads by dragging the beads (scenes/stress.py).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/levels.dart';
import '../core/palette.dart';
import '../core/scene_art.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const Rect _playLand = Rect.fromLTWH(210, 112, 650, 410); // the board
const double _margin = 34; // keeps puzzle beads away from the edge

// ---- difficulty: tune these to make each level easier or harder ----
class _Cfg {
  final int n0, nmax;
  final double extra;
  const _Cfg(this.n0, this.nmax, this.extra);
}

const List<_Cfg> _levels = [
  _Cfg(7, 11, 0.30), // Gentle: beads at the start / at most, extra threads
  _Cfg(10, 15, 0.80), // Deeper
];
const double _grabR = 32; // how close a click must be to pick up a bead
const double _hintSeconds = 4.0;
const double _introSeconds = 14.0;

// the yarn balls (assets/scenes/yarn_ball_0..4.png): pale blue, lilac, peach, pink, mint
const double _ballAspect = 168 / 156; // width / height of the ball pictures
const List<Color> _beadColors = [
  Color(0xFFF6AA8C), Color(0xFFB096E0), Color(0xFF8CCEB8), Color(0xFFF4AAC6), Color(0xFF96C4F2),
];
const List<double> _notes = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50]; // one gentle scale
const Color _calmThread = Color(0xFFBDE0F5); // pale blue wool, like the picture
const Color _warmThread = Color(0xFFF59C86);
const Color _solvedThread = Color(0xFFFFE2A0);
const List<Color> _sparkCols = [
  Color(0xFFFFE296), Color(0xFFFFFFFF), Color(0xFFCEBCFF), Color(0xFFFFD6E8), Color(0xFFBAE8FF),
];

const List<String> _intro = [
  'Drag the beads until the warm threads turn calm. No timer, no rush.',
  'Drag the beads until no thread crosses another. A hint is always there.',
];
const List<String> _lines = [
  'One bead at a time.',
  "There's no timer. Take all the time you like.",
  'Let your hands do the thinking.',
  'Slow is perfectly fine here.',
  '{n} is cheering you on, quietly.',
  'Stuck? You can always ask for a hint.',
  'Or try a new tangle. That\'s allowed too.',
];
const List<String> _solvedLines = [
  'Beautifully untangled.',
  'Look at that. All calm.',
  'Nicely done. Nothing left to untangle.',
];

// ================================================================ geometry
double _ccw(List<double> a, List<double> b, List<double> c) =>
    (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0]);

bool _segCross(List<double> a, List<double> b, List<double> c, List<double> d) {
  final d1 = _ccw(a, b, c), d2 = _ccw(a, b, d);
  final d3 = _ccw(c, d, a), d4 = _ccw(c, d, b);
  return d1 * d2 < 0 && d3 * d4 < 0;
}

double _segDist(List<double> p, List<double> a, List<double> b) {
  final dx = b[0] - a[0], dy = b[1] - a[1];
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return math.sqrt(math.pow(p[0] - a[0], 2) + math.pow(p[1] - a[1], 2));
  final t = clampD(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2, 0, 1);
  final qx = p[0] - (a[0] + t * dx), qy = p[1] - (a[1] + t * dy);
  return math.sqrt(qx * qx + qy * qy);
}

double _dist(List<double> a, List<double> b) {
  final dx = a[0] - b[0], dy = a[1] - b[1];
  return math.sqrt(dx * dx + dy * dy);
}

/// The set of edge numbers that cross another edge.
Set<int> _findCrossings(List<List<double>> pos, List<List<int>> edges) {
  final bad = <int>{};
  for (var i = 0; i < edges.length; i++) {
    final a = edges[i][0], b = edges[i][1];
    for (var j = i + 1; j < edges.length; j++) {
      final c = edges[j][0], d = edges[j][1];
      if (a == c || a == d || b == c || b == d) continue;
      if (_segCross(pos[a], pos[b], pos[c], pos[d])) {
        bad.add(i);
        bad.add(j);
      }
    }
  }
  return bad;
}

class _Pair {
  final double d;
  final int i, j;
  _Pair(this.d, this.i, this.j);
}

class _Puzzle {
  final List<List<double>> pos; // relative to the board's inner corner
  final List<List<int>> edges;
  _Puzzle(this.pos, this.edges);
}

/// Builds a planar graph (so a solution always exists), then scrambles the beads.
_Puzzle _makePuzzle(int n, double extraFrac, math.Random rng, Rect play) {
  final w = play.width - 2 * _margin, h = play.height - 2 * _margin;
  var mind = 0.62 * math.sqrt(w * h / n);
  final pts = <List<double>>[];
  var tries = 0;
  while (pts.length < n) {
    tries++;
    if (tries % 400 == 0) mind *= 0.9;
    final p = <double>[rng.nextDouble() * w, rng.nextDouble() * h];
    if (pts.every((q) => _dist(p, q) >= mind)) pts.add(p);
  }

  // greedy planar graph: shortest threads first, skipping any that would cross
  final pairs = <_Pair>[];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      pairs.add(_Pair(_dist(pts[i], pts[j]), i, j));
    }
  }
  pairs.sort((x, y) {
    final c = x.d.compareTo(y.d);
    if (c != 0) return c;
    final ci = x.i.compareTo(y.i);
    return ci != 0 ? ci : x.j.compareTo(y.j);
  });
  final planar = <List<int>>[];
  for (final pr in pairs) {
    final i = pr.i, j = pr.j;
    final a = pts[i], b = pts[j];
    var blocked = false;
    for (var k = 0; k < n; k++) {
      if (k != i && k != j && _segDist(pts[k], a, b) < 24) {
        blocked = true;
        break;
      }
    }
    if (blocked) continue;
    for (final e in planar) {
      final c = e[0], d = e[1];
      if (i == c || i == d || j == c || j == d) continue;
      if (_segCross(a, b, pts[c], pts[d])) {
        blocked = true;
        break;
      }
    }
    if (blocked) continue;
    planar.add([i, j]);
  }

  // keep everything connected (a spanning tree), then add a few extra threads
  final order = List<List<int>>.from(planar)..shuffle(rng);
  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  final tree = <List<int>>[], rest = <List<int>>[];
  for (final e in order) {
    final ra = find(e[0]), rb = find(e[1]);
    if (ra != rb) {
      parent[ra] = rb;
      tree.add(e);
    } else {
      rest.add(e);
    }
  }
  final edges = <List<int>>[...tree, ...rest.take(math.min(rest.length, (extraFrac * n).round()))];

  // scramble: shuffle which bead sits at which spot
  final want = math.max(3, (0.55 * edges.length).toInt());
  List<List<double>>? best;
  var bestC = -1;
  for (var it = 0; it < 150; it++) {
    final perm = List<int>.generate(n, (i) => i)..shuffle(rng);
    final pos = <List<double>>[for (var i = 0; i < n; i++) List<double>.from(pts[perm[i]])];
    final c = _findCrossings(pos, edges).length;
    if (c > bestC) {
      best = pos;
      bestC = c;
    }
    if (c >= want) break;
  }
  return _Puzzle(best!, edges);
}

// ================================================================ drawing helpers
/// One ball of yarn centred on [c], [size] pixels wide (the picture for colour [k]).
void _drawBead(Canvas canvas, Offset c, int k, double size) {
  if (size < 1) return;
  final img = SceneArt.get('yarn_ball_${k % _beadColors.length}.png');
  if (img == null) {
    canvas.drawCircle(c, size * 0.45, Paint()..color = _beadColors[k % _beadColors.length]); // until the picture loads
    return;
  }
  final h = size / _ballAspect;
  drawArt(canvas, img, Rect.fromCenter(center: c, width: size, height: h), q: FilterQuality.high);
}

/// A strand of soft wool lying on the felt, like the loose thread in the picture: it wanders in gentle S-curves
/// between the two balls (never a ruled line), is slightly fuzzy, and has a soft shadow on the felt.
void _drawThread(Canvas canvas, Offset a, Offset b, Color col, double t, int idx, {bool glow = false}) {
  final len = (b - a).distance;
  if (len < 1) return;
  final rnd = math.Random(idx * 131 + 17);
  final dir = (b - a) / len;
  final nm = Offset(-dir.dy, dir.dx);
  final waves = math.max(1.0, (len / 95).roundToDouble());
  final amp = math.min(2.0, len * 0.11) * (0.75 + 0.5 * rnd.nextDouble()) * (1 + 0.04 * math.sin(t * 0.8 + idx));
  final ph = rnd.nextDouble() * 6.283, ph2 = rnd.nextDouble() * 6.283;
  final n = math.max(12, (len / 3).ceil());
  Offset at(double u) {
    final env = math.pow(math.max(0.0, math.sin(math.pi * u)), 0.7).toDouble(); // both ends come to rest exactly at the balls
    final off = amp * math.sin(u * math.pi * waves + ph) * env + amp * 0.28 * math.sin(u * math.pi * waves * 2.3 + ph2) * env;
    return a + dir * (len * u) + nm * off;
  }

  final pts = <Offset>[for (var i = 0; i <= n; i++) at(i / n)];
  Path trace(Offset off) {
    final p = Path()..moveTo(pts.first.dx + off.dx, pts.first.dy + off.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx + off.dx, q.dy + off.dy);
    }
    return p;
  }

  Offset tang(int i) {
    final d = pts[math.min(n, i + 1)] - pts[math.max(0, i - 1)];
    final l = d.distance;
    return l == 0 ? const Offset(1, 0) : d / l;
  }

  Paint stroke(Color c, double w) {
    final p = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    return p;
  }

  const w = 4.2; // wool thickness
  if (glow) {
    canvas.drawPath(trace(Offset.zero), stroke(col.withAlpha(35), 16));
    canvas.drawPath(trace(Offset.zero), stroke(col.withAlpha(55), 10));
  }
  // soft shadow on the felt, built from a few translucent strokes
  canvas.drawPath(trace(const Offset(1.5, 3.5)), stroke(const Color(0x1810264A), 9));
  canvas.drawPath(trace(const Offset(1.5, 3.5)), stroke(const Color(0x2810264A), 6));
  canvas.drawPath(trace(const Offset(1.2, 2.8)), stroke(const Color(0x3010264A), 4));
  canvas.drawPath(trace(Offset.zero), stroke(col.withAlpha(50), w + 3.0)); // fuzzy halo
  final under = lerpColor(col, const Color(0xFF3A6AA8), 0.45);
  final light = lerpColor(col, Colors.white, 0.55);
  canvas.drawPath(trace(const Offset(0.5, 0.9)), stroke(under, w)); // the shaded underside
  canvas.drawPath(trace(Offset.zero), stroke(col, w - 0.9));

  // soft twist: short slanted strokes, low contrast so it reads as wool and not as a rope
  final lightRidge = <double>[], darkRidge = <double>[];
  var dist = 0.0;
  for (var i = 1; i < n; i++) {
    dist += (pts[i] - pts[i - 1]).distance;
    final pitch = 3.0 + rnd.nextDouble() * 1.4;
    if (dist < pitch) continue;
    dist = 0;
    final tg = tang(i), nn = Offset(-tg.dy, tg.dx);
    final u = i / n;
    final h = (w - 0.8) / 2 * math.min(1.0, math.min(u * len, (1 - u) * len) / 12);
    final sl = tg * 1.8, p = pts[i];
    lightRidge.addAll([p.dx - nn.dx * h - sl.dx, p.dy - nn.dy * h - sl.dy, p.dx + nn.dx * h + sl.dx, p.dy + nn.dy * h + sl.dy]);
    final p2 = p + tg * (pitch * 0.5);
    darkRidge.addAll([p2.dx - nn.dx * h - sl.dx, p2.dy - nn.dy * h - sl.dy, p2.dx + nn.dx * h + sl.dx, p2.dy + nn.dy * h + sl.dy]);
  }
  if (darkRidge.isNotEmpty) canvas.drawRawPoints(ui.PointMode.lines, Float32List.fromList(darkRidge), stroke(under.withAlpha(110), 0.9));
  if (lightRidge.isNotEmpty) canvas.drawRawPoints(ui.PointMode.lines, Float32List.fromList(lightRidge), stroke(light.withAlpha(120), 0.9));
  canvas.drawPath(trace(const Offset(-0.6, -0.9)), stroke(light.withAlpha(60), 1.0));

  // fuzz: tiny wisps standing off the wool (one batched draw)
  final wisps = <double>[];
  for (var k = 0; k < (len / 5).floor(); k++) {
    final i = 2 + rnd.nextInt(n - 3);
    final tg = tang(i), nn = Offset(-tg.dy, tg.dx), p = pts[i];
    final side = rnd.nextBool() ? 1.0 : -1.0;
    final l = 1.8 + rnd.nextDouble() * 3.6;
    final q = p + nn * (side * 1.4), tip = p + nn * (side * l) + tg * (rnd.nextDouble() * 4 - 2);
    wisps.addAll([q.dx, q.dy, tip.dx, tip.dy]);
  }
  if (wisps.isNotEmpty) canvas.drawRawPoints(ui.PointMode.lines, Float32List.fromList(wisps), stroke(light.withAlpha(110), 0.6));
}

class _Spark {
  double x, y, vx, vy;
  final double t0;
  final Color col;
  _Spark(this.x, this.y, this.vx, this.vy, this.t0, this.col);
}

// ================================================================ the scene
class StressScene extends StatefulWidget {
  const StressScene({super.key});

  @override
  State<StressScene> createState() => _StressSceneState();
}

class _StressSceneState extends State<StressScene> with SceneLoop {
  final math.Random _rng = math.Random();
  double _t = 0;
  int _level = 0;
  int _round = 0;
  List<_Spark> _sparks = <_Spark>[];

  List<List<double>> _pos = <List<double>>[];
  List<List<int>> _edges = <List<int>>[];
  List<int> _cols = <int>[];
  Set<int> _bad = <int>{};
  bool _solved = false;
  int? _drag;
  Offset _dragOff = Offset.zero;
  Offset _mouse = Offset.zero;
  double _hintUntil = 0;
  double _spawnT = 0;
  String _solvedMsg = '';

  // the board: wide on a landscape screen, a tall panel between the speech bubble and the buttons on a phone
  Rect get _play => Layout.portrait ? Rect.fromLTWH(40, 240, 520, Layout.h - 240 - 250) : _playLand;

  @override
  void initState() {
    super.initState();
    Sound.warmAmbient();
    _level = Levels.get('stress');
    _newPuzzle();
    startLoop();
  }

  @override
  void dispose() {
    Sound.stopAmbient(1200);
    if (_t >= 30) Companion.I.grow(); // staying a while counts as a day of calming practice
    stopLoop();
    super.dispose();
  }

  // ---------------------------------------------------------------- state
  void _toggleLevel() {
    setState(() {
      _level = Levels.toggle('stress');
      _round = 0;
      _newPuzzle();
    });
  }

  void _newPuzzle() {
    final cfg = _levels[_level];
    final n = math.min(cfg.nmax, cfg.n0 + _round);
    final pz = _makePuzzle(n, cfg.extra, _rng, _play);
    _edges = pz.edges;
    final ox = _play.left + _margin, oy = _play.top + _margin;
    _pos = [for (final p in pz.pos) <double>[ox + p[0], oy + p[1]]];
    _cols = [for (var i = 0; i < n; i++) _rng.nextInt(_beadColors.length)];
    _bad = _findCrossings(_pos, _edges);
    _solved = false;
    _drag = null;
    _dragOff = Offset.zero;
    _hintUntil = 0;
    _spawnT = _t;
    _solvedMsg = '';
  }

  void _giveHint() {
    if (_solved || _bad.isEmpty) return;
    _hintUntil = _t + _hintSeconds;
    Companion.I.say('The glowing bead is the most tangled. Try moving it somewhere new.', 5.0);
  }

  void _onSolved() {
    setState(() {
      _solved = true;
      _round += 1;
      _solvedMsg = _solvedLines[_rng.nextInt(_solvedLines.length)];
    });
    Sound.chime([523.25, 659.25, 783.99, 1046.50]);
    final comp = Companion.I;
    comp.cheer(2.5);
    comp.say(_solvedMsg, 6.0);
    final c = _play.center;
    for (var i = 0; i < 16; i++) {
      final a = _rng.nextDouble() * 6.28;
      final sp = 60 + _rng.nextDouble() * 130;
      _sparks.add(_Spark(c.dx, c.dy, math.cos(a) * sp, math.sin(a) * sp - 30, _t,
          _sparkCols[_rng.nextInt(_sparkCols.length)]));
    }
  }

  // ---------------------------------------------------------------- pointer
  void _down(PointerDownEvent e) {
    final p = e.localPosition;
    _mouse = p;
    if (Companion.I.rect.contains(p)) {
      Companion.I.pet();
      return;
    }
    int? best;
    var bd = _grabR;
    for (var i = 0; i < _pos.length; i++) {
      final dx = p.dx - _pos[i][0], dy = p.dy - _pos[i][1];
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= bd) {
        best = i;
        bd = d;
      }
    }
    if (best != null) {
      final q = _pos[best];
      _drag = best;
      _dragOff = Offset(q[0] - p.dx, q[1] - p.dy);
      Sound.plink(_notes[best % _notes.length], pan: (q[0] - _play.center.dx) / (_play.width / 2), vol: 0.6);
    }
  }

  void _move(PointerMoveEvent e) {
    _mouse = e.localPosition;
  }

  void _up(PointerEvent e) {
    if (_drag != null) {
      _drag = null;
      if (!_solved && _findCrossings(_pos, _edges).isEmpty) _onSolved();
    }
  }

  // ---------------------------------------------------------------- update
  @override
  void onTick(double dt) {
    _t += dt;
    Sound.ensureAmbient();

    final d = _drag;
    if (d != null) {
      final tx = clampD(_mouse.dx + _dragOff.dx, _play.left + 18, _play.right - 18);
      final ty = clampD(_mouse.dy + _dragOff.dy, _play.top + 18, _play.bottom - 18);
      final k = 1 - math.exp(-dt * 30);
      final p = _pos[d];
      p[0] += (tx - p[0]) * k;
      p[1] += (ty - p[1]) * k;
    }

    _bad = _findCrossings(_pos, _edges);

    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 40 * dt;
    }
    _sparks = _sparks.where((s) => _t - s.t0 < 2.4).toList();
  }

  // ---------------------------------------------------------------- drawing
  String _line() {
    final comp = Companion.I;
    if (nowSeconds() < comp.sayUntil) return comp.sayText;
    if (_solved) return _solvedMsg;
    if (_t < _introSeconds) return _intro[_level];
    final idx = ((_t - _introSeconds) ~/ 14) % _lines.length;
    return _lines[idx].replaceAll('{n}', comp.name);
  }

  int _tangledBead() {
    final counts = List<int>.filled(_pos.length, 0);
    for (final e in _bad) {
      counts[_edges[e][0]]++;
      counts[_edges[e][1]]++;
    }
    var best = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    return best;
  }

  void _draw(Canvas c) {
    final t = _t;
    final felt = SceneArt.get('yarn_bg.jpg');
    if (felt == null) {
      drawAmbientBg(c, w: Layout.w, h: Layout.h);
    } else {
      // blue felt, filling the screen
      final sc = math.max(Layout.w / felt.width, Layout.h / felt.height);
      final fw = felt.width * sc, fh = felt.height * sc;
      drawArt(c, felt, Rect.fromLTWH((Layout.w - fw) / 2, (Layout.h - fh) / 2, fw, fh), q: FilterQuality.high);
    }

    final hinting = t < _hintUntil;
    final showCross = (_level == 0 || hinting) && !_solved;

    Color colour(int idx) {
      if (_solved) return _solvedThread;
      if (_bad.contains(idx) && showCross) return _warmThread;
      return _calmThread;
    }

    // threads: calm ones first, tangled (warm) ones on top
    for (final warm in <bool>[false, true]) {
      for (var idx = 0; idx < _edges.length; idx++) {
        final col = colour(idx);
        if ((col == _warmThread) == warm) {
          final a = _pos[_edges[idx][0]], b = _pos[_edges[idx][1]];
          _drawThread(c, Offset(a[0], a[1]), Offset(b[0], b[1]), col, t, idx, glow: warm || _solved);
        }
      }
    }
    // beads (the one being dragged is drawn last, on top)
    final order = <int>[
      for (var i = 0; i < _pos.length; i++)
        if (i != _drag) i,
      if (_drag != null) _drag!,
    ];
    for (final i in order) {
      final x = _pos[i][0], y = _pos[i][1];
      final pop = smooth((t - _spawnT - i * 0.04) / 0.45);
      if (pop <= 0) continue;
      final lifted = i == _drag;
      drawGlow(c, Offset(x + 3, y + (lifted ? 12 : 7)), 36, const Color(0xFF10264A),
          strength: 110, opacity: (lifted ? 150 : 100) / 255);
      if (_solved) {
        final gs = 64 + 8 * math.sin(t * 2 + i);
        drawGlow(c, Offset(x, y), gs / 2, const Color(0xFFFFE296),
            strength: 210, opacity: (160 + 60 * math.sin(t * 2 + i)) / 255);
      }
      final size = (lifted ? 68.0 : 56.0) * pop;
      _drawBead(c, Offset(x, y - (lifted ? 4 : 0)), _cols[i], size);
    }

    // hint: the most tangled bead pulses
    if (hinting && _bad.isNotEmpty) {
      final p = _pos[_tangledBead()];
      final gs = 96 + 14 * math.sin(t * 5);
      drawGlow(c, Offset(p[0], p[1]), gs / 2, const Color(0xFFFFECBE), strength: 240, opacity: 210 / 255);
    }

    // sparkles after solving
    for (final s in _sparks) {
      final age = t - s.t0;
      final sn = math.sin(age * 4);
      drawSparkle(c, s.x, s.y, 14 + 12 * sn * sn, s.col, 255 * (1 - age / 2.4));
    }

    // companion and speech
    Companion.I.draw(c, Layout.portrait ? Offset(95, Layout.h - 150) : const Offset(100, 440),
        Layout.portrait ? 150 : 170, sparkles: false);
    drawBubble(c, _line(), Layout.w / 2, Layout.portrait ? 108 : 20, maxW: Layout.portrait ? 520 : 560, size: 22);
  }

  @override
  Widget build(BuildContext context) {
    final port = Layout.portrait;
    return EscScope(
      onEsc: () => Nav.I.go('home'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: paintLayer(_draw),
            ),
          ),
          CalmButton(
            rect: port ? const Rect.fromLTWH(24, 50, 110, 40) : const Rect.fromLTWH(24, 24, 110, 40),
            title: 'Leave',
            color: kCalm,
            hoverColor: kCalmHover,
            textColor: kTextDim,
            titleSize: 18,
            onTap: () => Nav.I.go('home'),
          ),
          SoundButton(
            rect: port ? Rect.fromLTWH(Layout.w - 124, 50, 100, 36) : const Rect.fromLTWH(kW - 124, 24, 100, 36),
            color: kCalm,
            hoverColor: kCalmHover,
            textColor: kTextDim,
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(Layout.w / 2 - 70, 50, 140, 36) : const Rect.fromLTWH(kW - 164, 70, 140, 36),
            title: 'Level: ${Levels.name(_level)}',
            color: kCalm,
            hoverColor: kCalmHover,
            textColor: kTextDim,
            titleSize: 15,
            onTap: _toggleLevel,
          ),
          if (!_solved)
            CalmButton(
              rect: port ? Rect.fromLTWH(190, Layout.h - 116, 130, 52) : const Rect.fromLTWH(367, 548, 130, 40),
              title: 'Hint',
              color: kCalm,
              hoverColor: kCalmHover,
              textColor: kText,
              titleSize: 20,
              onTap: _giveHint,
            ),
          CalmButton(
            rect: port ? Rect.fromLTWH(336, Layout.h - 116, 224, 52) : const Rect.fromLTWH(513, 548, 190, 40),
            title: _solved ? 'Another one' : 'New tangle',
            color: _solved ? kAccent : kCalm,
            hoverColor: _solved ? kAccentHover : kCalmHover,
            textColor: _solved ? kWhite : kText,
            titleSize: 20,
            onTap: () => setState(_newPuzzle),
          ),
        ],
      ),
    );
  }
}