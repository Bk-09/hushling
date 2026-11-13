import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'core/companion.dart';
import 'core/palette.dart';
import 'core/pets.dart';
import 'core/sound.dart';
import 'core/store.dart';
import 'core/util.dart';
import 'nav.dart';
import 'scenes/anxiety.dart';
import 'scenes/choose.dart';
import 'scenes/grounding.dart';
import 'scenes/home.dart';
import 'scenes/landing.dart';
import 'scenes/panic.dart';
import 'scenes/positivity.dart';
import 'scenes/stress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await Pets.init();
  Companion.I.load();
  await Future.wait<void>([
    Grain.init(),
    Sound.init(),
    Pets.preload(Companion.I.petId),
  ]);
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    // the 900x600 stage is designed for landscape
    try {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }
  Nav.I.current = Companion.I.exists ? 'home' : 'choose';
  runApp(const CalmApp());
}

class CalmApp extends StatelessWidget {
  const CalmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kAccent,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: kText,
          selectionColor: kAccent.withAlpha(90),
          selectionHandleColor: kAccent,
        ),
      ),
      home: const StageHost(),
    );
  }
}

Widget _buildScene(String name) {
  switch (name) {
    case 'choose':
      return const ChooseScene();
    case 'panic':
      return const PanicScene();
    case 'grounding':
      return const GroundingScene();
    case 'landing':
      return const LandingScene();
    case 'anxiety':
      return const AnxietyScene();
    case 'stress':
      return const StressScene();
    case 'positivity':
      return const PositivityScene();
    default:
      return const HomeScene();
  }
}

/// Shows the current scene on a fixed 900x600 stage, scaled to fit the window (letterboxed),
/// and fades softly on every scene change.
class StageHost extends StatefulWidget {
  const StageHost({super.key});

  @override
  State<StageHost> createState() => _StageHostState();
}

class _StageHostState extends State<StageHost> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _prev = Duration.zero;
  double _fade = 1.0; // 1.0 = fully covered, fades to 0

  @override
  void initState() {
    super.initState();
    Nav.I.addListener(_onNav);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    Nav.I.removeListener(_onNav);
    _ticker.dispose();
    super.dispose();
  }

  void _onNav() {
    setState(() => _fade = 1.0);
  }

  void _tick(Duration elapsed) {
    var dt = (elapsed - _prev).inMicroseconds / 1000000.0;
    _prev = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (_fade > 0) {
      setState(() => _fade = math.max(0.0, _fade - dt / 0.6)); // linear fade over 0.6 seconds
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = Nav.I.current;
    final cover = fadeColorFor(name);
    final visual = _fade * _fade; // ease the visual alpha: starts quick, settles gently
    return Scaffold(
      backgroundColor: cover,
      body: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: kW,
            height: kH,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  KeyedSubtree(key: ValueKey<int>(Nav.I.serial), child: _buildScene(name)),
                  if (_fade > 0)
                    IgnorePointer(child: ColoredBox(color: cover.withAlpha(a8(visual)))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
