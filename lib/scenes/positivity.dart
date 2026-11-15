// "Something good": a gratitude tree that grows (sprout to full tree) and bears a fruit of thought for every good thing you add
// (scenes/positivity.py). Saved only on this device.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/levels.dart';
import '../core/palette.dart';
import '../core/scene_art.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const String _storeKey = 'tree';
const int _maxSaved = 400; // oldest entries are dropped after this many
const int _slots = 60; // fruits shown on the tree at once
const int _growFullAt = 30; // entries until the tree is fully grown
const int _dailyGoal = 3; // "three good things" (a soft goal, never enforced)
const List<int> _maxLen = [60, 140]; // longest note: Gentle (own words), Deeper
// ---- artwork (assets/scenes): the landscape picture and the four growth stages of the tree ----
const double _soilFadeFrom = 0.60; // how far down each tree picture the painted soil starts to fade (0..1); raise it to fade less
const String _bgFile = 'positivity_bg.jpg';
const double _bgW = 736, _bgH = 1104; // size of the landscape picture
const double _rootX = 370, _rootY = 740; // where the tree stands on the picture (on the grassy mound)
const List<String> _treeFiles = ['tree_0.png', 'tree_1.png', 'tree_2.png', 'tree_3.png'];
const List<double> _treeAspect = [0.596, 0.699, 0.658, 0.827]; // width / height of each picture
const List<double> _treeSize = [0.30, 0.50, 0.70, 1.0]; // height of each stage, as a share of the full tree
// where the leaves are, per stage, as shares of the picture: centre x, centre y, radius x, radius y
const List<List<double>> _canopyFrac = [
  [0.49, 0.30, 0.43, 0.18], [0.50, 0.32, 0.44, 0.22], [0.50, 0.35, 0.44, 0.26], [0.50, 0.39, 0.44, 0.29],
];

// landscape: show the middle of the picture; portrait: fill the tall stage, anchored at the bottom
({double s, double ox, double oy}) get _bg {
  final w = Layout.w, h = Layout.h;
  if (Layout.portrait) {
    final s = math.max(w / _bgW, h / _bgH);
    return (s: s, ox: (w - _bgW * s) / 2, oy: h - _bgH * s);
  }
  final s = w / _bgW;
  return (s: s, ox: 0.0, oy: 470 - _rootY * s); // the tree's roots sit at y = 470 on the landscape stage
}

double get _gx => _bg.ox + _rootX * _bg.s;
double get _gy => _bg.oy + _rootY * _bg.s; // where the tree stands
double get _finalH => math.min(_gy - 130, Layout.portrait ? 540.0 : 390.0); // height of the full-grown tree

const Color _gold = Color(0xFFFFCE64);
const List<Color> _fruits = [Color(0xFF8CCB3C), Color(0xFF7DC038), Color(0xFF9AD148)]; // limes: slightly different greens
const List<Color> _blossoms = [
  Color(0xFFF6A8C6), Color(0xFFFFCE96), Color(0xFFBEAAF0),
  Color(0xFFA0D0F8), Color(0xFFFFBAA0), Color(0xFFAADEC8),
];

const List<String> _chips = [
  'A kind word', 'Warm food or drink', 'Fresh air',
  'A bit of rest', 'Music I liked', 'I got through today',
  'A friendly smile', 'A quiet moment', 'A good laugh',
];

const List<String> _prompts = [
  "What is one thing that's within your control today?",
  'What did you handle better than you expected?',
  'Who made your day a little easier, and how?',
  "What's a worry on your mind? Write one other way it could turn out.",
  'What would you say to a friend in your situation?',
  "What are you quietly proud of this week?",
  'What is one small thing you can look forward to?',
  'What did you learn about yourself recently?',
  'What is okay just as it is, right now?',
  "Name something ordinary that you're glad exists.",
];

