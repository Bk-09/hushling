// All sounds are generated in code, so there is nothing to download (port of core/sound.py's
// numpy synthesis). Every function returns a ready-to-play 16-bit stereo WAV file as bytes.
// These are plain top-level functions so they can run in a background isolate (compute()).
import 'dart:math' as math;
import 'dart:typed_data';

const int kSR = 44100;

// ---------------------------------------------------------------- helpers
Uint8List _wav(Float64List left, Float64List right) {
  final n = left.length;
  final dataLen = n * 4;
  final b = ByteData(44 + dataLen);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 2, Endian.little); // stereo
  b.setUint32(24, kSR, Endian.little);
  b.setUint32(28, kSR * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  var o = 44;
  for (var i = 0; i < n; i++) {
    b.setInt16(o, _s16(left[i]), Endian.little);
    b.setInt16(o + 2, _s16(right[i]), Endian.little);
    o += 4;
  }
  return b.buffer.asUint8List();
}

int _s16(double v) {
  final x = v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v);
  return (x * 32000).round();
}

double _peakOf(Float64List a) {
  var p = 1e-9;
  for (var i = 0; i < a.length; i++) {
    final v = a[i].abs();
    if (v > p) p = v;
  }
  return p;
}

/// Scales both channels together so the loudest sample is [target].
void _peak(Float64List l, Float64List r, double target) {
  final p = math.max(_peakOf(l), _peakOf(r));
  final k = target / p;
  for (var i = 0; i < l.length; i++) {
    l[i] *= k;
    r[i] *= k;
  }
}

Float64List _gauss(int n, int seed) {
  final r = math.Random(seed);
  final o = Float64List(n);
  for (var i = 0; i < n; i += 2) {
    final u1 = 1.0 - r.nextDouble();
    final u2 = r.nextDouble();
    final m = math.sqrt(-2.0 * math.log(u1));
    o[i] = m * math.cos(2 * math.pi * u2);
    if (i + 1 < n) o[i + 1] = m * math.sin(2 * math.pi * u2);
  }
  return o;
}

/// In-place second-order filter. type 0 = low-pass, 1 = high-pass.
void _biquad(Float64List x, int type, double f0) {
  const q = 0.7071;
  final w0 = 2 * math.pi * f0 / kSR;
  final cw = math.cos(w0);
  final alpha = math.sin(w0) / (2 * q);
  final double b0, b1, b2;
  if (type == 0) {
    b0 = (1 - cw) / 2;
    b1 = 1 - cw;
    b2 = (1 - cw) / 2;
  } else {
    b0 = (1 + cw) / 2;
    b1 = -(1 + cw);
    b2 = (1 + cw) / 2;
  }
  final a0 = 1 + alpha;
  final nb0 = b0 / a0, nb1 = b1 / a0, nb2 = b2 / a0;
  final na1 = (-2 * cw) / a0, na2 = (1 - alpha) / a0;
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final y = nb0 * xi + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2;
    x2 = x1;
    x1 = xi;
    y2 = y1;
    y1 = y;
    x[i] = y;
  }
}

/// Band-limited noise with unit standard deviation (dark ... airy).
Float64List _bandNoise(int n, double lo, double hi, int seed) {
  final x = _gauss(n, seed);
  _biquad(x, 1, lo);
  _biquad(x, 0, hi);
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    s += x[i] * x[i];
  }
  final sd = math.sqrt(s / n) + 1e-9;
  for (var i = 0; i < n; i++) {
    x[i] /= sd;
  }
  return x;
}

double _easeP(double p) => 0.5 - 0.5 * math.cos(math.pi * p);

// ---------------------------------------------------------------- 1) soft breathing
const List<List<double>> _bands = [
  [120, 350], [350, 900], [900, 2200], [2200, 5000],
];

/// One whole breath (in + out) as a single sound, so there is never a click.
/// args = [inhale seconds, exhale seconds]
Uint8List buildBreath(List<double> args) {
  final inhale = args[0], exhale = args[1];
  final nIn = (kSR * inhale).toInt(), nOut = (kSR * exhale).toInt();
  final n = nIn + nOut;
  final level = Float64List(n);
  final bright = Float64List(n);
  final amp = Float64List(n);
  for (var i = 0; i < nIn; i++) {
    final up = _easeP(nIn > 1 ? i / (nIn - 1) : 1.0);
    level[i] = up;
    bright[i] = 0.10 + 0.70 * up;
    amp[i] = math.pow(up, 1.3).toDouble();
  }
  for (var j = 0; j < nOut; j++) {
    final down = 1.0 - _easeP(nOut > 1 ? j / (nOut - 1) : 1.0);
    final i = nIn + j;
    level[i] = down;
    bright[i] = 0.05 + 0.75 * math.pow(down, 1.6).toDouble();
    amp[i] = math.pow(down, 1.3).toDouble() * (0.85 + 0.15 * down); // the exhale is a little softer
  }
  const centres = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0];
  final weights = <Float64List>[];
  final norm = Float64List(n);
  for (var k = 0; k < 4; k++) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      final d = (centres[k] - bright[i]) / 0.35;
      w[i] = math.exp(-d * d);
      norm[i] += w[i] * w[i];
    }
    weights.add(w);
  }
  for (var i = 0; i < n; i++) {
    norm[i] = math.sqrt(norm[i]) + 1e-6;
  }
  final chans = <Float64List>[];
  for (final side in const [0, 10]) {
    final out = Float64List(n);
    for (var k = 0; k < 4; k++) {
      final noise = _bandNoise(n, _bands[k][0], _bands[k][1], 100 + side + k);
      final w = weights[k];
      for (var i = 0; i < n; i++) {
        out[i] += w[i] * noise[i];
      }
    }
    for (var i = 0; i < n; i++) {
      out[i] = out[i] / norm[i] * amp[i] * 0.22; // different noise left and right = wide, airy
    }
    chans.add(out);
  }
  return _wav(chans[0], chans[1]);
}

