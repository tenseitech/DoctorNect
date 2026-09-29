import 'package:flutter/material.dart';

/// Slide-up + fade route used when expanding the intro mobile field into the full auth screen.
class UnifiedAuthExpandRoute<T> extends PageRouteBuilder<T> {
  UnifiedAuthExpandRoute({required this.screen})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
              reverseCurve: Curves.easeInOutCubic,
            );
            return FadeTransition(
              opacity: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );

  final Widget screen;
}