const List<String> _linesGentle = [
  'Small good things count. Every one of them.',
  "What's one little thing that went okay today?",
  'Your tree bears one thought at a time.',
  '{n} is happy to sit under this tree with you.',
  'Tap a fruit to remember it.',
  "Good things don't have to be big.",
  'You can come back any day. The tree will wait.',
];
const List<String> _linesDeeper = [
  'A little reflection, then a golden fruit.',
  "Noticing is a skill. You're practising it.",
  'Take your time with it.',
  '{n} is happy to sit under this tree with you.',
  'Tap a fruit to read it again.',
  'You can come back any day. The tree will wait.',
];
const List<String> _addedLines = [
  "That's a lovely one.",
  '{n} loved reading that.',
  'A new fruit on the tree. Look at it glow.',
  'Thank you for noticing that.',
];

const Color _calmC = Color(0xFFE2D8F4);
const Color _calmHoverC = Color(0xFFF0E6FC);

class _Entry {
  int n;
  String date;
  String text;
  String kind; // chip, own, deep
  String prompt;
  _Entry(this.n, this.date, this.text, this.kind, this.prompt);

  Map<String, dynamic> toJson() => {'n': n, 'date': date, 'text': text, 'kind': kind, 'prompt': prompt};
}

class _Petal {
  final double x0, y0, t0, sz, ph;
  final Color col;
  _Petal(this.x0, this.y0, this.t0, this.col, this.sz, this.ph);
}

class _Hit {
  final _Entry e;
  final double x, y, size;
  _Hit(this.e, this.x, this.y, this.size);
}

List<_Entry> _loadEntries() {
  try {
    final data = Store.getMap(_storeKey);
    final raw = data?['entries'];
    if (raw is! List) return [];
    final out = <_Entry>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final text = e['text'];
      if (text is! String || text.trim().isEmpty) continue;
      final n = e['n'];
      final kind = e['kind'];
      final prompt = (e['prompt'] ?? '').toString();
      out.add(_Entry(
        (n is int && n >= 0) ? n : out.length,
        (e['date'] ?? '').toString(),
        text.length > 140 ? text.substring(0, 140) : text,
        (kind == 'chip' || kind == 'own' || kind == 'deep') ? kind as String : 'own',
        prompt.length > 140 ? prompt.substring(0, 140) : prompt,
      ));
    }
    return out.length > _maxSaved ? out.sublist(out.length - _maxSaved) : out;
  } catch (_) {
    return [];
  }
}

void _saveEntries(List<_Entry> entries) {
  try {
    final list = entries.length > _maxSaved ? entries.sublist(entries.length - _maxSaved) : entries;
    Store.setMap(_storeKey, {'entries': [for (final e in list) e.toJson()]});
  } catch (_) {}
}

Offset _slotPos(int k, double cx, double cy, double rx, double ry) {
  final r = math.sqrt((k + 6) / (_slots + 6));
  final a = k * 2.399963;
  return Offset(cx + math.cos(a) * rx * 0.80 * r, cy + math.sin(a) * ry * 0.78 * r);
}

void _ellipse(Canvas c, double x, double y, double rx, double ry, Color col) {
  c.drawOval(
    Rect.fromCenter(center: Offset(x, y), width: 2 * math.max(1.0, rx), height: 2 * math.max(1.0, ry)),
    Paint()..color = col,
  );
}

void _circle(Canvas c, double x, double y, double r, Color col) {
  c.drawCircle(Offset(x, y), math.max(1.0, r), Paint()..color = col);
}

double _mix(double a, double b, double t) => a + (b - a) * t;

/// One lime (centred on x, y; [size] is its radius): glossy green skin, little nub, soft highlight.
void _drawFruit(Canvas c, double x, double y, double size, Color col, bool ripe) {
  if (size < 1.5) return;
  final body = ripe ? lerpColor(col, const Color(0xFFE6E060), 0.35) : col;
  // a tiny leaf and stalk
  c.drawLine(Offset(x, y - size * 0.85), Offset(x + size * 0.15, y - size * 1.3),
      Paint()..color = const Color(0xFF5A4A2A)..strokeWidth = math.max(1.0, size * 0.14)..strokeCap = StrokeCap.round);
  _ellipse(c, x + size * 0.55, y - size * 1.2, size * 0.5, size * 0.2, const Color(0xFF4E9A3A));
  final r = Rect.fromCenter(center: Offset(x, y), width: size * 2.1, height: size * 1.9); // a lime is a touch wider than tall
  final shader = ui.Gradient.radial(Offset(x - size * 0.35, y - size * 0.4), size * 1.7,
      [lerpColor(body, Colors.white, 0.45), body, lerpColor(body, const Color(0xFF1F5A14), 0.55)], [0.0, 0.5, 1.0]);
  c.drawOval(r, Paint()..shader = shader);
  c.drawOval(r, Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(0.8, size * 0.07)..color = const Color(0x661F4A12));
  // little nub at the bottom and a soft highlight
  _ellipse(c, x, y + size * 0.9, size * 0.16, size * 0.10, lerpColor(body, const Color(0xFF1F5A14), 0.4));
  _ellipse(c, x - size * 0.38, y - size * 0.38, size * 0.34, size * 0.20, const Color(0xB3FFFFFF));
}

