import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';

class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

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

    return _SearchField(
      compact: compact,
      placeholder: placeholder,
      active: active,
      onTap: widget.onTap,
      onHoverChanged: (value) => setState(() => _hovered = value),
      onPressedChanged: (value) => setState(() => _pressed = value),
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
