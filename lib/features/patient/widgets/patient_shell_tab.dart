import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import 'patient_screen_title_bar.dart';

/// Shell tab page: title, pill tabs, constrained body.
class PatientShellTabPage extends StatelessWidget {
  const PatientShellTabPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.tabController,
    required this.tabLabels,
    required this.tabBodies,
    this.accentColor = AppColors.patientTeal,
  });

  final String title;
  final String? subtitle;
  final TabController tabController;
  final List<String> tabLabels;
  final List<Widget> tabBodies;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);

    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: AppColors.surfaceOf(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PatientScreenTitleBar(title: title, subtitle: subtitle),
                PatientSegmentedTabBar(
                  controller: tabController,
                  labels: tabLabels,
                  accentColor: accentColor,
                ),
                Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: TabBarView(
                  controller: tabController,
                  children: tabBodies,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PatientSegmentedTabBar extends StatelessWidget {
  const PatientSegmentedTabBar({
    super.key,
    required this.controller,
    required this.labels,
    this.accentColor = AppColors.patientTeal,
  });

  final TabController controller;
  final List<String> labels;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final hPad = compact ? 16.0 : 20.0;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, compact ? 12 : 14),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: _SegmentTab(
                    label: labels[i],
                    selected: controller.index == i,
                    accentColor: accentColor,
                    onTap: () => controller.animateTo(i),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SegmentTab extends StatefulWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<_SegmentTab> createState() => _SegmentTabState();
}

class _SegmentTabState extends State<_SegmentTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final accent = widget.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent
                  : (_hovered ? accent.withValues(alpha: 0.08) : AppColors.cardBgOf(context)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? accent
                    : (_hovered ? accent.withValues(alpha: 0.35) : AppColors.borderOf(context)),
              ),
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.white : AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat list container used under shell tabs.
class PatientShellTabList extends StatelessWidget {
  const PatientShellTabList({
    super.key,
    required this.children,
    this.empty,
    this.onRefresh,
  });

  final List<Widget> children;
  final Widget? empty;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty && empty != null) {
      return ColoredBox(color: AppColors.surfaceOf(context), child: empty);
    }

    final list = ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );

    if (onRefresh == null) {
      return ColoredBox(color: AppColors.surfaceOf(context), child: list);
    }

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: RefreshIndicator(
        color: AppColors.patientTeal,
        onRefresh: onRefresh!,
        child: list,
      ),
    );
  }
}

class PatientTabEmptyState extends StatelessWidget {
  const PatientTabEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accentColor = AppColors.patientTeal,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: accentColor.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondaryOf(context),
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