// ---------------------------------------------------------------- 2) soft little chime
Uint8List buildChime(List<double> freqs) {
  const length = 4.0;
  final n = (kSR * length).toInt();
  final out = Float64List(n);
  for (var i = 0; i < freqs.length; i++) {
    final f = freqs[i];
    final start = (i * 0.28 * kSR).toInt(); // notes arrive one after another
    for (var j = 0; j < n - start; j++) {
      final tt = j / kSR;
      final env = (1 - math.exp(-tt * 160)) * math.exp(-tt * 2.0);
      final s = math.sin(2 * math.pi * f * tt) +
          0.12 * math.sin(2 * math.pi * 2.76 * f * tt) * math.exp(-tt * 5) +
          0.05 * math.sin(2 * math.pi * 5.4 * f * tt) * math.exp(-tt * 9);
      out[start + j] += s * env;
    }
  }
  final k = 0.6 / _peakOf(out);
  for (var i = 0; i < n; i++) {
    out[i] *= k;
  }
  return _wav(out, Float64List.fromList(out));
}

// ---------------------------------------------------------------- 3) the landing lullaby (original)
const Map<String, double> _notes = {
  'F3': 174.61, 'G3': 196.00, 'A3': 220.00, 'B3': 246.94, 'C4': 261.63, 'D4': 293.66, 'E4': 329.63,
  'G4': 392.00, 'A4': 440.00, 'C5': 523.25, 'D5': 587.33, 'E5': 659.25, 'F5': 698.46,
  'G5': 783.99, 'A5': 880.00, 'C6': 1046.50,
};

const Map<String, List<String>> _arp = {
  'C': ['C4', 'E4', 'G4'],
  'Am': ['A3', 'C4', 'E4'],
  'F': ['F3', 'A3', 'C4'],
  'G': ['G3', 'B3', 'D4'],
};

const List<String> _prog = [
  'C', 'Am', 'F', 'G', 'C', 'Am', 'F', 'G',
  'C', 'Am', 'F', 'G', 'C', 'Am', 'G', 'C',
];

// 16 bars of 3 beats: (note, beat inside the bar, length in beats)
class _N {
  final String name;
  final double beat;
  final double dur;
  const _N(this.name, this.beat, this.dur);
}

const List<List<_N>> _melody = [
  [_N('E5', 0, 1), _N('G5', 1, 1), _N('E5', 2, 1)],
  [_N('C5', 0, 1.5), _N('E5', 1.5, .5), _N('D5', 2, 1)],
  [_N('C5', 0, 1), _N('A4', 1, 1), _N('C5', 2, 1)],
  [_N('D5', 0, 2), _N('E5', 2, 1)],
  [_N('G5', 0, 1), _N('E5', 1, 1), _N('C5', 2, 1)],
  [_N('A4', 0, 1), _N('C5', 1, 1), _N('E5', 2, 1)],
  [_N('A4', 0, 1), _N('C5', 1, .5), _N('D5', 1.5, .5), _N('C5', 2, 1)],
  [_N('D5', 0, 3)],
  [_N('E5', 0, .5), _N('G5', .5, .5), _N('C6', 1, 1), _N('G5', 2, 1)],
  [_N('A5', 0, 1), _N('G5', 1, .5), _N('E5', 1.5, .5), _N('C5', 2, 1)],
  [_N('A5', 0, 1), _N('F5', 1, 1), _N('A5', 2, 1)],
  [_N('D5', 0, 1), _N('G5', 1, 1), _N('D5', 2, 1)],
  [_N('E5', 0, 1), _N('G5', 1, 1), _N('E5', 2, 1)],
  [_N('C5', 0, 1), _N('E5', 1, 1), _N('A5', 2, 1)],
  [_N('D5', 0, 1), _N('E5', 1, 1), _N('D5', 2, 1)],
  [_N('C5', 0, 3)],
];

