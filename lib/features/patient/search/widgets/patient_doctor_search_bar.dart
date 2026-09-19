import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class PatientDoctorSearchBar extends StatefulWidget {
  const PatientDoctorSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.hintText = 'Search doctors by name, speciality, city…',
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String hintText;
  final Widget? trailing;

  @override
  State<PatientDoctorSearchBar> createState() => _PatientDoctorSearchBarState();
}

class _PatientDoctorSearchBarState extends State<PatientDoctorSearchBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);

    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: compact ? 50 : 54,
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? AppColors.patientTeal.withValues(alpha: 0.55)
                    : AppColors.borderOf(context),
                width: _focused ? 1.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.patientTeal.withValues(alpha: 0.1),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: _focused
                      ? AppColors.patientTeal
                      : AppColors.textSecondaryOf(context),
                  size: 22,
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    autofocus: widget.autofocus,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textPrimaryOf(context),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: widget.hintText,
                      hintStyle: GoogleFonts.inter(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    if (widget.controller.text.isEmpty)
                      return const SizedBox.shrink();
                    return IconButton(
                      onPressed: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                        widget.onSubmitted?.call('');
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppColors.textSecondaryOf(context)
                            .withValues(alpha: 0.75),
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Clear',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (widget.trailing != null) ...[
          SizedBox(width: compact ? 10 : 12),
          widget.trailing!,
        ],
      ],
    );
  }
}

class SearchFilterButton extends StatefulWidget {
  const SearchFilterButton({
    super.key,
    required this.onTap,
    this.activeCount = 0,
  });

  final VoidCallback onTap;
  final int activeCount;

  @override
  State<SearchFilterButton> createState() => _SearchFilterButtonState();
}

class _SearchFilterButtonState extends State<SearchFilterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final hasActive = widget.activeCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: compact ? 50 : 54,
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
            decoration: BoxDecoration(
              color: hasActive
                  ? AppColors.patientTeal.withValues(alpha: 0.1)
                  : (_hovered ? AppColors.cardBgOf(context) : AppColors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasActive || _hovered
                    ? AppColors.patientTeal.withValues(alpha: 0.45)
                    : AppColors.borderOf(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: hasActive
                      ? AppColors.patientTeal
                      : AppColors.textSecondaryOf(context),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Filters',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                      color: hasActive
                          ? AppColors.patientTeal
                          : AppColors.textPrimaryOf(context),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 6),
                  Text(
                    'Filter',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                      color: hasActive
                          ? AppColors.patientTeal
                          : AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
                if (hasActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.patientTeal,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.activeCount}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.surfaceOf(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
