import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  // True for your own messages (swipe left), false for others (swipe right).
  final bool swipeLeft;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
    this.swipeLeft = false,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _triggerDistance = 64.0;
  static const _maxDistance = 90.0;

  late final AnimationController _backController;

  // How far the bubble has moved in the reply direction (never negative).
  double _distance = 0;
  double _releasedFrom = 0;
  bool _passedTrigger = false;

  @override
  void initState() {
    super.initState();
    _backController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          setState(() {
            _distance =
                _releasedFrom *
                (1 - Curves.easeOut.transform(_backController.value));
          });
        });
  }

  @override
  void dispose() {
    _backController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _backController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final direction = widget.swipeLeft ? -1 : 1;
    var delta = details.delta.dx * direction;
    // A little resistance once the trigger point is passed.
    if (_distance > _triggerDistance) {
      delta *= 0.5;
    }
    setState(() {
      _distance = (_distance + delta).clamp(0.0, _maxDistance).toDouble();
    });
    if (!_passedTrigger && _distance >= _triggerDistance) {
      _passedTrigger = true;
      HapticFeedback.mediumImpact();
    } else if (_passedTrigger && _distance < _triggerDistance) {
      _passedTrigger = false;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final shouldReply = _distance >= _triggerDistance;
    _passedTrigger = false;
    _releasedFrom = _distance;
    _backController.forward(from: 0);
    if (shouldReply) {
      widget.onReply();
    }
  }

  void _onDragCancel() {
    _passedTrigger = false;
    _releasedFrom = _distance;
    _backController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final colors = Theme.of(context).colorScheme;
    final progress = (_distance / _triggerDistance).clamp(0.0, 1.0).toDouble();
    final direction = widget.swipeLeft ? -1.0 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: Stack(
        alignment: widget.swipeLeft
            ? Alignment.centerRight
            : Alignment.centerLeft,
        children: [
          // The reply icon, revealed as the bubble moves away.
          Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.6 + 0.4 * progress,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.onSurface.withAlpha(24),
                ),
                child: Icon(
                  Icons.reply,
                  size: 18,
                  color: colors.onSurface.withAlpha(180),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(direction * _distance, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
