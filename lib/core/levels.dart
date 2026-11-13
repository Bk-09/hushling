// Gentle / Deeper level per mode (core/levels.py).
import 'store.dart';

class Levels {
  static const List<String> names = ['Gentle', 'Deeper'];
  static const String _key = 'levels';

  static int get(String mode) {
    final v = Store.getMap(_key)?[mode];
    return (v == 0 || v == 1) ? v as int : 0;
  }

  static int toggle(String mode) {
    final d = Store.getMap(_key) ?? <String, dynamic>{};
    final next = 1 - get(mode);
    d[mode] = next;
    Store.setMap(_key, d);
    return next;
  }

  static String name(int level) => names[level];
}
