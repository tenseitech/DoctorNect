import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../../../../widgets/required_field_label.dart';
import '../../../../core/theme/app_typography.dart';

/// Shared visual tokens for patient profile form screens (matches doctor profile sections).
abstract final class PatientProfileFormStyles {
  static const maxContentWidth = 560.0;
  static const pagePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 24);
  static const contentPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 24);

  static InputDecoration fieldDecoration(
    BuildContext context, {
    required String labelText,
    Widget? suffixIcon,
    String? counterText,
    String? hintText,
    bool alignLabelWithHint = false,
    bool isRequired = false,
  }) {
    return RequiredFieldLabels.decorate(
      InputDecoration(
        hintText: hintText,
        alignLabelWithHint: alignLabelWithHint,
        filled: true,
        fillColor: AppColors.surfaceOf(context),
        suffixIcon: suffixIcon,
        counterText: counterText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.patientTeal, width: 1.5),
        ),
      ),
      labelText,
      isRequired: isRequired,
    );
  }

  static Widget changeSuffixLabel({VoidCallback? onPressed}) {
    final label = Text(
      'Change',
      style: GoogleFonts.inter(
        fontSize: AppTypography.bodyMedium,
        fontWeight: FontWeight.w600,
        color: AppColors.patientTeal,
      ),
    );

    if (onPressed == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, right: 4),
        child: label,
      );
    }

    return TextButton(
      onPressed: onPressed,
      child: label,
    );
  }

  static Widget sectionLabel(String text) {
    return sectionHeader(text);
  }

  static Widget sectionHeader(String text) {
    return Builder(
      builder: (context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ),
    );
  }

  static double resolveContentWidth(
      BuildContext context, BoxConstraints constraints) {
    var viewportWidth = constraints.maxWidth;
    if (!viewportWidth.isFinite || viewportWidth <= 0) {
      viewportWidth = MediaQuery.sizeOf(context).width;
    }
    return viewportWidth > maxContentWidth ? maxContentWidth : viewportWidth;
  }

  static EdgeInsets scrollPaddingWithSystemInsets(
    BuildContext context, {
    EdgeInsets? padding,
  }) {
    final base = padding ?? pagePadding;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    if (bottomInset <= 0) return base;
    return base.copyWith(bottom: base.bottom + bottomInset);
  }

  /// UI FIX: constrained layout — centered scroll body capped at 560px.
  static Widget constrainedScrollBody({
    required Widget child,
    EdgeInsets? padding,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = resolveContentWidth(context, constraints);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            child: SingleChildScrollView(
              padding: scrollPaddingWithSystemInsets(context, padding: padding),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// UI FIX: constrained layout — scrollable list + optional bottom bar at 560px.
  static Widget constrainedListWithBottom({
    required Widget Function(BuildContext context) listBuilder,
    required Widget bottom,
    EdgeInsets? listPadding,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = resolveContentWidth(context, constraints);

        return Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: listBuilder(context),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: bottom,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// UI FIX: constrained layout — white surface card with standard padding.
  static Widget contentSurface(
      {required Widget child, required BuildContext context}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      padding: contentPadding,
      child: child,
    );
  }

  static Widget profileCard(
      {required Widget child, required BuildContext context}) {
    return contentSurface(context: context, child: child);
  }

  /// UI FIX: constrained layout — bordered record/list item card.
  static Widget recordItemCard(
      {required Widget child, required BuildContext context}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      child: child,
    );
  }

  /// UI FIX: constrained layout — menu/settings row inside a bordered card.
  static Widget settingsRowCard({
    required Widget child,
    required BuildContext context,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      child: child,
    );
  }

  static AppBar profileAppBar(String title, {BuildContext? context}) {
    return AppBar(
      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor:
          context != null ? AppColors.surfaceOf(context) : Colors.white,
      foregroundColor: context != null
          ? AppColors.textPrimaryOf(context)
          : AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    );
  }

  static Widget dobPickerRow({
    required BuildContext context,
    required String label,
    required String valueText,
    required VoidCallback onTap,
    bool isRequired = false,
  }) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RequiredFieldLabels.text(
                      label,
                      isRequired: isRequired,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      valueText,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          color: AppColors.textPrimaryOf(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.calendar_today_outlined,
                  color: AppColors.textSecondaryOf(context), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static Widget issueTypeChips({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Builder(
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((option) {
          final isSelected = selected == option;
          return FilterChip(
            label: Text(option),
            selected: isSelected,
            onSelected: (_) => onSelected(option),
            selectedColor: AppColors.patientTeal.withValues(alpha: 0.2),
            backgroundColor: AppColors.cardBgOf(context),
            disabledColor: AppColors.cardBgOf(context),
            checkmarkColor: AppColors.patientTeal,
            labelStyle: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              color: isSelected
                  ? AppColors.patientTeal
                  : AppColors.textSecondaryOf(context),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(
                color: isSelected
                    ? AppColors.patientTeal
                    : AppColors.borderOf(context)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        }).toList(),
      ),
    );
  }

  static Widget outlinedAddButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.patientTeal,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  /// UI FIX: constrained layout — action button filling card width only.
  static Widget cardActionButton({
    required VoidCallback? onPressed,
    required String label,
    Color? backgroundColor,
    bool fullWidth = true,
  }) {
    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.patientTeal,
        minimumSize: Size(fullWidth ? double.infinity : 0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );

    if (fullWidth) return button;

    return Align(alignment: Alignment.centerRight, child: button);
  }

  static Widget bottomSaveButton({
    required VoidCallback onPressed,
    required String label,
    bool enabled = true,
  }) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = resolveContentWidth(context, constraints);

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: cardActionButton(
                  onPressed: enabled ? onPressed : null,
                  label: label,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget bottomDestructiveButton({
    required VoidCallback? onPressed,
    required String label,
    IconData icon = Icons.person_remove_outlined,
  }) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = resolveContentWidth(context, constraints);

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: LabeledRemoveButton(
                  label: label,
                  icon: icon,
                  fullWidth: true,
                  compact: false,
                  onPressed: onPressed,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
