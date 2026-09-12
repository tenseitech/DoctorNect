import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/required_field_label.dart';

/// Border-only decoration for auth login fields (label sits above the input).
InputDecoration authLoginFieldDecoration({
  required BuildContext context,
  required Color accentColor,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? counterText,
  bool readOnly = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hintText,
    hintStyle: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    counterText: counterText,
    filled: true,
    fillColor: readOnly ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: border(AppColors.borderOf(context)),
    enabledBorder: border(AppColors.borderOf(context)),
    focusedBorder: border(accentColor, 1.6),
    errorBorder: border(AppColors.error),
    focusedErrorBorder: border(AppColors.error, 1.6),
    disabledBorder: border(AppColors.borderOf(context)),
    errorStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.error, height: 1.2),
    errorMaxLines: 4,
  );
}

/// Compact header inside the login form card.
class AuthLoginFormHeader extends StatelessWidget {
  const AuthLoginFormHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.accentColor,
  });

  final String title;
  final String? subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              subtitle!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Shows saved email when the user returns to login.
class AuthLoginSavedAccountChip extends StatelessWidget {
  const AuthLoginSavedAccountChip({
    super.key,
    required this.email,
    required this.accentColor,
    required this.onChange,
  });

  final String email;
  final Color accentColor;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accentColor.withValues(alpha: 0.12),
            child: Icon(Icons.person_outline, size: 18, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signing in as',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Change',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label row shown above login inputs.
class AuthLoginFieldLabel extends StatelessWidget {
  const AuthLoginFieldLabel({
    super.key,
    required this.label,
    this.isRequired = false,
    this.trailing,
  });

  final String label;
  final bool isRequired;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: RequiredFieldLabels.text(
              label,
              isRequired: isRequired,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
                height: 1.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Stacked-label text field used on auth login screens.
class AuthLoginFormField extends StatelessWidget {
  const AuthLoginFormField({
    super.key,
    required this.label,
    required this.controller,
    required this.accentColor,
    this.isRequired = false,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.labelTrailing,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.readOnly = false,
    this.obscureText = false,
    this.maxLength,
    this.counterText,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final Color accentColor;
  final bool isRequired;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final Widget? labelTrailing;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool obscureText;
  final int? maxLength;
  final String? counterText;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthLoginFieldLabel(
          label: label,
          isRequired: isRequired,
          trailing: labelTrailing,
        ),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          obscureText: obscureText,
          maxLength: maxLength,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          onChanged: onChanged,
          validator: validator,
          autofillHints: autofillHints,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: readOnly ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
          ),
          decoration: authLoginFieldDecoration(
            context: context,
            accentColor: accentColor,
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            counterText: counterText,
            readOnly: readOnly,
          ),
        ),
      ],
    );
  }
}
