// Stress mode: untangle the threads by dragging the beads (scenes/stress.py).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/levels.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const Rect _play = Rect.fromLTWH(210, 112, 650, 410); // the board
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
const double _grabR = 26; // how close a click must be to pick up a bead
const double _hintSeconds = 4.0;
const double _introSeconds = 14.0;

const List<Color> _beadColors = [
  Color(0xFFF6AA8C), Color(0xFFB096E0), Color(0xFF8CCEB8), Color(0xFFF4AAC6), Color(0xFF96C4F2),
];
const List<double> _notes = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50]; // one gentle scale
const Color _calmThread = Color(0xFFA08AD6);
const Color _warmThread = Color(0xFFF49674);
const Color _solvedThread = Color(0xFFF0BE78);
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
_Puzzle _makePuzzle(int n, double extraFrac, math.Random rng) {
  final w = _play.width - 2 * _margin, h = _play.height - 2 * _margin;
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
/// One shiny bead centred on [c], [size] pixels wide (make_bead in Python, drawn as vectors).
void _drawBead(Canvas canvas, Offset c, Color col, double size) {
  if (size < 1) return;
  const s = 128.0;
  const r = s * 0.44;
  final shade = Color.fromARGB(255, (col.red * 0.76).toInt(), (col.green * 0.76).toInt(), (col.blue * 0.76).toInt());
  final light = Color.fromARGB(255, math.min(255, col.red + 52), math.min(255, col.green + 52), math.min(255, col.blue + 52));
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.scale(size / s);
  canvas.drawCircle(const Offset(0, 3), r, Paint()..color = shade);
  const steps = 12;
  for (var k = 0; k <= steps; k++) {
    final f = k / steps;
    final rr = math.max(2.0, r * (1 - 0.72 * f));
    final off = -r * 0.30 * f;
    canvas.drawCircle(Offset(off, off), rr, Paint()..color = lerpColor(col, light, f));
  }
  canvas.drawCircle(const Offset(-r / 3, -r / 3), math.max(2.0, r / 7), Paint()..color = Colors.white);
  canvas.restore();
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
    final pz = _makePuzzle(n, cfg.extra, _rng);
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
    drawAmbientBg(c);
    drawGlass(c, _play.inflate(12), radius: 34, alpha: 120);

    final hinting = t < _hintUntil;
    final showCross = (_level == 0 || hinting) && !_solved;

    Color colour(int idx) {
      if (_solved) return _solvedThread;
      if (_bad.contains(idx) && showCross) return _warmThread;
      return _calmThread;
    }

    Paint line(double w, Color col, [int alpha = 255]) => Paint()
      ..color = col.withAlpha(alpha)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // soft halos under the threads, then the threads (warm ones on top)
    for (var idx = 0; idx < _edges.length; idx++) {
      final a = _pos[_edges[idx][0]], b = _pos[_edges[idx][1]];
      c.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), line(13, colour(idx), 55));
    }
    for (final warm in <bool>[false, true]) {
      for (var idx = 0; idx < _edges.length; idx++) {
        final col = colour(idx);
        if ((col == _warmThread) == warm) {
          final a = _pos[_edges[idx][0]], b = _pos[_edges[idx][1]];
          c.drawLine(Offset(a[0], a[1]), Offset(b[0], b[1]), line(5, col));
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
      drawGlow(c, Offset(x + 3, y + (lifted ? 10 : 6)), 30, const Color(0xFF4A2E52),
          strength: 110, opacity: (lifted ? 150 : 100) / 255);
      if (_solved) {
        final gs = 64 + 8 * math.sin(t * 2 + i);
        drawGlow(c, Offset(x, y), gs / 2, const Color(0xFFFFE296),
            strength: 210, opacity: (160 + 60 * math.sin(t * 2 + i)) / 255);
      }
      final size = (lifted ? 52.0 : 40.0) * pop;
      _drawBead(c, Offset(x, y - (lifted ? 4 : 0)), _beadColors[_cols[i]], size);
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
    Companion.I.draw(c, const Offset(100, 440), 170, sparkles: false);
    drawBubble(c, _line(), kW / 2, 20, maxW: 560, size: 22);
  }

  @override
  Widget build(BuildContext context) {
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
          if (!_solved)
            CalmButton(
              rect: const Rect.fromLTWH(367, 548, 130, 40),
              title: 'Hint',
              color: kCalm,
              hoverColor: kCalmHover,
              textColor: kText,
              titleSize: 20,
              onTap: _giveHint,
            ),
          CalmButton(
            rect: const Rect.fromLTWH(513, 548, 190, 40),
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
