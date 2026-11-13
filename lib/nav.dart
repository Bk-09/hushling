// Which screen is showing (replaces SceneManager.switch in the Python app).
import 'package:flutter/material.dart';

import 'core/palette.dart';

class Nav extends ChangeNotifier {
  Nav._();
  static final Nav I = Nav._();

  String current = 'home';
  int serial = 0;

  /// Switch screen. Every switch starts the new screen fresh and fades in softly.
  void go(String name) {
    current = name;
    serial++;
    notifyListeners();
  }
}

/// The colour the screen fades in from (each scene's fade_color in Python).
Color fadeColorFor(String scene) {
  switch (scene) {
    case 'panic':
    case 'grounding':
    case 'landing':
      return kDuskTop;
    case 'anxiety':
      return const Color(0xFF7068B0);
    default:
      return kBg;
  }
}
