import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import 'auth_login_form_field.dart';
import '../../../core/theme/app_typography.dart';

class AuthLoginPasswordField extends StatefulWidget {
  const AuthLoginPasswordField({
    super.key,
    required this.controller,
    required this.accentColor,
    this.label = 'Password',
    this.hint,
    this.validator,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    this.isRequired,
    this.labelTrailing,
    this.footer,
  });

  final TextEditingController controller;
  final Color accentColor;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool? isRequired;
  final Widget? labelTrailing;

  /// Shown directly below the password field (e.g. forgot password link).
  final Widget? footer;

  @override
  State<AuthLoginPasswordField> createState() => _AuthLoginPasswordFieldState();
}

class _AuthLoginPasswordFieldState extends State<AuthLoginPasswordField> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AuthLoginPasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRequired = widget.isRequired ?? widget.validator != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthLoginFieldLabel(
          label: widget.label,
          isRequired: isRequired,
          trailing: widget.labelTrailing,
        ),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscure,
          validator: widget.validator,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: const [AutofillHints.password],
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: true,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimaryOf(context),
          ),
          decoration: authLoginFieldDecoration(
            context: context,
            accentColor: widget.accentColor,
            hintText: widget.hint ?? 'Enter your password',
            prefixIcon: Icon(Icons.lock_outline_rounded,
                size: 20, color: AppColors.textSecondaryOf(context)),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: AppColors.textSecondaryOf(context),
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: widget.footer!,
          ),
        ],
      ],
    );
  }
}

/// Default validator wrapper for login password fields.
String? authLoginPasswordValidator(String? value) =>
    FormValidators.required(value, field: 'Password');
