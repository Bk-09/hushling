import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/palette.dart';
import '../core/pets.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

const int _maxName = 14;
const int _cols = 5;
const double _cellH = 112;
const double _petPx = 78;

class _Tab {
  final String group;
  final String label;
  final Rect rect;
  _Tab(this.group, this.label, this.rect);
}

/// First-time setup AND later customizing (same screen, two modes).
class ChooseScene extends StatefulWidget {
  const ChooseScene({super.key});

  @override
  State<ChooseScene> createState() => _ChooseSceneState();
}

class _ChooseSceneState extends State<ChooseScene> with SceneLoop {
  final TextEditingController _name = TextEditingController();
  late bool _editing;
  late String _snapPet;
  late String _snapName;
  String _group = 'popular';
  int _page = 0;
  final List<_Tab> _tabs = <_Tab>[];
  Offset _mouse = const Offset(-100, -100);

  // ---- layout: landscape (900 x 600) or portrait (600 x tall). Everything that moves between the
  // two is a getter, so the rest of the code reads the same for both.
  bool get _port => Layout.portrait;
  int get _rows => _port ? (Layout.h >= 1100 ? 3 : 2) : 3; // 3 rows of friends fit on tall phones
  int get _perPage => _cols * _rows;
  double get _cellW => _port ? 104 : 106;
  double get _gridX => _port ? 40 : 344;
  // portrait: a share of any spare height on very tall phones goes between the sections
  double get _dy => _port ? ((Layout.h - (_rows == 3 ? 1100 : 1000)) * 0.3).clamp(0.0, 110.0).toDouble() : 0.0;
  double get _tabsY => _port ? 548 + _dy : 112;
  double get _gridY => _port ? 592 + _dy : 158;
  double get _pagerY => _port ? _gridY + _rows * _cellH + 22 : 530;
  Rect get _prevRect =>
      Rect.fromCenter(center: Offset(_gridX + _cellW * _cols / 2 - 90, _pagerY), width: 46, height: 36);
  Rect get _nextRect =>
      Rect.fromCenter(center: Offset(_gridX + _cellW * _cols / 2 + 90, _pagerY), width: 46, height: 36);
  Rect get _preview => _port ? Rect.fromLTWH(190, 176 + _dy, 220, 220) : const Rect.fromLTWH(24, 110, 300, 300);
  Rect get _box => _port ? Rect.fromLTWH(100, 480 + _dy, 400, 48) : const Rect.fromLTWH(24, 462, 300, 48);

  @override
  void initState() {
    super.initState();
    final comp = Companion.I;
    _editing = comp.exists;
    _name.text = _editing ? comp.name : '';
    _snapPet = comp.petId;
    _snapName = comp.name;
    _buildTabs();
    _showGroupOf(comp.petId);
    startLoop();
  }

  @override
  void dispose() {
    stopLoop();
    _name.dispose();
    super.dispose();
  }

  @override
  void onTick(double dt) {}

  // ------------------------------------------------------------ helpers
  void _buildTabs() {
    final groups = Pets.groups.where((g) => Pets.inGroup(g[0]).isNotEmpty).toList();
    _tabs.clear();
    if (groups.isEmpty) return;
    final w = ((_cellW * _cols) / groups.length).floorToDouble();
    for (var i = 0; i < groups.length; i++) {
      _tabs.add(_Tab(groups[i][0], groups[i][1], Rect.fromLTWH(_gridX + i * w + 2, _tabsY, w - 4, 32)));
    }
  }

  List<String> _ids() => Pets.inGroup(_group);

  int _pages() {
    final n = (_ids().length + _perPage - 1) ~/ _perPage;
    return n < 1 ? 1 : n;
  }

  List<MapEntry<String, Rect>> _cellRects() {
    final ids = _ids();
    final start = _page * _perPage;
    final out = <MapEntry<String, Rect>>[];
    for (var i = 0; start + i < ids.length && i < _perPage; i++) {
      out.add(MapEntry(
        ids[start + i],
        Rect.fromLTWH(_gridX + (i % _cols) * _cellW + 2, _gridY + (i ~/ _cols) * _cellH, _cellW - 4, _cellH - 6),
      ));
    }
    return out;
  }

