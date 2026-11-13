// Plays the sounds from synth.dart (port of the playing half of core/sound.py).
// Sounds are generated in code, cached in memory, written once to the temp folder and played
// with audioplayers. If anything audio-related fails (no device, unsupported platform), the app
// simply stays silent.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';
import 'synth.dart';

// ---- volume knobs (0.0 to 1.0) ----
const double kMasterVolume = 0.70; // one knob for everything: lower it if it is still too loud
const double kBreathVolume = 0.60;
const double kChimeVolume = 0.40;
const double kMusicVolume = 0.35;
const double kAmbientVolume = 0.20; // the soft hush in anxiety and stress mode (0 removes it)
const double kPlinkVolume = 0.38; // the notes when you tap the water

const double kMusicBeatSeconds = 0.78; // tempo of the landing lullaby (bigger = slower)
const double _ambientSeconds = 14.0;

// Top-level functions for compute() (they run on a background isolate).
Uint8List _bgBreath(List<double> a) => buildBreath(a);
Uint8List _bgChime(List<double> a) => buildChime(a);
Uint8List _bgMusic(double beat) => buildMusic(beat);
Uint8List _bgAmbient(double secs) => buildAmbient(secs);

class _Chan {
  AudioPlayer? _player;
  Timer? _fade;
  double _vol = 0.0;
  int _gen = 0;

  Future<void> play(Source src, double volume, {bool loop = false, int fadeInMs = 0}) async {
    _fade?.cancel();
    final gen = ++_gen;
    final p = _player ??= AudioPlayer();
    await p.stop();
    await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    _vol = fadeInMs > 0 ? 0.0 : volume;
    await p.setVolume(_vol);
    if (gen != _gen) return; // something newer started meanwhile
    await p.play(src);
    if (fadeInMs > 0) _ramp(volume, fadeInMs);
  }

  void _ramp(double target, int ms, {bool stopAtEnd = false}) {
    _fade?.cancel();
    final p = _player;
    if (p == null) return;
    const step = 50;
    final steps = (ms / step).ceil().clamp(1, 1000);
    final from = _vol;
    var i = 0;
    _fade = Timer.periodic(const Duration(milliseconds: step), (tm) {
      i++;
      _vol = from + (target - from) * (i / steps);
      p.setVolume(_vol < 0 ? 0.0 : (_vol > 1 ? 1.0 : _vol)).catchError((_) {});
      if (i >= steps) {
        tm.cancel();
        if (stopAtEnd) p.stop().catchError((_) {});
      }
    });
  }

  void fadeOutAndStop(int ms) {
    _gen++;
    if (_player == null) return;
    if (ms <= 0) {
      _fade?.cancel();
      _player!.stop().catchError((_) {});
    } else {
      _ramp(0.0, ms, stopAtEnd: true);
    }
  }

  void setVolume(double v) {
    _vol = v;
    _player?.setVolume(v).catchError((_) {});
  }
}

class Sound {
  static bool enabled = true;
  static String? _dir;
  static bool _ready = false;

  static final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  static final Map<String, Future<Uint8List>> _futures = <String, Future<Uint8List>>{};
  static final Map<String, Source> _sources = <String, Source>{};
  static int _fileCounter = 0;

  static final _Chan _breath = _Chan();
  static final _Chan _chime = _Chan();
  static final _Chan _music = _Chan();
  static final _Chan _ambient = _Chan();
  static final List<_Chan> _plinkChans = <_Chan>[_Chan(), _Chan(), _Chan()];
  static int _plinkI = 0;

  static bool _musicOn = false, _musicStarting = false;
  static bool _ambientOn = false, _ambientStarting = false;

