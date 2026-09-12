import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/auth/widgets/auth_login_page_shell.dart';
import 'required_field_label.dart';

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint,
    this.validator,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    this.accentColor,
    this.isRequired,
    this.showStrengthIndicator = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Color? accentColor;
  final bool? isRequired;
  final bool showStrengthIndicator;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.showStrengthIndicator) {
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    if (widget.showStrengthIndicator) {
      widget.controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final isRequired = widget.isRequired ?? widget.validator != null;
    final text = widget.controller.text;

    final hasMinLength = text.length >= 8;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(text);
    final hasLower = RegExp(r'[a-z]').hasMatch(text);
    final hasDigit = RegExp(r'[0-9]').hasMatch(text);
    final hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\+=/\\]').hasMatch(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password, AutofillHints.newPassword],
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: true,
          contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
          validator: widget.validator,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          style: widget.accentColor != null
              ? GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)
              : null,
          decoration: widget.accentColor != null
              ? authLoginInputDecoration(
                  context: context,
                  accentColor: accent,
                  labelText: widget.label,
                  hintText: widget.hint,
                  isRequired: isRequired,
                  prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                )
              : RequiredFieldLabels.decorate(
                  InputDecoration(
                    hintText: widget.hint,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  widget.label,
                  isRequired: isRequired,
                ),
        ),
        if (widget.showStrengthIndicator && text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RequirementPill(label: '8+ chars', met: hasMinLength),
              _RequirementPill(label: '1 Uppercase (A-Z)', met: hasUpper),
              _RequirementPill(label: '1 Lowercase (a-z)', met: hasLower),
              _RequirementPill(label: '1 Number (0-9)', met: hasDigit),
              _RequirementPill(label: '1 Special (!@#\$%^&*)', met: hasSpecial),
            ],
          ),
        ],
      ],
    );
  }
}

class _RequirementPill extends StatelessWidget {
  const _RequirementPill({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF16A34A);
    final inactiveColor = const Color(0xFF64748B);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: met ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: met ? activeColor.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 13,
            color: met ? activeColor : inactiveColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: met ? FontWeight.w600 : FontWeight.w400,
              color: met ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
