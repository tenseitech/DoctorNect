import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'legal_document_modal.dart';
import 'medibond_legal_content.dart';

class RegistrationLegalConsentCheckbox extends StatelessWidget {
  const RegistrationLegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.audience,
    this.accentColor = AppColors.patientTeal,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final LegalAudience audience;
  final Color accentColor;

  void _openDocument(BuildContext context, LegalDocumentType type) {
    showLegalDocumentModal(
      context,
      type: type,
      audience: audience,
      accentColor: accentColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = GoogleFonts.inter(
      fontSize: 13,
      height: 1.45,
      color: accentColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: accentColor,
    );
    final bodyStyle = GoogleFonts.inter(
      fontSize: 13,
      height: 1.45,
      color: AppColors.textSecondaryOf(context),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: accentColor,
            side: BorderSide(color: AppColors.borderOf(context)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: bodyStyle,
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openDocument(
                            context,
                            LegalDocumentType.termsOfService,
                          ),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openDocument(
                            context,
                            LegalDocumentType.privacyPolicy,
                          ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
