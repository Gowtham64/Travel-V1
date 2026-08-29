import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

/// Shared cinematic design system for the app.
///
/// Provides the brand palette, the frosted-glass card, an animated
/// (Ken-Burns) background, and a staggered "reveal one step at a time"
/// entrance animation used across all internal pages.
class AppColors {
  static const Color accent = Color(0xFF2E75B6);
  static const Color accentLight = Color(0xFF60A5FA);
  static const Color slate = Color(0xFF1E293B);
  static const Color obsidian = Color(0xFF0F172A);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Apple-style "liquid glass" surface: heavy backdrop blur + saturation, a
/// glossy top sheen, a bright rim highlight, an accent glow, and a slow
/// animated light sweep that gives the surface a living, liquid quality.
class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  /// When false, the moving highlight is disabled (static gloss only).
  final bool animate;

  /// When true, adds a soft accent-colored outer glow.
  final bool glow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24.0),
    this.radius = 24,
    this.blur = 22,
    this.animate = true,
    this.glow = true,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    if (widget.animate) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          // Depth shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 30,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
          // Accent glow
          if (widget.glow)
            BoxShadow(
              color: AppColors.accent.withOpacity(0.20),
              blurRadius: 28,
              spreadRadius: -10,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          // Blur + gentle saturation boost = liquid-glass refraction feel.
          filter: ImageFilter.compose(
            outer: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
            inner: const ColorFilter.matrix(<double>[
              1.35, -0.18, -0.18, 0, 6, //
              -0.13, 1.30, -0.13, 0, 6, //
              -0.18, -0.18, 1.35, 0, 6, //
              0, 0, 0, 1, 0, //
            ]),
          ),
          child: Stack(
            children: [
              // Base translucent fill
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.16),
                        Colors.white.withOpacity(0.04),
                      ],
                    ),
                    borderRadius: r,
                  ),
                ),
              ),
              // Glossy top sheen
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.white.withOpacity(0.22),
                          Colors.white.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Animated diagonal light sweep
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) {
                      // Slide a soft highlight band across the surface.
                      final p = _sweep.value; // 0..1
                      final dx = -1.4 + 3.2 * p;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: r,
                          gradient: LinearGradient(
                            begin: Alignment(dx - 0.4, -1),
                            end: Alignment(dx + 0.4, 1),
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.10),
                              Colors.white.withOpacity(0.0),
                            ],
                            stops: const [0.35, 0.5, 0.65],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Bright rim highlight (top-left brighter than bottom-right)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.28),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-bleed background image with a slow Ken-Burns zoom/pan and a
/// darkening overlay. The gentle motion gives every page a "living"
/// cinematic feel without distracting from the content.
class AnimatedBackground extends StatefulWidget {
  final String imageUrl;
  final double overlayOpacity;
  final Widget child;

  const AnimatedBackground({
    super.key,
    required this.imageUrl,
    this.overlayOpacity = 0.5,
    required this.child,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 34),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_controller.value);
              final scale = 1.04 + 0.035 * t;
              return Transform.scale(
                scale: scale,
                alignment: Alignment(-0.3 + 0.6 * t, -0.2 + 0.4 * t),
                child: child,
              );
            },
            child: Image.network(widget.imageUrl, fit: BoxFit.cover),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(widget.overlayOpacity * 0.7),
                  Colors.black.withOpacity(widget.overlayOpacity),
                ],
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Fades + slides a widget into place after an optional [delay].
///
/// Drop these into a Column/ListView with increasing delays to get the
/// "reveal one simple step at a time" staggered entrance.
class RevealIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final double offsetX;

  const RevealIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.offsetY = 28,
    this.offsetX = 0,
  });

  /// Convenience: build a list of children each revealed [step] later than
  /// the previous one.
  static List<Widget> stagger(
    List<Widget> children, {
    Duration step = const Duration(milliseconds: 55),
    Duration initial = const Duration(milliseconds: 50),
    double offsetY = 28,
  }) {
    return [
      for (int i = 0; i < children.length; i++)
        RevealIn(
          delay: initial + step * i,
          offsetY: offsetY,
          child: children[i],
        ),
    ];
  }

  @override
  State<RevealIn> createState() => _RevealInState();
}

class _RevealInState extends State<RevealIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final v = _anim.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(
              widget.offsetX * (1 - v),
              widget.offsetY * (1 - v),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A pill-shaped primary button that gently scales on press — the shared
/// call-to-action across pages.
class AccentButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AccentButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 18),
    this.radius = 16,
  });

  @override
  State<AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<AccentButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled
                ? AppColors.accentGradient
                : LinearGradient(colors: [
                    Colors.grey.shade700,
                    Colors.grey.shade800,
                  ]),
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
