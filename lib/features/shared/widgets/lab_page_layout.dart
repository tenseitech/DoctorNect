import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class LabPageLayout extends StatelessWidget {
  const LabPageLayout({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  static PreferredSizeWidget appBar(BuildContext context, {required String title, VoidCallback? onBack, List<Widget>? actions}) {
    return AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack) : null,
      actions: actions,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  static double contentWidth(BuildContext context) => 720.0;
  
  static BoxDecoration cardDecoration([BuildContext? context]) {
    return BoxDecoration(
      color: context != null ? AppColors.surfaceOf(context) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context != null ? AppColors.borderOf(context) : Colors.grey.shade200),
      boxShadow: context != null
          ? AppColors.cardShadowOf(context)
          : const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
    );
  }
}

class LabPageBody extends StatelessWidget {
  const LabPageBody({super.key, required this.child, this.centerVertically = false});
  final Widget child;
  final bool centerVertically;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (centerVertically) {
      content = Center(child: child);
    }
    return LabPageLayout(child: content);
  }
}

class LabContentCard extends StatelessWidget {
  const LabContentCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: LabPageLayout.cardDecoration(context),
      padding: padding ?? const EdgeInsets.all(24),
      child: child,
    );
  }
}

class LabPrimaryButton extends StatelessWidget {
  const LabPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.enabled = true});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: (loading || !enabled) ? null : onPressed,
        child: loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class LabSectionHeader extends StatelessWidget {
  const LabSectionHeader({super.key, required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 16),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
