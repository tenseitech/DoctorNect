import 'package:flutter/material.dart';
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
            child: RotationTransition(
              turns: anim,
              child: child,
            ),
          ),
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            key: ValueKey(isDark),
            color: iconColor,
            size: iconSize,
          ),
        );

        if (highlighted) {
          return Tooltip(
            message: tooltip,
            child: IconButton(
              onPressed: () => AppThemeController.instance.toggleTheme(),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: iconWidget,
              color: iconColor,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cardBgOf(context),
                side: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
          );
        }

        return IconButton(
          icon: iconWidget,
          tooltip: tooltip,
          onPressed: () => AppThemeController.instance.toggleTheme(),
        );
      },
    );
  }
}
