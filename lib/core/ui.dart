// Shared widgets: buttons, text input, the per-frame loop that drives each scene, and the painter.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'palette.dart';
import 'sound.dart';
import 'util.dart';

/// A rounded button placed on the 900x600 stage (core/ui.py Button).
class CalmButton extends StatefulWidget {
  final Rect rect;
  final String title;
  final String subtitle;
  final Color color;
  final Color hoverColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback? onTap;
  final double titleSize;
  final double subSize;
  final bool pulse;

  const CalmButton({
    super.key,
    required this.rect,
    required this.title,
    this.subtitle = '',
    this.color = kCard,
    this.hoverColor = kCardHover,
    this.textColor = kText,
    this.subColor = kTextDim,
    this.onTap,
    this.titleSize = 30,
    this.subSize = 19,
    this.pulse = false,
  });

  @override
  State<CalmButton> createState() => _CalmButtonState();
}

class _CalmButtonState extends State<CalmButton> with SingleTickerProviderStateMixin {
  bool _hover = false;
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 3927))..repeat();
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  void _set(bool v) {
    if (_hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Positioned(
      left: w.rect.left,
      top: w.rect.top,
      width: w.rect.width,
      height: w.rect.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: w.onTap,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _hover ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (context, h, _) {
              Widget face = Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color.lerp(w.color, w.hoverColor, h),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(color: kText.withAlpha(46), blurRadius: 22, offset: Offset(0, 10 - 4 * h)),
                  ],
                ),
                child: w.subtitle.isEmpty
                    ? Text(w.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: TextAlign.center,
                        style: calmTextStyle(w.titleSize, bold: true, color: w.textColor))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(w.title,
                              maxLines: 1,
                              softWrap: false,
                              style: calmTextStyle(w.titleSize, bold: true, color: w.textColor)),
                          SizedBox(height: w.subSize * 0.55),
                          Text(w.subtitle,
                              maxLines: 1,
                              softWrap: false,
                              style: calmTextStyle(w.subSize, color: w.subColor)),
                        ],
                      ),
              );
              face = Transform.translate(offset: Offset(0, -5 * h), child: face);
              final pc = _pulse;
              if (pc != null) {
                return AnimatedBuilder(
                  animation: pc,
                  child: face,
                  builder: (context, child) =>
                      Transform.scale(scale: 1 + 0.012 * math.sin(pc.value * 2 * math.pi), child: child),
                );
              }
              return face;
            },
          ),
        ),
      ),
    );
  }
}

/// "Sound: on / off" toggle used on most screens.
class SoundButton extends StatefulWidget {
  final Rect rect;
  final Color color;
  final Color hoverColor;
  final Color textColor;
  const SoundButton({
    super.key,
    required this.rect,
    required this.color,
    required this.hoverColor,
    required this.textColor,
  });

  @override
  State<SoundButton> createState() => _SoundButtonState();
}

class _SoundButtonState extends State<SoundButton> {
  @override
  Widget build(BuildContext context) {
    return CalmButton(
      rect: widget.rect,
      title: Sound.enabled ? 'Sound: on' : 'Sound: off',
      color: widget.color,
      hoverColor: widget.hoverColor,
      textColor: widget.textColor,
      titleSize: 15,
      onTap: () {
        Sound.toggle();
        setState(() {});
      },
    );
  }
}

/// A text box on the stage. Uses a real TextField, so phone keyboards work too.
class CalmTextField extends StatelessWidget {
  final Rect rect;
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int maxLines;
  final double fontSize;
  final bool bold;
  final TextAlign align;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final EdgeInsets padding;
  final bool autofocus;

  const CalmTextField({
    super.key,
    required this.rect,
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
    this.fontSize = 24,
    this.bold = true,
    this.align = TextAlign.center,
    this.onSubmit,
    this.onChanged,
    this.padding = EdgeInsets.zero,
    this.autofocus = true,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: maxLines,
      textAlign: align,
      cursorColor: kText,
      textInputAction: TextInputAction.done,
      style: calmTextStyle(fontSize, bold: bold, color: kText),
      inputFormatters: [
        LengthLimitingTextInputFormatter(maxLength),
        if (maxLines > 1) FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
      ],
      onChanged: onChanged,
      onSubmitted: (_) => onSubmit?.call(),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: padding,
        hintText: hint,
        hintStyle: calmTextStyle(fontSize * 0.82, bold: false, color: kTextDim),
      ),
    );
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Align(
        alignment: maxLines > 1 ? Alignment.topLeft : Alignment.center,
        child: onSubmit == null
            ? field
            : CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.enter): onSubmit!,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): onSubmit!,
                },
                child: field,
              ),
      ),
    );
  }
}

/// Escape = go back (desktop keyboards). Also makes sure the scene can receive key events.
class EscScope extends StatelessWidget {
  final VoidCallback onEsc;
  final Widget child;
  const EscScope({super.key, required this.onEsc, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onEsc,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// Tells a CustomPaint to repaint every frame.
class FrameClock extends ChangeNotifier {
  void bump() => notifyListeners();
}

class ScenePainter extends CustomPainter {
  final void Function(Canvas canvas) fn;
  ScenePainter(this.fn, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    fn(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// The per-frame loop every scene uses: call startLoop() in initState and stopLoop() in dispose.
/// onTick(dt) is the Python update(dt); the painter callback is draw(). dt is capped at 0.05 s so a
/// hiccup never makes timers jump.
mixin SceneLoop<T extends StatefulWidget> on State<T> {
  Ticker? _ticker;
  Duration _prev = Duration.zero;
  final FrameClock frame = FrameClock();

  void onTick(double dt);

  void startLoop() {
    _ticker = Ticker((elapsed) {
      var dt = (elapsed - _prev).inMicroseconds / 1000000.0;
      _prev = elapsed;
      if (dt > 0.05) dt = 0.05;
      if (dt < 0) dt = 0;
      onTick(dt);
      frame.bump();
    })..start();
  }

  void stopLoop() {
    _ticker?.dispose();
    _ticker = null;
    frame.dispose();
  }

  Widget paintLayer(void Function(Canvas canvas) draw) =>
      CustomPaint(size: const Size(kW, kH), painter: ScenePainter(draw, frame));
}

/// Simple text button rects used by painters for hit-testing.
bool hit(Rect r, Offset p) => r.contains(p);