Float64List _bell(double freq, double amp, double decay, [double length = 3.2]) {
  final n = (kSR * length).toInt();
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / kSR;
    final env = (1 - math.exp(-t * 350)) * math.exp(-t * decay);
    final sig = math.sin(2 * math.pi * freq * t) +
        0.30 * math.sin(2 * math.pi * 2 * freq * t) * math.exp(-t * 3.5) +
        0.10 * math.sin(2 * math.pi * 4.02 * freq * t) * math.exp(-t * 9);
    o[i] = sig * env * amp;
  }
  return o;
}

/// Add a sound into a looping buffer; any tail wraps around to the start (seamless loop).
void _mixIn(Float64List buf, int start, Float64List sig) {
  final n = buf.length;
  final s = start % n;
  final first = math.min(sig.length, n - s);
  for (var i = 0; i < first; i++) {
    buf[s + i] += sig[i];
  }
  final rest = sig.length - first;
  for (var i = 0; i < rest; i++) {
    buf[i] += sig[first + i];
  }
}

/// The landing lullaby (about 37 seconds, loops seamlessly). [beatSeconds] = tempo.
Uint8List buildMusic(double beatSeconds) {
  final beat = beatSeconds;
  final n = (kSR * beat * 3 * _prog.length).toInt();
  final mix = Float64List(n);
  final cache = <String, Float64List>{};
  Float64List bell(String name, double amp, double decay) =>
      cache.putIfAbsent('$name|$amp|$decay', () => _bell(_notes[name]!, amp, decay));
  for (var bar = 0; bar < _prog.length; bar++) {
    final chord = _prog[bar];
    final barStart = bar * 3 * beat;
    final arp = _arp[chord]!;
    for (var k = 0; k < arp.length; k++) {
      // soft rolling accompaniment
      _mixIn(mix, ((barStart + k * beat) * kSR).toInt(), bell(arp[k], k == 0 ? 0.30 : 0.22, 2.6));
    }
    for (final note in _melody[bar]) {
      // the tune
      _mixIn(mix, ((barStart + note.beat * beat) * kSR).toInt(),
          bell(note.name, 0.60, note.dur >= 2 ? 1.5 : 2.6));
    }
  }
  final left = Float64List(n);
  final right = Float64List(n);
  final sl = (0.29 * kSR).toInt(), sr = (0.43 * kSR).toInt(); // a little shimmer
  for (var i = 0; i < n; i++) {
    left[i] = mix[i] + 0.22 * mix[(i - sl) % n];
    right[i] = mix[i] + 0.22 * mix[(i - sr) % n];
  }
  _peak(left, right, 0.6);
  return _wav(left, right);
}

// ---------------------------------------------------------------- 4) soft hush and water notes
/// Makes [x] loop without a click: the tail is crossfaded into the start (equal power).
Float64List _loopable(Float64List x, int fade) {
  final n = x.length - fade;
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    o[i] = x[i];
  }
  for (var i = 0; i < fade; i++) {
    final p = i / fade;
    o[i] = x[i] * math.sin(p * math.pi / 2) + x[n + i] * math.cos(p * math.pi / 2);
  }
  return o;
}

/// A very soft, airy hush (like gentle rain). Loops seamlessly. [duration] seconds.
Uint8List buildAmbient(double duration) {
  const fadeSeconds = 1.5;
  final fade = (kSR * fadeSeconds).toInt();
  final n = (kSR * duration).toInt() + fade;
  final chans = <Float64List>[];
  for (final side in const [0, 10]) {
    final low = _bandNoise(n, 350, 1400, 300 + side);
    final high = _bandNoise(n, 1400, 5000, 320 + side);
    final o = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i / kSR;
      final a = 0.60 + 0.40 * math.sin(2 * math.pi * (2 / duration) * t + side * 0.3);
      final b = 0.55 + 0.45 * math.sin(2 * math.pi * (3 / duration) * t + 1.0 + side);
      o[i] = low[i] * a * 0.70 + high[i] * b * 0.35;
    }
    chans.add(_loopable(o, fade));
  }
  _peak(chans[0], chans[1], 0.5);
  return _wav(chans[0], chans[1]);
}

/// One soft water-drop note. [pan] is -1 (left), 0 (centre) or 1 (right).
Uint8List buildPlink(double freq, double pan) {
  final sig = _bell(freq, 0.6, 2.2, 2.8);
  final k = 0.55 / _peakOf(sig);
  final ang = (pan.clamp(-1.0, 1.0) + 1.0) * math.pi / 4; // equal-power panning
  final gl = math.cos(ang), gr = math.sin(ang);
  final l = Float64List(sig.length), r = Float64List(sig.length);
  for (var i = 0; i < sig.length; i++) {
    l[i] = sig[i] * k * gl;
    r[i] = sig[i] * k * gr;
  }
  return _wav(l, r);
}