  void _showGroupOf(String pid) {
    bool hasTab(String g) => _tabs.any((t) => t.group == g);
    if (Pets.popular.contains(pid) && hasTab('popular')) {
      _group = 'popular';
      final ids = _ids();
      _page = ids.contains(pid) ? ids.indexOf(pid) ~/ _perPage : 0;
    } else if (Pets.byId.containsKey(pid) && hasTab(Pets.byId[pid]!.group)) {
      _group = Pets.byId[pid]!.group;
      final ids = _ids();
      _page = ids.contains(pid) ? ids.indexOf(pid) ~/ _perPage : 0;
    } else if (_tabs.isNotEmpty) {
      _group = _tabs.first.group;
      _page = 0;
    }
  }

  // ------------------------------------------------------------ flow
  void _finish() {
    final comp = Companion.I;
    final typed = _name.text.trim();
    if (_editing) {
      comp.name = typed.isNotEmpty ? typed : _snapName;
      comp.save();
      comp.say('${comp.name} loves the new look!', 5.0);
      comp.cheer(3.0);
    } else {
      comp.finishSetup(typed.isNotEmpty ? typed : 'Pip');
    }
    Nav.I.go('home');
  }

  void _cancelEdit() {
    Companion.I.petId = _snapPet;
    Nav.I.go('home');
  }

  void _flip(int step) {
    setState(() => _page = (_page + step) % _pages());
  }

  void _onDown(PointerDownEvent e) {
    final p = e.localPosition;
    final comp = Companion.I;
    for (final t in _tabs) {
      if (t.rect.contains(p) && t.group != _group) {
        setState(() {
          _group = t.group;
          _page = 0;
        });
      }
    }
    for (final cell in _cellRects()) {
      if (cell.value.contains(p)) {
        comp.petId = cell.key;
        comp.cheer(1.2); // the chosen one hops happily
      }
    }
    if (_pages() > 1) {
      if (_prevRect.contains(p)) {
        _flip(-1);
      } else if (_nextRect.contains(p)) {
        _flip(1);
      }
    }
  }

  // ------------------------------------------------------------ drawing
  double _fit(String text, double width, [double size = 16]) {
    while (size > 11 && textWidth(text, size) > width) {
      size -= 1;
    }
    return size;
  }

  void _arrow(Canvas c, Rect r, int dir) {
    drawGlass(c, r, radius: 18, alpha: 170);
    final ctr = r.center;
    const d = 7.0;
    final path = Path();
    if (dir < 0) {
      path
        ..moveTo(ctr.dx + d / 2, ctr.dy - d)
        ..lineTo(ctr.dx + d / 2, ctr.dy + d)
        ..lineTo(ctr.dx - d, ctr.dy);
    } else {
      path
        ..moveTo(ctr.dx - d / 2, ctr.dy - d)
        ..lineTo(ctr.dx - d / 2, ctr.dy + d)
        ..lineTo(ctr.dx + d, ctr.dy);
    }
    path.close();
    c.drawPath(path, Paint()..color = kText);
  }

