// Stage size, now per screen shape.
//
// The Python layouts were all designed on a landscape 900x600 stage (kW x kH). Portrait screens use a
// 600-wide stage whose height follows the screen shape (600 x kPMinH..kPMaxH).
//
// A scene is "portrait-ready" once it appears in kPortraitScenes. Ready scenes get the tall stage
// whenever the window/phone is taller than wide; every other scene keeps the landscape stage
// (letterboxed), so you can convert the app one screen at a time.
import 'palette.dart';

/// Scenes that have a portrait layout. Add a scene name here when its portrait layout is done.
const Set<String> kPortraitScenes = <String>{
  'home', 'panic', 'grounding', 'landing', 'choose', 'stress', 'anxiety', 'positivity',
};

const double kPW = 600;
const double kPMinH = 1000; // wide-ish tablets and small windows
const double kPMaxH = 1300; // very tall phones (about 20:9)

class Layout {
  /// True while the current scene is shown on the tall stage.
  static bool portrait = false;

  /// Size of the stage the current scene is drawn on. Scenes should use these instead of kW / kH
  /// in any code that has a portrait layout.
  static double w = kW;
  static double h = kH;
}
