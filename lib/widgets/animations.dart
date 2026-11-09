import 'package:flutter/material.dart';

// Small, friendly animations used around the app.
//
// All of them turn themselves off when "Reduce animations" is on in Settings,
// or when the phone's own "remove animations" accessibility switch is on.
// The app root passes both through MediaQuery.disableAnimations.

bool animationsOff(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;

// A duration that becomes zero when animations are off.
Duration animationDuration(BuildContext context, int milliseconds) =>
    animationsOff(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

// A screen change: the new screen fades in while sliding in a little.
Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (animationsOff(context)) {
        return child;
      }
      final curve = CurveTween(curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: animation.drive(curve),
        child: SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).chain(curve),
          ),
          child: child,
        ),
      );
    },
  );
}

// Fades and floats a list item into place. Later items (higher "index")
// start a little slower, so a list appears one row after another.
class FadeSlideIn extends StatelessWidget {
  final int index;
  final Widget child;

  const FadeSlideIn({super.key, this.index = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    if (animationsOff(context)) {
      return child;
    }
    final milliseconds = 250 + (index > 8 ? 8 : index) * 60;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: milliseconds),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: child,
        ),
      ),
    );
  }
}

// A new chat bubble grows a little and fades in, from the side it belongs to.
class PopIn extends StatelessWidget {
  final Alignment alignment;
  final Widget child;

  const PopIn({super.key, required this.alignment, required this.child});

  @override
  Widget build(BuildContext context) {
    if (animationsOff(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * value,
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }
}

// The heart on the first screen, gently beating. It stays still when
// animations are off.
class BeatingHeart extends StatefulWidget {
  final double size;
  final Color color;

  const BeatingHeart({super.key, required this.size, required this.color});

  @override
  State<BeatingHeart> createState() => _BeatingHeartState();
}

class _BeatingHeartState extends State<BeatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: 1.14,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animationsOff(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(Icons.favorite, size: widget.size, color: widget.color),
    );
  }
}

// A soft glow around something that needs attention, like a room with new
// messages. It pulses gently. With animations off it is a steady highlight.
class GlowPulse extends StatefulWidget {
  final bool active;
  final Color color;
  final double radius;
  final Widget child;

  const GlowPulse({
    super.key,
    required this.active,
    required this.color,
    this.radius = 16,
    required this.child,
  });

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  // Starts the pulse only while it is needed, and stops it otherwise.
  void _sync() {
    final shouldPulse = widget.active && !animationsOff(context);
    if (shouldPulse) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          decoration: BoxDecoration(
            color: widget.color.withAlpha(24),
            borderRadius: radius,
            border: Border.all(
              color: widget.color.withAlpha((90 + 100 * t).round()),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha((50 + 90 * t).round()),
                blurRadius: 6 + 14 * t,
                spreadRadius: 0.5 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
