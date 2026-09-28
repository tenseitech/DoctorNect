import 'dart:async';

import 'package:flutter/material.dart';

/// Shared animated rotating placeholder used by both the Patient and Doctor
/// home search bars. Cycles through [placeholders] every [rotationInterval]
/// using a vertical slide + fade [AnimatedSwitcher] transition.
class RotatingSearchPlaceholder extends StatefulWidget {
  const RotatingSearchPlaceholder({
    super.key,
    required this.placeholders,
    required this.style,
    this.paused = false,
    this.ignorePointer = false,
    this.rotationInterval = const Duration(milliseconds: 2500),
    this.transitionDuration = const Duration(milliseconds: 400),
  }) : assert(placeholders.length > 0, 'placeholders must not be empty');

  final List<String> placeholders;
  final TextStyle style;
  final bool paused;
  final bool ignorePointer;
  final Duration rotationInterval;
  final Duration transitionDuration;

  @override
  State<RotatingSearchPlaceholder> createState() =>
      _RotatingSearchPlaceholderState();
}

class _RotatingSearchPlaceholderState extends State<RotatingSearchPlaceholder> {
  Timer? _rotationTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant RotatingSearchPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.placeholders.length != oldWidget.placeholders.length &&
        _currentIndex >= widget.placeholders.length) {
      _currentIndex = 0;
    }
    if (widget.paused != oldWidget.paused ||
        widget.rotationInterval != oldWidget.rotationInterval) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _stopTimer();
    if (widget.paused || widget.placeholders.length <= 1) return;
    _rotationTimer = Timer(widget.rotationInterval, () {
      if (!mounted || widget.paused) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.placeholders.length;
      });
      _syncTimer();
    });
  }

  void _stopTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.ignorePointer,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: widget.transitionDuration,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final isIncoming = child.key == ValueKey<int>(_currentIndex);
              final offsetTween = isIncoming
                  ? Tween<Offset>(
                      begin: const Offset(0.0, 0.8),
                      end: Offset.zero,
                    )
                  : Tween<Offset>(
                      begin: const Offset(0.0, -0.8),
                      end: Offset.zero,
                    );

              return SlideTransition(
                position: offsetTween.animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutCubic,
                  ),
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            layoutBuilder:
                (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: Text(
              widget.placeholders[_currentIndex],
              key: ValueKey<int>(_currentIndex),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}
