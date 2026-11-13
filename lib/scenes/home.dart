import 'package:flutter/material.dart';

import '../core/companion.dart';
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
          title: 'I need help right now',
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