class PositivityScene extends StatefulWidget {
  const PositivityScene({super.key});

  @override
  State<PositivityScene> createState() => _PositivitySceneState();
}

class _PositivitySceneState extends State<PositivityScene> with SceneLoop {
  final math.Random _rnd = math.Random();
  final TextEditingController _ctrl = TextEditingController();

  double _t = 0;
  int _level = 0;
  List<_Entry> _entries = [];
  String? _overlay; // null, 'chips', 'write' or 'confirm'
  int _promptI = 0;
  String? _viewText;
  double _viewUntil = 0;
  final Map<_Entry, double> _birth = <_Entry, double>{};
  final Set<_Entry> _fresh = <_Entry>{};
  List<_Hit> _hits = [];
  final List<_Petal> _petals = [];
  double _nextPetal = 1.5;
  double _g = 0;
  Offset _mouse = const Offset(-999, -999);

  @override
  void initState() {
    super.initState();
    _level = Levels.get('positivity');
    _entries = _loadEntries();
    final recent = _entries.length > _slots ? _entries.sublist(_entries.length - _slots) : _entries;
    for (var rank = 0; rank < recent.length; rank++) {
      _birth[recent[rank]] = 0.3 + 0.05 * rank; // blossoms open one after another
    }
    _g = _targetG() * 0.85;
    startLoop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    stopLoop();
    super.dispose();
  }

  double _targetG() => math.pow(smooth(_entries.length / _growFullAt), 0.6).toDouble();

  int _todayCount() {
    final today = isoToday();
    return _entries.where((e) => e.date == today).length;
  }

  // ---------------------------------------------------------------- actions
  void _toggleLevel() => setState(() => _level = Levels.toggle('positivity'));

  void _closeOverlay() {
    setState(() {
      _overlay = null;
      _ctrl.clear();
    });
  }

  void _openAdd() {
    setState(() {
      _viewText = null;
      if (_level == 0) {
        _overlay = 'chips';
      } else {
        final today = isoToday();
        final done = _entries.where((e) => e.date == today && e.kind == 'deep').length;
        _promptI = (todayOrdinal() + done) % _prompts.length;
        _openWrite();
      }
    });
  }

  void _openWrite() {
    setState(() {
      _overlay = 'write';
      _ctrl.clear();
    });
  }

  void _nextPrompt() {
    setState(() => _promptI = (_promptI + 1 + _rnd.nextInt(_prompts.length - 1)) % _prompts.length);
  }

