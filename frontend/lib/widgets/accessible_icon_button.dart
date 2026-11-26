import 'package:flutter/material.dart';

import '../core/accessibility/accessibility_tokens.dart';

/// Icon button with required tooltip + semantics for screen readers (Audit 9).
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final Widget icon;
  final String semanticsLabel;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  factory AccessibleIconButton.back({
    Key? key,
    required VoidCallback? onPressed,
    String semanticsLabel = 'Go back',
    Color? color,
  }) {
    return AccessibleIconButton(
      key: key,
      icon: const Icon(Icons.arrow_back),
      semanticsLabel: semanticsLabel,
      tooltip: semanticsLabel,
      onPressed: onPressed,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: icon,
      color: color,
      tooltip: tooltip ?? semanticsLabel,
      constraints: const BoxConstraints(
        minWidth: AccessibilityTokens.minTapTarget,
        minHeight: AccessibilityTokens.minTapTarget,
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      child: button,
    );
  }
}