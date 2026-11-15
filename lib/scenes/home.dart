import 'package:flutter/material.dart';

import '../core/companion.dart';
import '../core/layout.dart';
import '../core/palette.dart';
import '../core/ui.dart';
import '../core/util.dart';
import '../nav.dart';

// The mood buttons on the home screen: (button text, scene name). To add a mode: write a scene,
// add it to _buildScene in main.dart, add one line here. Buttons are laid out evenly.
const List<List<String>> kHomeModes = [
  ["I'm stressed", 'stress'],
  ["I'm anxious", 'anxiety'],
  ['Something good', 'positivity'],
];

class HomeScene extends StatefulWidget {
  const HomeScene({super.key});

  @override
  State<HomeScene> createState() => _HomeSceneState();
}

class _HomeSceneState extends State<HomeScene> with SceneLoop {
  @override
  void initState() {
    super.initState();
    Companion.I.arrive();
    startLoop();
  }

  @override
  void dispose() {
    stopLoop();
    super.dispose();
  }

  @override
  void onTick(double dt) {}

  // ------------------------------------------------------------ portrait layout (600 x tall)
  // Vertical order, top to bottom: Customize, speech bubble, companion, status line, the three
  // mood buttons stacked, then the big "Calm me down" button at the bottom where a thumb
  // reaches it fastest.
  static const double _pPad = 40; // side margin
  static const double _pBtnW = 520; // button width (600 - 2 * 40)
  static const double _pHelpH = 112;
  static const double _pModeH = 68;
  static const double _pGap = 14;
  static const double _pBottom = 64; // keeps clear of the home indicator
  static const double _pBubbleTop = 100;
  static const double _pAvailTop = 250; // below the tallest speech bubble

  double get _pHelpTop => Layout.h - _pBottom - _pHelpH;
  double get _pModesTop {
    final n = kHomeModes.length;
    return _pHelpTop - 22 - (n * _pModeH + (n - 1) * _pGap);
  }

  /// Companion size and ground line, centred in the free space between bubble and buttons.
  ({double size, double centerY, double groundY}) _pPetBox() {
    final availBottom = _pModesTop - 40;
    final size = (availBottom - _pAvailTop - 60).clamp(150.0, 340.0).toDouble();
    final blockH = size + 50;
    final top = _pAvailTop + ((availBottom - _pAvailTop - blockH) / 2).clamp(0.0, 400.0);
    return (size: size, centerY: top + size / 2, groundY: top + size);
  }

  void _drawPortrait(Canvas c) {
    drawAmbientBg(c, w: Layout.w, h: Layout.h);
    final comp = Companion.I;
    const cx = kPW / 2;
    final box = _pPetBox();
    comp.draw(c, Offset(cx, box.centerY), box.size);
    drawBubble(c, comp.speech(), cx, _pBubbleTop, maxW: 520, size: 25);
    final stage = kStages[comp.stageIndex()].name;
    drawText(c, comp.name, 28, kText, Offset(cx, box.groundY + 34), bold: true);
    drawText(c, '$stage  ·  Day ${comp.daysTogether()} together', 20, kTextDim,
        Offset(cx, box.groundY + 66));
  }

  Widget _buildPortrait() {
    final n = kHomeModes.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (Companion.I.rect.contains(e.localPosition)) Companion.I.pet();
            },
            child: paintLayer(_drawPortrait),
          ),
        ),
        CalmButton(
          rect: Rect.fromLTWH(Layout.w - _pPad - 150, 44, 150, 40),
          title: 'Customize',
          textColor: kTextDim,
          titleSize: 18,
          onTap: () => Nav.I.go('choose'),
        ),
        for (var i = 0; i < n; i++)
          CalmButton(
            rect: Rect.fromLTWH(_pPad, _pModesTop + i * (_pModeH + _pGap), _pBtnW, _pModeH),
            title: kHomeModes[i][0],
            titleSize: 26,
            onTap: () => Nav.I.go(kHomeModes[i][1]),
          ),
        CalmButton(
          rect: Rect.fromLTWH(_pPad, _pHelpTop, _pBtnW, _pHelpH),
          title: 'Calm me down',
          subtitle: "Tap and we'll breathe together",
          color: kAccent,
          hoverColor: kAccentHover,
          textColor: kWhite,
          subColor: const Color(0xFFFFEEE2),
          titleSize: 34,
          subSize: 20,
          pulse: true,
          onTap: () => Nav.I.go('panic'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ landscape layout (900 x 600)
  void _draw(Canvas c) {
    drawAmbientBg(c);
    final comp = Companion.I;
    const cx = kW / 2;
    comp.draw(c, const Offset(cx, 248), 260);
    drawBubble(c, comp.speech(), cx, 20);
    final stage = kStages[comp.stageIndex()].name;
    drawText(c, '${comp.name}  ·  $stage  ·  Day ${comp.daysTogether()} together', 20, kTextDim,
        const Offset(cx, 398));
  }

  @override
  Widget build(BuildContext context) {
    if (Layout.portrait) return _buildPortrait();
    // one button per mode, spread evenly across the width
    final n = kHomeModes.length;
    const gap = 25.0;
    final total = kW - 100;
    final w = ((total - gap * (n - 1)) / n).floorToDouble();
    final size = n <= 3 ? 24.0 : 20.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (Companion.I.rect.contains(e.localPosition)) Companion.I.pet();
            },
            child: paintLayer(_draw),
          ),
        ),
        CalmButton(
          rect: Rect.fromLTWH(175, 418, 550, 88),
          title: 'Calm me down',
          subtitle: "Tap and we'll breathe together",
          color: kAccent,
          hoverColor: kAccentHover,
          textColor: kWhite,
          subColor: const Color(0xFFFFEEE2),
          titleSize: 34,
          subSize: 20,
          pulse: true,
          onTap: () => Nav.I.go('panic'),
        ),
        for (var i = 0; i < n; i++)
          CalmButton(
            rect: Rect.fromLTWH(50 + i * (w + gap), 528, w, 52),
            title: kHomeModes[i][0],
            titleSize: size,
            onTap: () => Nav.I.go(kHomeModes[i][1]),
          ),
        CalmButton(
          rect: Rect.fromLTWH(kW - 166, 381, 150, 34),
          title: 'Customize',
          textColor: kTextDim,
          titleSize: 17,
          onTap: () => Nav.I.go('choose'),
        ),
      ],
    );
  }
}
