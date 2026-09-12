import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

/// Icon + text row that avoids horizontal overflow on narrow screens.
class SafeIconTextRow extends StatelessWidget {
  const SafeIconTextRow({
    super.key,
    required this.icon,
    required this.text,
    this.iconSize = 14,
    this.iconColor,
    this.style,
    this.maxLines = 2,
    this.mainAxisAlignment = MainAxisAlignment.center,
  });

  final IconData icon;
  final String text;
  final double iconSize;
  final Color? iconColor;
  final TextStyle? style;
  final int maxLines;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      children: [
        Icon(icon, size: iconSize, color: iconColor ?? AppColors.textSecondaryOf(context)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style ??
                GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
          ),
        ),
      ],
    );
  }
}

/// Bottom navigation label that scales down instead of overflowing.
class SafeBottomNavLabel extends StatelessWidget {
  const SafeBottomNavLabel({
    super.key,
    required this.label,
    required this.style,
    this.maxLines = 2,
  });

  final String label;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}

/// Shortens long bottom-nav labels on very narrow tabs.
String compactBottomNavLabel(String label) {
  return switch (label) {
    'Medical Store' => 'Medical\nStore',
    'Prescriptions' => 'Rx',
    'Notifications' => 'Alerts',
    'Appointments' => 'Appointments',
    'Diagnostic Lab Login' => 'Lab',
    _ => label,
  };
}

/// Constrains dialog body height and scrolls when content overflows.
Widget scrollableDialogContent({
  required BuildContext context,
  required Widget child,
  double maxHeightFraction = 0.7,
}) {
  final media = MediaQuery.of(context);
  final maxHeight = media.size.height * maxHeightFraction;
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: child,
    ),
  );
}

/// Modal bottom sheet with scroll-safe height and keyboard inset padding.
Future<T?> showScrollableModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  double maxHeightFraction = 0.85,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction,
    ),
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: builder(ctx),
      );
    },
  );
}
