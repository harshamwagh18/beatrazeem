import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The six core colors match the light and dark Beatrazeem palettes.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.accent,
    required this.secondary,
    required this.text,
    required this.muted,
    required this.onAccent,
  });

  static const light = AppPalette(
    background: Color(0xffffffff),
    surface: Color(0xfff5f5f7),
    accent: Color(0xff7c3aed),
    secondary: Color(0xffddd6fe),
    text: Color(0xff18181b),
    muted: Color(0xff71717a),
    onAccent: Color(0xffffffff),
  );
  static const dark = AppPalette(
    background: Color(0xff121216),
    surface: Color(0xff1e1e24),
    accent: Color(0xff7c3aed),
    secondary: Color(0xffddd6fe),
    text: Color(0xfff4f4f5),
    muted: Color(0xffa1a1aa),
    onAccent: Color(0xffffffff),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppPalette(
      background: theme.scaffoldBackgroundColor,
      surface: colors.surface,
      accent: colors.primary,
      secondary: colors.secondary,
      text: colors.onSurface,
      muted: colors.onSurfaceVariant,
      onAccent: colors.onPrimary,
    );
  }

  final Color background;
  final Color surface;
  final Color accent;
  final Color secondary;
  final Color text;
  final Color muted;
  final Color onAccent;

  // Keep small accent labels legible against dark surfaces.
  Color get accentText =>
      background.computeLuminance() < .5 ? secondary : accent;

  Color get line => Color.alphaBlend(text.withValues(alpha: .09), surface);
  Color get tint => Color.alphaBlend(accent.withValues(alpha: .12), surface);

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      background == other.background &&
      surface == other.surface &&
      accent == other.accent &&
      secondary == other.secondary &&
      text == other.text &&
      muted == other.muted &&
      onAccent == other.onAccent;

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    accent,
    secondary,
    text,
    muted,
    onAccent,
  );
}

ThemeData beatrazeemTheme({Brightness brightness = Brightness.dark}) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final base = ThemeData(
    brightness: brightness,
    fontFamily: 'sans-serif',
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.accent,
          onPrimary: p.onAccent,
          primaryContainer: p.tint,
          onPrimaryContainer: p.text,
          secondary: p.secondary,
          onSecondary: const Color(0xff18181b),
          secondaryContainer: p.tint,
          onSecondaryContainer: p.text,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          outline: p.line,
          outlineVariant: p.line,
          surfaceContainerHighest: p.tint,
        ),
    textTheme: base.textTheme
        .apply(bodyColor: p.text, displayColor: p.text)
        .copyWith(
          bodyMedium: base.textTheme.bodyMedium!.copyWith(
            color: p.text,
            height: 1.45,
          ),
          bodySmall: base.textTheme.bodySmall!.copyWith(
            color: p.muted,
            height: 1.5,
          ),
        ),
    iconTheme: IconThemeData(color: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.accent, width: 1.6),
      ),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.muted),
      counterStyle: TextStyle(color: p.muted),
      prefixIconColor: p.accent,
      suffixIconColor: p.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(double.infinity, 58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontFamily: 'sans-serif',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        foregroundColor: p.text,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accentText),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: p.accent,
      thumbColor: p.accent,
      inactiveTrackColor: p.line,
      overlayColor: p.accent.withValues(alpha: .12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? p.onAccent : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? p.accent : p.surface,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? p.accent : p.line,
      ),
    ),
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: .25),
      selectionHandleColor: p.accent,
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.color,
    this.padding = 20,
  });
  final Widget child;
  final Color? color;
  final double padding;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: color ?? p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.line),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.graphic_eq_rounded, color: p.onAccent, size: 25),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'beatrazeem',
              style: TextStyle(
                color: p.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -.9,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class InitialAvatar extends StatelessWidget {
  const InitialAvatar(
    this.name, {
    super.key,
    this.host = false,
    this.size = 42,
  });
  final String name;
  final bool host;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .34),
        color: host ? p.accent : p.tint,
        border: Border.all(color: host ? p.accent : p.line),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: host ? p.onAccent : p.accentText,
          fontWeight: FontWeight.w800,
          fontSize: size * .38,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.active = false});
  final String text;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: active ? p.tint : p.background,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: active ? p.accent.withValues(alpha: .25) : p.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: active ? p.accent : p.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: active ? p.accentText : p.muted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A local painter animates the signal core without rebuilding screen content.
class SignalArt extends StatefulWidget {
  const SignalArt({super.key, this.height = 200});
  final double height;

  @override
  State<SignalArt> createState() => _SignalArtState();
}

