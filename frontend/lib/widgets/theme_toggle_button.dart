import 'package:flutter/material.dart';

import '../core/accessibility/accessibility_tokens.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme_controller.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({
    super.key,
    this.iconSize = 20,
    this.color,
    this.highlighted = true,
  });

  final double iconSize;
  final Color? color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final isDark = AppThemeController.instance.isDarkMode;
        final iconColor = color ??
            (highlighted
                ? AppColors.textPrimaryOf(context)
                : (isDark ? const Color(0xFFFDE047) : const Color(0xFF0F172A)));
        final tooltip = isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode';

        final iconWidget = AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: RotationTransition(turns: anim, child: child),
          ),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            key: ValueKey(isDark),
            color: iconColor,
            size: iconSize,
          ),
        );

        void toggleTheme() => AppThemeController.instance.toggleTheme();

        if (highlighted) {
          return Semantics(
            button: true,
            label: tooltip,
            child: Tooltip(
              message: tooltip,
              child: IconButton(
                onPressed: toggleTheme,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AccessibilityTokens.minTapTarget,
                  minHeight: AccessibilityTokens.minTapTarget,
                ),
                icon: iconWidget,
                color: iconColor,
                tooltip: tooltip,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.cardBgOf(context),
                  side: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
            ),
          );
        }

        return Semantics(
          button: true,
          label: tooltip,
          child: IconButton(
            icon: iconWidget,
            tooltip: tooltip,
            onPressed: toggleTheme,
          ),
        );
      },
    );
  }
}
