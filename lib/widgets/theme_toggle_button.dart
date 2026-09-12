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
            (isDark ? const Color(0xFFFDE047) : const Color(0xFF0F172A));
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
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => AppThemeController.instance.toggleTheme(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFFFDE047).withValues(alpha: 0.18)
                        : AppColors.patientTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? const Color(0xFFFDE047) : AppColors.patientTeal,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isDark ? const Color(0xFFFDE047) : AppColors.patientTeal)
                            .withValues(alpha: 0.25),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconWidget,
                      const SizedBox(width: 6),
                      Text(
                        isDark ? 'Dark' : 'Light',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFFDE047) : AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
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