  static Future<void> init() async {
    enabled = Store.getMap('prefs')?['sound'] != false;
    try {
      if (!kIsWeb) _dir = (await getTemporaryDirectory()).path;
    } catch (_) {
      _dir = null;
    }
    try {
      // let our sounds play together (e.g. the hush under the water notes)
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (_) {}
    _ready = true;
  }

  static bool toggle() {
    enabled = !enabled;
    Store.setMap('prefs', {'sound': enabled});
    if (!enabled) {
      _breath.fadeOutAndStop(250);
      _chime.fadeOutAndStop(250);
      _music.fadeOutAndStop(250);
      _ambient.fadeOutAndStop(250);
      for (final c in _plinkChans) {
        c.fadeOutAndStop(250);
      }
      _musicOn = false;
      _ambientOn = false;
    }
    return enabled;
  }

  // ---------------------------------------------------------------- caching
  static Future<Uint8List> _get(String key, Future<Uint8List> Function() build) {
    return _futures.putIfAbsent(key, () async {
      final b = await build();
      _bytes[key] = b;
      return b;
    });
  }

  static void _warm(String key, Future<Uint8List> Function() build) {
    _get(key, build).then((_) {}, onError: (_) {});
  }

  static Future<Source?> _source(String key, Uint8List bytes) async {
    final hit = _sources[key];
    if (hit != null) return hit;
    try {
      Source s;
      if (kIsWeb || _dir == null) {
        s = BytesSource(bytes);
      } else {
        final f = File('$_dir/calm_sound_${_fileCounter++}.wav');
        await f.writeAsBytes(bytes, flush: true);
        s = DeviceFileSource(f.path);
      }
      _sources[key] = s;
      return s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _playOn(_Chan ch, String key, Future<Uint8List> Function() build, double volume,
      {bool loop = false, int fadeInMs = 0}) async {
    try {
      final bytes = await _get(key, build);
      if (!enabled) return;
      final src = await _source(key, bytes);
      if (src == null || !enabled) return;
      await ch.play(src, volume, loop: loop, fadeInMs: fadeInMs);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 1) breathing
  static String _breathKey(double i, double e) => 'breath|$i|$e';

  /// Pre-build the breath sounds in the background so nothing stutters later.
  static void warmBreath(double inhale, List<double> exhales) {
    for (final e in exhales) {
      _warm(_breathKey(inhale, e), () => compute(_bgBreath, <double>[inhale, e]));
    }
  }

  static void playCycle(double inhale, double exhale) {
    if (!enabled || !_ready) return;
    _playOn(_breath, _breathKey(inhale, exhale), () => compute(_bgBreath, <double>[inhale, exhale]),
        kBreathVolume * kMasterVolume);
  }

  static void stopBreath([int fadeMs = 400]) => _breath.fadeOutAndStop(fadeMs);

  // ---------------------------------------------------------------- 2) chime
  static void chime(List<double> freqs) {
    if (!enabled || !_ready) return;
    _playOn(_chime, 'chime|${freqs.join(',')}', () => compute(_bgChime, List<double>.from(freqs)),
        kChimeVolume * kMasterVolume);
  }

  // ---------------------------------------------------------------- 3) lullaby
  static void warmMusic() {
    if (_ready) _warm('music', () => compute(_bgMusic, kMusicBeatSeconds));
  }

  /// Call every frame while the lullaby should be playing. Starts it if needed.
  static void ensureMusic() {
    if (!enabled || !_ready || _musicOn || _musicStarting) return;
    if (!_bytes.containsKey('music')) {
      warmMusic(); // starts on a later frame, once it is ready
      return;
    }
    _musicStarting = true;
    _playOn(_music, 'music', () => compute(_bgMusic, kMusicBeatSeconds), kMusicVolume * kMasterVolume,
            loop: true, fadeInMs: 3000)
        .whenComplete(() {
      _musicStarting = false;
      _musicOn = true;
    });
  }

  static void stopMusic([int fadeMs = 1500]) {
    _music.fadeOutAndStop(fadeMs);
    _musicOn = false;
  }

  // ---------------------------------------------------------------- 4) hush and water notes
  static void warmAmbient() {
    if (_ready) _warm('ambient', () => compute(_bgAmbient, _ambientSeconds));
  }

  /// Call every frame while the soft hush should be playing.
  static void ensureAmbient() {
    if (!enabled || !_ready || _ambientOn || _ambientStarting) return;
    if (!_bytes.containsKey('ambient')) {
      warmAmbient();
      return;
    }
    _ambientStarting = true;
    _playOn(_ambient, 'ambient', () => compute(_bgAmbient, _ambientSeconds), kAmbientVolume * kMasterVolume,
            loop: true, fadeInMs: 4000)
        .whenComplete(() {
      _ambientStarting = false;
      _ambientOn = true;
    });
  }

  static void stopAmbient([int fadeMs = 1500]) {
    _ambient.fadeOutAndStop(fadeMs);
    _ambientOn = false;
  }

  /// One soft water-drop note. [pan]: -1 (left) .. 1 (right).
  static void plink(double freq, {double pan = 0.0, double vol = 1.0}) {
    if (!enabled || !_ready) return;
    final bucket = pan < -0.33 ? -1.0 : (pan > 0.33 ? 1.0 : 0.0);
    final key = 'plink|${freq.toStringAsFixed(2)}|$bucket';
    final ch = _plinkChans[_plinkI % _plinkChans.length];
    _plinkI++;
    final v = kPlinkVolume * kMasterVolume * vol * 1.414;
    _playOn(ch, key, () async => buildPlink(freq, bucket), v > 1.0 ? 1.0 : v);
  }
}