  void _submitText() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (_level == 1) {
      _addEntry(text, 'deep', _prompts[_promptI]);
    } else {
      _addEntry(text, 'own');
    }
  }

  void _addEntry(String text, String kind, [String prompt = '']) {
    final serial = _entries.isNotEmpty ? _entries.last.n + 1 : 0;
    final e = _Entry(serial, isoToday(), text, kind, prompt);
    setState(() {
      _entries.add(e);
      if (_entries.length > _maxSaved) _entries.removeAt(0);
      _saveEntries(_entries);
      _birth[e] = _t;
      _fresh.add(e);
      _overlay = null;
      _ctrl.clear();
      _viewText = null;
    });

    final comp = Companion.I;
    if (kind == 'deep') {
      Sound.chime([523.25, 659.25, 783.99, 1046.50]);
    } else {
      Sound.chime([659.25, 783.99, 1046.50]);
    }
    comp.cheer(2.2);
    if (_todayCount() == _dailyGoal) {
      comp.say("That's your three for today. ${comp.name} is so proud of you.", 7.0);
    } else {
      comp.say(_addedLines[_rnd.nextInt(_addedLines.length)].replaceAll('{n}', comp.name), 5.0);
    }
    comp.grow(); // a day of looking after yourself (counts once per day)
  }

  void _askClear() => setState(() => _overlay = 'confirm');

  void _doClear() {
    setState(() {
      _entries = [];
      _birth.clear();
      _fresh.clear();
      _hits = [];
      _saveEntries(_entries);
      _overlay = null;
      _ctrl.clear();
      _viewText = null;
    });
    final comp = Companion.I;
    comp.say('A fresh start. ${comp.name} is right here with you.', 6.0);
  }

  void _showEntry(_Entry e) {
    final label = niceDate(e.date);
    _viewText = label.isNotEmpty ? '$label  ·  ${e.text}' : e.text;
    _viewUntil = _t + 8.0;
    Sound.plink(880.00, vol: 0.7);
  }

  void _onPointerDown(PointerDownEvent ev) {
    if (_overlay != null) return;
    final pos = ev.localPosition;
    if (Companion.I.rect.contains(pos)) {
      Companion.I.pet();
      return;
    }
    _Entry? best;
    var bd = 1e9;
    for (final h in _hits) {
      final d = (pos - Offset(h.x, h.y)).distance;
      if (d <= h.size + 8 && d < bd) {
        best = h.e;
        bd = d;
      }
    }
    if (best != null) _showEntry(best);
  }

  void _onEsc() {
    if (_overlay != null) {
      _closeOverlay();
    } else {
      Nav.I.go('home');
    }
  }

  // ---------------------------------------------------------------- update
  // which two growth stages are showing, how far we are between them, and how strongly the next one has faded in
  (int, double, double) _stage() {
    final last = _treeFiles.length - 1; // number of steps between growth pictures
    final p = _g * last;
    final i = p.floor().clamp(0, last - 1);
    final f = (p - i).clamp(0.0, 1.0);
    return (i, f, smooth((f - 0.3) / 0.4));
  }

  // height of stage [k] on screen while we are [f] of the way from stage [i] to the next
  double _stageH(int k, int i, double f) {
    final base = _finalH * _treeSize[k];
    return k == i ? base * (1 + 0.15 * f) : base * (0.85 + 0.15 * f);
  }

  (double, double, double, double) _canopyGeom(double g) {
    final (i, f, fade) = _stage();
    final base = _gy;
    List<double> one(int k) {
      final h = _stageH(k, i, f), w = h * _treeAspect[k];
      final cf = _canopyFrac[k];
      return [_gx - w / 2 + cf[0] * w, base - h + cf[1] * h, cf[2] * w, cf[3] * h];
    }

    final a = one(i), b = one(i + 1);
    return (_mix(a[0], b[0], fade), _mix(a[1], b[1], fade), _mix(a[2], b[2], fade), _mix(a[3], b[3], fade));
  }

  @override
  void onTick(double dt) {
    _t += dt;
    _g += (_targetG() - _g) * math.min(1.0, dt * 1.2);

    _nextPetal -= dt;
    if (_nextPetal <= 0) {
      _nextPetal = 2.5 + _rnd.nextDouble() * 2.0;
      final (cx, cy, rx, ry) = _canopyGeom(_g);
      _petals.add(_Petal(
        cx + (_rnd.nextDouble() * 1.4 - 0.7) * rx,
        cy + _rnd.nextDouble() * 0.7 * ry,
        _t,
        _blossoms[_rnd.nextInt(_blossoms.length)],
        0.7 + _rnd.nextDouble() * 0.5,
        _rnd.nextDouble() * 6.28,
      ));
    }
    _petals.removeWhere((p) => _t - p.t0 >= 9.0);
    _fresh.removeWhere((e) => _t - (_birth[e] ?? -99.0) >= 2.0);
  }

  // ---------------------------------------------------------------- drawing
  String _line() {
    final comp = Companion.I;
    final v = _viewText;
    if (v != null && _t < _viewUntil) return v;
    if (nowSeconds() < comp.sayUntil) return comp.sayText;
    if (_entries.isEmpty) {
      return _level == 0
          ? 'Your tree is just starting. Add the first good thing whenever you like.'
          : 'Plant the first reflection whenever you like.';
    }
    final lines = _level == 1 ? _linesDeeper : _linesGentle;
    return lines[(_t ~/ 13) % lines.length].replaceAll('{n}', comp.name);
  }

  void _drawBackground(Canvas c) {
    final img = SceneArt.get(_bgFile);
    if (img == null) {
      drawAmbientBg(c, w: Layout.w, h: Layout.h);
      return;
    }
    final b = _bg;
    drawArt(c, img, Rect.fromLTWH(b.ox, b.oy, _bgW * b.s, _bgH * b.s), q: FilterQuality.high);
  }

  // the tree: two neighbouring growth pictures cross-fade as it grows
  void _drawTree(Canvas c) {
    final (i, f, fade) = _stage();
    for (final k in <int>[i, i + 1]) {
      final img = SceneArt.get(_treeFiles[k]);
      if (img == null) continue;
      final alpha = k == i ? 1.0 - smooth((fade - 0.5) / 0.5) : fade; // old stage stays solid, then fades once the new one is in
      if (alpha <= 0.01) continue;
      final h = _stageH(k, i, f), w = h * _treeAspect[k];
      final dst = Rect.fromLTWH(_gx - w / 2, _gy - h + h * 0.03, w, h); // the picture's shadow sits just below the roots
      // draw the picture on its own layer and fade its lowest part away, so the painted soil dissolves into the landscape
      c.saveLayer(dst.inflate(4), Paint()..color = Color.fromARGB(a8(alpha), 255, 255, 255));
      drawArt(c, img, dst, q: FilterQuality.high);
      c.drawRect(
          dst.inflate(4),
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(0, dst.top), Offset(0, dst.bottom),
                const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)], const [0.0, _soilFadeFrom, 1.0]));
      c.restore();
    }
    _drawGrassBase(c);
  }

  // a soft shadow and little tufts of grass where the trunk meets the mound
  void _drawGrassBase(Canvas c) {
    final span = _finalH * _treeSize[0] * _treeAspect[0] * (0.25 + 0.75 * _g); // grows a little with the tree
    _ellipse(c, _gx, _gy - 1, span * 0.55, span * 0.09, const Color(0x442E4A2A));
    const cols = [Color(0xFF5E8F3A), Color(0xFF74A446), Color(0xFF4C7F34), Color(0xFF8DB652)];
    final rnd = math.Random(11);
    final n = 22;
    for (var i = 0; i < n; i++) {
      final u = (i / (n - 1)) * 2 - 1; // -1..1 across the base
      final x = _gx + u * span * 0.5 + (rnd.nextDouble() - 0.5) * 4;
      final hgt = (5 + rnd.nextDouble() * 9) * (1 - 0.45 * u.abs()) * (0.7 + 0.5 * _g);
      final lean = (rnd.nextDouble() - 0.5) * 8 + 2 * math.sin(_t * 0.9 + i);
      final y = _gy + rnd.nextDouble() * 2;
      c.drawPath(
          Path()
            ..moveTo(x - 1.4, y)
            ..quadraticBezierTo(x + lean * 0.4, y - hgt * 0.6, x + lean, y - hgt)
            ..quadraticBezierTo(x + lean * 0.4 + 1.4, y - hgt * 0.5, x + 1.4, y),
          Paint()..color = cols[i % cols.length]);
    }
  }

  void _drawFruits(Canvas c, double t) {
    final (cx, cy, rx, ry) = _canopyGeom(_g);
    final size = 4.5 + 6.0 * _g;
    final hits = <_Hit>[];
    final shown = _entries.length > _slots ? _entries.sublist(_entries.length - _slots) : _entries;
    for (final e in shown) {
      final k = e.n % _slots;
      final sp = _slotPos(k, cx, cy, rx, ry);
      final x = sp.dx + 2.0 * math.sin(t * 0.6 + k * 0.7);
      final y = sp.dy + 1.2 * math.sin(t * 0.8 + k);
      final age = t - (_birth[e] ?? -99.0);
      if (age < 0) continue;
      final s = size * math.max(0.0, popCurve(age / 0.9));
      final gold = e.kind == 'deep';
      final col = _fruits[k % _fruits.length];

      final hover = _overlay == null && (_mouse - Offset(x, y)).distance < size + 6;
      final gs = math.max(4.0, s * (hover ? 5.0 : (gold ? 4.0 : 3.0)));
      drawGlow(c, Offset(x, y), gs / 2, const Color(0xFFFFECBE),
          strength: 230, opacity: (hover ? 190 : (gold ? 120 : 60)) / 255); // every thought glows softly
      _drawFruit(c, x, y, s, col, gold);
      hits.add(_Hit(e, x, y, size));

      if (_fresh.contains(e) && age < 1.8) {
        // a brand-new blossom sparkles
        final gs = size * (4 + 6 * smooth(age / 1.8));
        drawGlow(c, Offset(x, y), gs / 2, const Color(0xFFFFECBE),
            strength: 230, opacity: 220 * (1 - age / 1.8) / 255);
        for (var j = 0; j < 5; j++) {
          final a = j * 1.2566 + age * 1.4;
          final r = size * 0.8 + age * 24;
          final sn = math.sin(age * 6 + j);
          drawSparkle(c, x + math.cos(a) * r, y + math.sin(a) * r, 9 + 5 * sn * sn,
              const Color(0xFFFFF0BE), 255 * (1 - age / 1.8));
        }
      }
    }
    _hits = hits;
  }

  void _drawPetals(Canvas c, double t) {
    for (final p in _petals) {
      final age = t - p.t0;
      final x = p.x0 + 14 * math.sin(age * 0.9 + p.ph) + age * 5;
      final y = p.y0 + age * 24;
      final alpha = 215 * math.min(1.0, math.min(age / 1.0, (9.0 - age) / 2.0));
      if (alpha > 2) {
        _ellipse(c, x, y, 4 * p.sz, math.max(1.0, 2.6 * p.sz), p.col.withAlpha(a8(alpha / 255.0)));
      }
    }
  }

  void _draw(Canvas c) {
    final t = _t;
    final comp = Companion.I;
    final port = Layout.portrait;
    _drawBackground(c);

    c.save(); // the whole tree sways a touch around its roots
    c.translate(_gx, _gy);
    c.rotate(0.010 * math.sin(t * 0.7));
    c.translate(-_gx, -_gy);
    _drawTree(c);
    _drawFruits(c, t);
    c.restore();
    _drawPetals(c, t);

    comp.draw(c, port ? Offset(130, _gy + 60) : const Offset(170, 400), port ? 190 : 200, sparkles: false);
    drawBubble(c, _line(), Layout.w / 2, port ? 108 : 20, maxW: port ? 520 : 600, size: 22);

    final n = _entries.length;
    final status = n == 0
        ? 'Your tree is waiting for its first fruit'
        : 'Today ${math.min(_todayCount(), _dailyGoal)} of $_dailyGoal  ·  $n on your tree';
    final sp = port ? Offset(Layout.w / 2, Layout.h - 150) : const Offset(210, 585);
    drawGlass(c, Rect.fromCenter(center: sp, width: 400, height: 32), radius: 16, alpha: 170); // keeps the text readable on the picture
    drawText(c, status, 17, kText, sp);

    if (_overlay != null) {
      c.drawRect(Rect.fromLTWH(0, 0, Layout.w, Layout.h), Paint()..color = const Color(0x6E3C285A));
      switch (_overlay) {
        case 'chips':
          _drawChips(c);
          break;
        case 'write':
          _drawWrite(c);
          break;
        default:
          _drawConfirm(c);
      }
    }
  }

  void _drawChips(Canvas c) {
    final cx = Layout.w / 2;
    if (Layout.portrait) {
      final oy = _oy;
      drawGlass(c, Rect.fromLTWH(24, 150 + oy, 552, 440), radius: 30, alpha: 238);
      drawText(c, "What's one small good thing today?", 26, kText, Offset(cx, 200 + oy), bold: true);
      drawText(c, 'Tap one that fits, or write your own.', 18, kTextDim, Offset(cx, 240 + oy));
      drawText(c, 'It stays on this device.', 18, kTextDim, Offset(cx, 264 + oy));
      return;
    }
    drawGlass(c, const Rect.fromLTWH(100, 110, 700, 400), radius: 30, alpha: 238);
    drawText(c, "What's one small good thing today?", 30, kText, Offset(cx, 150), bold: true);
    drawText(c, 'Tap one that fits, or write your own. It stays on this device.', 18, kTextDim, Offset(cx, 190));
  }

  void _drawWrite(Canvas c) {
    final port = Layout.portrait;
    final cx = Layout.w / 2;
    final t0 = 130.0 + _oy;
    drawGlass(c, port ? Rect.fromLTWH(24, t0, 552, 520) : const Rect.fromLTWH(100, 110, 700, 420),
        radius: 30, alpha: 238);
    String title, hint;
    if (_level == 1) {
      title = _prompts[_promptI];
      hint = 'A line or two is plenty. It stays on this device.';
    } else {
      title = 'Write your own small good thing';
      hint = 'It stays on this device.';
    }
    var y = port ? t0 + 50 : 160.0;
    for (final line in wrapText(title, port ? 26 : 28, true, port ? 490 : 600).take(port ? 3 : 2)) {
      drawText(c, line, port ? 26 : 28, kText, Offset(cx, y), bold: true);
      y += port ? 34 : 36;
    }
    drawText(c, hint, 18, kTextDim, Offset(cx, port ? t0 + 150 : 250));
    final box = port ? Rect.fromLTWH(50, t0 + 175, 500, 150) : const Rect.fromLTWH(150, 275, 600, 140);
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(22)), Paint()..color = kCard);
    drawText(c, '${_ctrl.text.length}/${_maxLen[_level]}', 16, kTextDim, Offset(box.right - 28, box.bottom + 15));
  }

  void _drawConfirm(Canvas c) {
    final port = Layout.portrait;
    final cx = Layout.w / 2;
    final top = port ? 360.0 + _oy : 190.0;
    drawGlass(c, port ? Rect.fromLTWH(50, top, 500, 250) : const Rect.fromLTWH(230, 190, 440, 220),
        radius: 30, alpha: 240);
    drawText(c, 'Clear your whole tree?', 28, kText, Offset(cx, top + 38), bold: true);
    var y = top + (port ? 84 : 82);
    for (final line in wrapText(
        "Every fruit and note will be removed from this device. This can't be undone.", 19, false, port ? 440 : 380)) {
      drawText(c, line, 19, kTextDim, Offset(cx, y));
      y += 25;
    }
  }

  // ---------------------------------------------------------------- widgets
  // extra top offset for the pop-up panels on very tall phones
  double get _oy => Layout.portrait ? ((Layout.h - 1000) * 0.25).clamp(0.0, 80.0).toDouble() : 0.0;

  List<Widget> _overlayWidgets() {
    final port = Layout.portrait;
    final oy = _oy;
    final t0 = 130.0 + oy; // top of the write panel
    switch (_overlay) {
      case 'chips':
        return [
          for (var i = 0; i < _chips.length; i++)
            CalmButton(
              rect: port
                  ? Rect.fromLTWH(36.0 + (i % 3) * 177, 300.0 + oy + (i ~/ 3) * 66, 166, 52)
                  : Rect.fromLTWH(126.0 + (i % 3) * 220, 232.0 + (i ~/ 3) * 66, 208, 52),
              title: _chips[i],
              titleSize: port ? 15 : 17,
              onTap: () => _addEntry(_chips[i], 'chip'),
            ),
          CalmButton(
            rect: port ? Rect.fromLTWH(44, 512 + oy, 250, 52) : const Rect.fromLTWH(136, 440, 300, 52),
            title: 'Write my own',
            color: _calmC,
            hoverColor: _calmHoverC,
            titleSize: 21,
            onTap: _openWrite,
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(306, 512 + oy, 250, 52) : const Rect.fromLTWH(464, 440, 300, 52),
            title: 'Never mind',
            textColor: kTextDim,
            titleSize: 21,
            onTap: _closeOverlay,
          ),
        ];
      case 'write':
        final deep = _level == 1;
        return [
          CalmTextField(
            key: ValueKey<int>(_level),
            rect: port ? Rect.fromLTWH(66, t0 + 191, 468, 118) : const Rect.fromLTWH(170, 291, 560, 110),
            controller: _ctrl,
            hint: deep ? 'Write whatever comes to mind' : 'Type it here',
            maxLength: _maxLen[_level],
            maxLines: 4,
            fontSize: 22,
            bold: false,
            align: TextAlign.left,
            autofocus: !isMobilePlatform,
            onSubmit: _submitText,
            onChanged: (_) => setState(() {}),
          ),
          if (deep)
            CalmButton(
              rect: port ? Rect.fromLTWH(50, t0 + 372, 500, 48) : const Rect.fromLTWH(124, 448, 200, 52),
              title: 'Another prompt',
              color: _calmC,
              hoverColor: _calmHoverC,
              titleSize: 19,
              onTap: _nextPrompt,
            ),
          CalmButton(
            rect: port ? Rect.fromLTWH(50, t0 + 372 + (deep ? 58 : 0), 200, 52) : Rect.fromLTWH(deep ? 340 : 227, 448, 180, 52),
            title: 'Never mind',
            textColor: kTextDim,
            titleSize: 19,
            onTap: _closeOverlay,
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(270, t0 + 372 + (deep ? 58 : 0), 280, 52) : Rect.fromLTWH(deep ? 536 : 433, 448, 240, 52),
            title: 'Add to my tree',
            color: kAccent,
            hoverColor: kAccentHover,
            textColor: kWhite,
            titleSize: 21,
            onTap: _submitText,
          ),
        ];
      case 'confirm':
        return [
          CalmButton(
            rect: port ? Rect.fromLTWH(75, 360 + oy + 170, 210, 52) : const Rect.fromLTWH(250, 336, 190, 52),
            title: 'Keep my tree',
            titleSize: 19,
            onTap: _closeOverlay,
          ),
          CalmButton(
            rect: port ? Rect.fromLTWH(315, 360 + oy + 170, 210, 52) : const Rect.fromLTWH(460, 336, 190, 52),
            title: 'Yes, clear it',
            color: kAccent,
            hoverColor: kAccentHover,
            textColor: kWhite,
            titleSize: 19,
            onTap: _doClear,
          ),
        ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final port = Layout.portrait;
    return EscScope(
      onEsc: _onEsc,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: MouseRegion(
              onHover: (e) => _mouse = e.localPosition,
              onExit: (_) => _mouse = const Offset(-999, -999),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                child: paintLayer(_draw),
              ),
            ),
          ),
          if (_overlay == null) ...[
            CalmButton(
              rect: port ? const Rect.fromLTWH(24, 50, 110, 40) : const Rect.fromLTWH(24, 24, 110, 40),
              title: 'Leave',
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
              titleSize: 18,
              onTap: () => Nav.I.go('home'),
            ),
            SoundButton(
              rect: port ? Rect.fromLTWH(Layout.w - 124, 50, 100, 36) : Rect.fromLTWH(kW - 124, 24, 100, 36),
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
            ),
            CalmButton(
              rect: port ? Rect.fromLTWH(Layout.w / 2 - 70, 50, 140, 36) : Rect.fromLTWH(kW - 164, 70, 140, 36),
              title: 'Level: ${Levels.name(_level)}',
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
              titleSize: 15,
              onTap: _toggleLevel,
            ),
            CalmButton(
              rect: port ? Rect.fromLTWH(40, Layout.h - 124, 520, 60) : const Rect.fromLTWH(70, 516, 280, 50),
              title: _level == 1 ? 'Add a reflection' : 'Add a good thing',
              color: kAccent,
              hoverColor: kAccentHover,
              textColor: kWhite,
              titleSize: 22,
              pulse: true,
              onTap: _openAdd,
            ),
            if (_entries.isNotEmpty)
              CalmButton(
                rect: port ? Rect.fromLTWH(Layout.w / 2 - 71, Layout.h - 208, 142, 30) : Rect.fromLTWH(kW - 166, 558, 142, 30),
                title: 'Start fresh',
                color: _calmC,
                hoverColor: _calmHoverC,
                textColor: kTextDim,
                titleSize: 14,
                onTap: _askClear,
              ),
          ] else
            ..._overlayWidgets(),
        ],
      ),
    );
  }
}