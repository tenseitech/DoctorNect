import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';

class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({
    super.key,
    required this.onTap,
    this.onCategoryTap,
  });

  final VoidCallback onTap;
  final ValueChanged<String>? onCategoryTap;

  static const _quickCategories = [
    'General Physician',
    'Dentist',
    'Skin Specialist',
    'Heart Specialist',
    'Eye Specialist',
  ];

  static String placeholder({required bool compact}) {
    return compact
        ? 'Search doctors, lab, specialities…'
        : 'Doctor, lab, speciality, location, language…';
  }

  static String placeholderFor(BuildContext context) {
    return placeholder(compact: ResponsiveLayout.isCompact(context));
  }

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final placeholder = HomeSearchBar.placeholder(compact: compact);
    final active = _pressed || _hovered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(
          compact: compact,
          placeholder: placeholder,
          active: active,
          onTap: widget.onTap,
          onHoverChanged: (value) => setState(() => _hovered = value),
          onPressedChanged: (value) => setState(() => _pressed = value),
        ),
        if (widget.onCategoryTap != null) ...[
          SizedBox(height: compact ? 10 : 14),
          _QuickCategoriesRow(
            compact: compact,
            onCategoryTap: widget.onCategoryTap!,
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.compact,
    required this.placeholder,
    required this.active,
    required this.onTap,
    required this.onHoverChanged,
    required this.onPressedChanged,
  });

  final bool compact;
  final String placeholder;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onHighlightChanged: onPressedChanged,
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.patientTeal.withValues(alpha: 0.05),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: compact ? 50 : 54,
            padding: EdgeInsets.only(
              left: compact ? 14 : 16,
              right: compact ? 6 : 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? AppColors.patientTeal.withValues(alpha: 0.55)
                    : AppColors.borderOf(context),
                width: active ? 1.5 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: AppColors.patientTeal.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppColors.textPrimaryOf(context).withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: active ? AppColors.patientTeal : AppColors.textSecondaryOf(context),
                  size: 22,
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Text(
                    placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.2,
                    ),
                  ),
                ),
                if (compact)
                  _MobileSearchAction(active: active, onTap: onTap)
                else
                  _DesktopSearchAction(onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSearchAction extends StatelessWidget {
  const _MobileSearchAction({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active
            ? AppColors.patientTeal
            : AppColors.patientTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: active ? AppColors.surfaceOf(context) : AppColors.patientTeal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSearchAction extends StatefulWidget {
  const _DesktopSearchAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DesktopSearchAction> createState() => _DesktopSearchActionState();
}

class _DesktopSearchActionState extends State<_DesktopSearchAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF0D5C47) : AppColors.patientTeal,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            'Search',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.surfaceOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCategoriesRow extends StatelessWidget {
  const _QuickCategoriesRow({
    required this.compact,
    required this.onCategoryTap,
  });

  final bool compact;
  final ValueChanged<String> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final category in HomeSearchBar._quickCategories)
            _QuickCategoryChip(
              label: category,
              compact: false,
              onTap: () => onCategoryTap(category),
            ),
        ],
      );
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: HomeSearchBar._quickCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = HomeSearchBar._quickCategories[index];
          return _QuickCategoryChip(
            label: category,
            compact: true,
            onTap: () => onCategoryTap(category),
          );
        },
      ),
    );
  }
}

class _QuickCategoryChip extends StatefulWidget {
  const _QuickCategoryChip({
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_QuickCategoryChip> createState() => _QuickCategoryChipState();
}

class _QuickCategoryChipState extends State<_QuickCategoryChip> {
  bool _hovered = false;

  String get _label {
    if (!widget.compact) return widget.label;
    return switch (widget.label) {
      'General Physician' => 'General',
      'Skin Specialist' => 'Skin',
      'Heart Specialist' => 'Heart',
      'Eye Specialist' => 'Eye',
      _ => widget.label,
    };
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.patientTeal.withValues(alpha: 0.1)
                  : AppColors.cardBgOf(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _hovered
                    ? AppColors.patientTeal.withValues(alpha: 0.35)
                    : AppColors.borderOf(context),
              ),
            ),
            child: Text(
              _label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: _hovered ? AppColors.patientTeal : AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