class _SignalArtState extends State<SignalArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
    value: .12,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _orbit.stop();
      _orbit.value = .12;
    } else if (!_orbit.isAnimating) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SignalPainter(AppPalette.of(context), _orbit),
        ),
      ),
    ),
  );
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(this.palette, this.orbit) : super(repaint: orbit);
  final AppPalette palette;
  final Animation<double> orbit;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final c = Offset(size.width / 2, size.height * .51);
    final r = math.min(size.width * .245, size.height * .31);
    final phase = orbit.value * math.pi * 2;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            p.accent.withValues(alpha: .16),
            p.accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 2.05)),
    );
    final dot = Paint()..color = p.muted.withValues(alpha: .15);
    for (var column = 0; column < 13; column++) {
      for (var row = 0; row < 5; row++) {
        final point = Offset(
          size.width * .08 + column * size.width * .07,
          size.height * .12 + row * size.height * .19,
        );
        if ((point - c).distance > r * 1.25) {
          canvas.drawCircle(point, .9, dot);
        }
      }
    }

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-.30);
    final ellipse = Rect.fromCenter(
      center: Offset.zero,
      width: r * 3.55,
      height: r * 1.76,
    );
    canvas.drawOval(
      ellipse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = p.accent.withValues(alpha: .24),
    );
    canvas.drawArc(
      ellipse,
      phase,
      .68,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = p.accent.withValues(alpha: .75),
    );
    final satellite = Offset(
      math.cos(phase + .68) * ellipse.width / 2,
      math.sin(phase + .68) * ellipse.height / 2,
    );
    canvas.drawCircle(satellite, 8, Paint()..color = p.tint);
    canvas.drawCircle(satellite, 3, Paint()..color = p.accent);
    canvas.restore();

    canvas.drawCircle(
      c,
      r * 1.20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = p.accent.withValues(alpha: .16),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 1.20),
      -phase * .5,
      1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = p.secondary.withValues(alpha: .75),
    );
    final core = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c + Offset(0, r * .08),
      r,
      Paint()
        ..color = p.accent.withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.tint, p.surface, p.background],
        ).createShader(core),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.accent.withValues(alpha: .7),
            p.accent.withValues(alpha: .08),
          ],
        ).createShader(core),
    );
    canvas.drawCircle(
      c,
      r * .84,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = p.accent.withValues(alpha: .10),
    );
    for (var i = 0; i < 15; i++) {
      final x = (i - 7) * r * .087;
      final taper = 1 - (i - 7).abs() / 10;
      final wave = math.sin(i * .72 + phase * 2).abs();
      final h = r * (.14 + (.30 + wave * .30) * taper);
      final bar = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c + Offset(x, 0), width: r * .038, height: h),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        bar,
        Paint()..color = Color.lerp(p.accent, p.secondary, i / 22)!,
      );
    }
    canvas.drawCircle(
      c + Offset(r * .97, -r * .86),
      4.5,
      Paint()..color = p.secondary,
    );
    canvas.drawCircle(
      c + Offset(-r * 1.34, r * .73),
      2.5,
      Paint()..color = p.accent.withValues(alpha: .65),
    );
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.orbit != orbit;
}

class SoundWave extends StatefulWidget {
  const SoundWave({super.key, required this.level, required this.active});
  final double level;
  final bool active;

  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave> with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
    value: .2,
  );
  late final AnimationController _amplitude = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: widget.level.clamp(0, 1),
  );
  late final Listenable _repaint = Listenable.merge([_phase, _amplitude]);
  bool _motion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant SoundWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      final level = widget.level.clamp(0.0, 1.0);
      if (_motion && widget.active) {
        _amplitude.animateTo(level, curve: Curves.easeOutCubic);
      } else {
        _amplitude.value = level;
      }
    }
    _syncMotion();
  }

  void _syncMotion() {
    if (_motion && widget.active) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
      _phase.value = .2;
      _amplitude.stop();
      _amplitude.value = widget.level.clamp(0, 1);
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amplitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            palette: AppPalette.of(context),
            active: widget.active,
            phase: _phase,
            amplitude: _amplitude,
            repaint: _repaint,
          ),
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.palette,
    required this.active,
    required this.phase,
    required this.amplitude,
    required Listenable repaint,
  }) : super(repaint: repaint);
  final AppPalette palette;
  final bool active;
  final Animation<double> phase;
  final Animation<double> amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 43;
    final spacing = size.width / bars;
    final width = (spacing * .37).clamp(2.0, 4.0);
    final level = amplitude.value;
    final time = phase.value * math.pi * 2;
    for (var i = 0; i < bars; i++) {
      final envelope = .30 + .70 * math.sin(i / (bars - 1) * math.pi);
      final wave = math.sin(i * .67 + time).abs();
      final h = active
          ? 3 +
                (size.height - 8) *
                    envelope *
                    (.08 + level * .92) *
                    (.30 + wave * .70)
          : 3 + 7 * envelope * math.sin(i * .48).abs();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(spacing * (i + .5), size.height / 2),
            width: width,
            height: h,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = active
              ? palette.accent.withValues(alpha: .5 + wave * .5)
              : palette.muted.withValues(alpha: .34 + wave * .15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.active != active ||
      oldDelegate.phase != phase ||
      oldDelegate.amplitude != amplitude;
}

/// Finite entrance motion, with an immediate presentation for reduced motion.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 580),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _position = Tween<Offset>(
    begin: const Offset(0, .055),
    end: Offset.zero,
  ).animate(_curve);
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _delay?.cancel();
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        _delay = Timer(widget.delay, () {
          if (mounted) _controller.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _position, child: widget.child),
  );
}
