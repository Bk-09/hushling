// "Something good": a gratitude tree that grows a blossom for every good thing you add
// (scenes/positivity.py). Saved only on this device.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/levels.dart';
import '../core/palette.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const String _storeKey = 'tree';
const int _maxSaved = 400; // oldest entries are dropped after this many
const int _slots = 60; // blossoms shown on the tree at once
const int _growFullAt = 30; // entries until the tree is fully grown
const int _dailyGoal = 3; // "three good things" (a soft goal, never enforced)
const List<int> _maxLen = [60, 140]; // longest note: Gentle (own words), Deeper
const double _gx = 575, _gy = 515; // where the tree stands

const Color _leafShade = Color(0xFF76B098);
const Color _leafMain = Color(0xFF94CAAA);
const Color _leafLight = Color(0xFFBAE4C2);
const Color _trunk = Color(0xFFBA8E82);
const Color _trunkDark = Color(0xFFA07670);
const Color _gold = Color(0xFFFFCE64);
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
  'Your tree grows one blossom at a time.',
  '{n} is happy to sit under this tree with you.',
  'Tap a blossom to remember it.',
  "Good things don't have to be big.",
  'You can come back any day. The tree will wait.',
];
const List<String> _linesDeeper = [
  'A little reflection, then a golden blossom.',
  "Noticing is a skill. You're practising it.",
  'Take your time with it.',
  '{n} is happy to sit under this tree with you.',
  'Tap a blossom to read it again.',
  'You can come back any day. The tree will wait.',
];
const List<String> _addedLines = [
  "That's a lovely one.",
  '{n} loved reading that.',
  'A new blossom. Look at it glow.',
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

class _Blob {
  final double ux, uy, sx, sy, ph;
  const _Blob(this.ux, this.uy, this.sx, this.sy, this.ph);
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

void _drawBlossom(Canvas c, double x, double y, double size, Color col, bool gold) {
  if (size < 1.5) return;
  final petals = gold ? 6 : 5;
  for (var i = 0; i < petals; i++) {
    final a = i * 2 * math.pi / petals - math.pi / 2;
    _circle(c, x + math.cos(a) * size * 0.55, y + math.sin(a) * size * 0.55, size * 0.52, col);
  }
  _circle(c, x, y, size * 0.34, gold ? const Color(0xFFFFF0C8) : const Color(0xFFFFE296));
  _circle(c, x - size * 0.08, y - size * 0.10, size * 0.10, const Color(0xE6FFFFFF));
}

class PositivityScene extends StatefulWidget {
  const PositivityScene({super.key});

  @override
  State<PositivityScene> createState() => _PositivitySceneState();
}

class _PositivitySceneState extends State<PositivityScene> with SceneLoop {
  final math.Random _rnd = math.Random();
  late final List<_Blob> _blobs;
  static const List<Offset> _lights = [
    Offset(-0.45, -0.50), Offset(-0.10, -0.66), Offset(0.25, -0.56),
    Offset(-0.66, -0.10), Offset(0.55, -0.26), Offset(-0.30, 0.0),
  ];

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
    final rng = math.Random(5);
    _blobs = [];
    for (var i = 0; i < 16; i++) {
      final a = i * 2 * math.pi / 16 + (rng.nextDouble() * 0.3 - 0.15);
      _blobs.add(_Blob(math.cos(a) * 0.95, math.sin(a) * 0.95, 0.26 + rng.nextDouble() * 0.08,
          0.26 + rng.nextDouble() * 0.08, rng.nextDouble() * 6.28));
    }
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
  (double, double, double, double) _canopyGeom(double g) {
    final h = 90 + 120 * g;
    return (_gx, _gy - h - 20 * g, 55 + 150 * g, 42 + 108 * g);
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

  void _drawHills(Canvas c) {
    const hills = <List<Object>>[
      [720.0, 590.0, 420.0, 120.0, Color(0xFFCEE8CA)],
      [180.0, 620.0, 380.0, 130.0, Color(0xFFBCE2BE)],
      [450.0, 660.0, 640.0, 150.0, Color(0xFFACD8B2)],
    ];
    for (final h in hills) {
      _ellipse(c, h[0] as double, h[1] as double, h[2] as double, h[3] as double, h[4] as Color);
    }
  }

  void _drawTrunk(Canvas c) {
    final g = _g;
    final h = 90 + 120 * g;
    final top = _gy - h;
    final bw = 30 + 14 * g, tw = 14 + 9 * g;
    _ellipse(c, _gx + 8, _gy + 4, bw * 1.5, 11, const Color(0x284A2E52));
    final left = <Offset>[], right = <Offset>[];
    const n = 14;
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final y = top + u * h;
      final w = tw + (bw - tw) * math.pow(u, 1.8).toDouble();
      final off = 6 * math.sin(u * 3.0) * (1 - 0.3 * u);
      left.add(Offset(_gx + off - w / 2, y));
      right.add(Offset(_gx + off + w / 2, y));
    }
    Path poly(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].dx, pts[i].dy);
      }
      return p..close();
    }

    c.drawPath(poly([...left, ...right.reversed]), Paint()..color = _trunk);
    final shade = <Offset>[
      for (var i = 0; i < left.length; i++)
        Offset(left[i].dx + (right[i].dx - left[i].dx) * 0.62, left[i].dy),
    ];
    c.drawPath(poly([...shade, ...right.reversed]), Paint()..color = _trunkDark);
    _ellipse(c, _gx + 2, _gy, bw * 0.78, 8, _trunk);
  }

  void _drawCanopy(Canvas c, double t) {
    final (cx, cy, rx, ry) = _canopyGeom(_g);
    Offset blobPos(_Blob b, [double dy = 0.0]) =>
        Offset(cx + b.ux * rx * 0.78 + 3 * math.sin(t * 0.6 + b.ph), cy + b.uy * ry * 0.78 + dy);

    final drop = 6 + 6 * _g;
    _ellipse(c, cx, cy + drop, rx * 0.86, ry * 0.86, _leafShade);
    for (final b in _blobs) {
      final p = blobPos(b, drop);
      _ellipse(c, p.dx, p.dy, rx * b.sx, ry * b.sy, _leafShade);
    }
    _ellipse(c, cx, cy, rx * 0.86, ry * 0.86, _leafMain);
    for (final b in _blobs) {
      final p = blobPos(b);
      _ellipse(c, p.dx, p.dy, rx * b.sx, ry * b.sy, _leafMain);
    }
    for (final l in _lights) {
      _ellipse(c, cx + l.dx * rx * 0.62, cy + l.dy * ry * 0.62, rx * 0.20, ry * 0.15, _leafLight.withAlpha(150));
    }
  }

  void _drawBlossoms(Canvas c, double t) {
    final (cx, cy, rx, ry) = _canopyGeom(_g);
    final size = 4.5 + 5.5 * _g;
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
      final col = gold ? _gold : _blossoms[k % _blossoms.length];

      final hover = _overlay == null && (_mouse - Offset(x, y)).distance < size + 6;
      if (gold || hover) {
        final gs = math.max(4.0, s * (hover ? 5.0 : 4.0));
        drawGlow(c, Offset(x, y), gs / 2, const Color(0xFFFFECBE), strength: 230, opacity: (hover ? 190 : 110) / 255);
      }
      _drawBlossom(c, x, y, s, col, gold);
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
    drawAmbientBg(c);
    drawGlow(c, const Offset(770, 100), 150, const Color(0xFFFFEECC), strength: 175);
    _drawHills(c);

    _drawTrunk(c);
    _drawCanopy(c, t);
    _drawBlossoms(c, t);
    _drawPetals(c, t);

    comp.draw(c, const Offset(170, 400), 200, sparkles: false);
    drawBubble(c, _line(), kW / 2, 20, maxW: 600, size: 22);

    final n = _entries.length;
    final status = n == 0
        ? 'Your tree is waiting for its first blossom'
        : 'Today ${math.min(_todayCount(), _dailyGoal)} of $_dailyGoal  ·  $n on your tree';
    drawText(c, status, 17, kText, const Offset(210, 585));

    if (_overlay != null) {
      c.drawRect(const Rect.fromLTWH(0, 0, kW, kH), Paint()..color = const Color(0x6E3C285A));
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
    const cx = kW / 2;
    drawGlass(c, const Rect.fromLTWH(100, 110, 700, 400), radius: 30, alpha: 238);
    drawText(c, "What's one small good thing today?", 30, kText, const Offset(cx, 150), bold: true);
    drawText(c, 'Tap one that fits, or write your own. It stays on this device.', 18, kTextDim,
        const Offset(cx, 190));
  }

  void _drawWrite(Canvas c) {
    const cx = kW / 2;
    drawGlass(c, const Rect.fromLTWH(100, 110, 700, 420), radius: 30, alpha: 238);
    String title, hint;
    if (_level == 1) {
      title = _prompts[_promptI];
      hint = 'A line or two is plenty. It stays on this device.';
    } else {
      title = 'Write your own small good thing';
      hint = 'It stays on this device.';
    }
    var y = 160.0;
    for (final line in wrapText(title, 28, true, 600).take(2)) {
      drawText(c, line, 28, kText, Offset(cx, y), bold: true);
      y += 36;
    }
    drawText(c, hint, 18, kTextDim, const Offset(cx, 250));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(150, 275, 600, 140), const Radius.circular(22)),
        Paint()..color = kCard);
    drawText(c, '${_ctrl.text.length}/${_maxLen[_level]}', 16, kTextDim, const Offset(722, 430));
  }

  void _drawConfirm(Canvas c) {
    const cx = kW / 2;
    drawGlass(c, const Rect.fromLTWH(230, 190, 440, 220), radius: 30, alpha: 240);
    drawText(c, 'Clear your whole tree?', 28, kText, const Offset(cx, 228), bold: true);
    var y = 272.0;
    for (final line in wrapText(
        "Every blossom and note will be removed from this device. This can't be undone.", 19, false, 380)) {
      drawText(c, line, 19, kTextDim, Offset(cx, y));
      y += 25;
    }
  }

  // ---------------------------------------------------------------- widgets
  List<Widget> _overlayWidgets() {
    switch (_overlay) {
      case 'chips':
        return [
          for (var i = 0; i < _chips.length; i++)
            CalmButton(
              rect: Rect.fromLTWH(126.0 + (i % 3) * 220, 232.0 + (i ~/ 3) * 66, 208, 52),
              title: _chips[i],
              titleSize: 17,
              onTap: () => _addEntry(_chips[i], 'chip'),
            ),
          CalmButton(
            rect: const Rect.fromLTWH(136, 440, 300, 52),
            title: 'Write my own',
            color: _calmC,
            hoverColor: _calmHoverC,
            titleSize: 21,
            onTap: _openWrite,
          ),
          CalmButton(
            rect: const Rect.fromLTWH(464, 440, 300, 52),
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
            rect: const Rect.fromLTWH(170, 291, 560, 110),
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
              rect: const Rect.fromLTWH(124, 448, 200, 52),
              title: 'Another prompt',
              color: _calmC,
              hoverColor: _calmHoverC,
              titleSize: 19,
              onTap: _nextPrompt,
            ),
          CalmButton(
            rect: Rect.fromLTWH(deep ? 340 : 227, 448, 180, 52),
            title: 'Never mind',
            textColor: kTextDim,
            titleSize: 19,
            onTap: _closeOverlay,
          ),
          CalmButton(
            rect: Rect.fromLTWH(deep ? 536 : 433, 448, 240, 52),
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
            rect: const Rect.fromLTWH(250, 336, 190, 52),
            title: 'Keep my tree',
            titleSize: 19,
            onTap: _closeOverlay,
          ),
          CalmButton(
            rect: const Rect.fromLTWH(460, 336, 190, 52),
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
              rect: const Rect.fromLTWH(24, 24, 110, 40),
              title: 'Leave',
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
              titleSize: 18,
              onTap: () => Nav.I.go('home'),
            ),
            SoundButton(
              rect: Rect.fromLTWH(kW - 124, 24, 100, 36),
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
            ),
            CalmButton(
              rect: Rect.fromLTWH(kW - 164, 70, 140, 36),
              title: 'Level: ${Levels.name(_level)}',
              color: _calmC,
              hoverColor: _calmHoverC,
              textColor: kTextDim,
              titleSize: 15,
              onTap: _toggleLevel,
            ),
            CalmButton(
              rect: const Rect.fromLTWH(70, 516, 280, 50),
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
                rect: Rect.fromLTWH(kW - 166, 558, 142, 30),
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