  void _draw(Canvas c) {
    drawAmbientBg(c, w: Layout.w, h: Layout.h);
    final comp = Companion.I;
    final cx = Layout.w / 2;
    final t = nowSeconds();
    final ty = _port ? 112.0 : 48.0; // title row; the subtitle sits 36 below
    final sub = _editing
        ? 'Your bond and growth stay exactly as they are.'
        : 'They start small, and grow with you at your own pace.';

    drawText(c, _editing ? 'Customize $_snapName' : 'Choose your companion', 38, kText, Offset(cx, ty),
        bold: true);
    drawText(c, sub, _fit(sub, 560, 20), kTextDim, Offset(cx, ty + 36));

    // ---- big preview of the pick
    drawGlass(c, _preview, radius: 30, alpha: 140);
    comp.draw(c, Offset(_preview.center.dx, _preview.center.dy + 2), _port ? _preview.height * 0.73 : 220,
        full: true, petIdOverride: comp.petId);
    drawText(c, Pets.nameOf(comp.petId), 26, kText, Offset(_preview.center.dx, _preview.bottom + 22), bold: true);

    // ---- name
    drawText(c, 'Their name', 18, kTextDim, Offset(_box.center.dx, _box.top - 12));
    drawGlass(c, _box, radius: 22, alpha: 200);

    // ---- the friends: tabs, grid, pager
    for (final tab in _tabs) {
      final sel = tab.group == _group;
      if (sel) {
        c.drawRRect(RRect.fromRectAndRadius(tab.rect, const Radius.circular(16)), Paint()..color = kAccent);
      } else {
        drawGlass(c, tab.rect, radius: 16, alpha: 150);
      }
      drawText(c, tab.label, 17, sel ? kWhite : kText, tab.rect.center, bold: sel);
    }

    for (final cell in _cellRects()) {
      final pid = cell.key;
      final r = cell.value;
      final sel = pid == comp.petId;
      if (sel) {
        drawGlass(c, r, radius: 22, alpha: 175);
        Pets.draw(c, pid, Offset(r.center.dx, r.top + 46), _petPx + 8, t, mood: 'happy');
      } else {
        if (r.contains(_mouse)) drawGlass(c, r, radius: 22, alpha: 95);
        Pets.drawThumb(c, pid, Offset(r.center.dx, r.top + 46), _petPx);
      }
      final nm = Pets.nameOf(pid);
      drawText(c, nm, _fit(nm, r.width - 6), sel ? kText : kTextDim, Offset(r.center.dx, r.bottom - 14), bold: sel);
    }

    final n = _pages();
    if (n > 1) {
      _arrow(c, _prevRect, -1);
      _arrow(c, _nextRect, 1);
      drawText(c, '${_page + 1} / $n', 20, kTextDim,
          Offset((_prevRect.center.dx + _nextRect.center.dx) / 2, _pagerY));
    }
    if (!_port) {
      drawText(c, 'Tap a friend to meet them', 17, kTextDim, Offset(_gridX + _cellW * _cols / 2, 574));
    }
  }

  @override
  Widget build(BuildContext context) {
    return EscScope(
      onEsc: () {
        if (_editing) _cancelEdit();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerHover: (e) => _mouse = e.localPosition,
              onPointerMove: (e) => _mouse = e.localPosition,
              onPointerSignal: (e) {
                if (e is PointerScrollEvent &&
                    _pages() > 1 &&
                    Rect.fromLTWH(_gridX, _tabsY - 8, _cellW * _cols, _rows * _cellH + 104).contains(e.localPosition)) {
                  _flip(e.scrollDelta.dy < 0 ? -1 : 1);
                }
              },
              child: paintLayer(_draw),
            ),
          ),
          CalmTextField(
            rect: _box.deflate(10),
            controller: _name,
            hint: _editing ? 'Type a name' : 'Type a name (or leave it for Pip)',
            maxLength: _maxName,
            fontSize: 26,
            autofocus: !isMobilePlatform,
            onSubmit: _finish,
          ),
          CalmButton(
            rect: _port ? Rect.fromLTWH(40, Layout.h - 124, 520, 60) : Rect.fromLTWH(24, 530, 300, 56),
            title: _editing ? 'Save changes' : 'Begin together',
            color: kAccent,
            hoverColor: kAccentHover,
            textColor: kWhite,
            titleSize: 26,
            onTap: _finish,
          ),
          if (_editing)
            CalmButton(
              rect: _port ? Rect.fromLTWH(24, 50, 110, 40) : Rect.fromLTWH(24, 24, 110, 40),
              title: 'Cancel',
              textColor: kTextDim,
              titleSize: 18,
              onTap: _cancelEdit,
            ),
        ],
      ),
    );
  }
}
