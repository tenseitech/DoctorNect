import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/country_phone_codes.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/legal/medibond_legal_content.dart';
import '../../../core/legal/registration_legal_consent_checkbox.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/doctor_credentials_editor.dart';
import '../../../widgets/form_scroll_helper.dart';
import '../../../widgets/qualification_selector.dart';
import '../../../widgets/registration_mobile_otp_section.dart';
import 'auth_login_branding.dart';
import 'auth_login_page_shell.dart';
import 'auth_registration_page_shell.dart';
import '../../../core/theme/app_typography.dart';

/// Minimal registration form: Name, Degree, Mobile + OTP, legal consent.
class SimpleRoleRegistrationForm extends StatefulWidget {
  const SimpleRoleRegistrationForm({
    super.key,
    required this.role,
    required this.accentColor,
    required this.appBarTitle,
    required this.welcomeTitle,
    required this.subtitle,
    required this.icon,
    required this.onSubmit,
    this.nameLabel = 'Full name *',
    this.degreeLabel = 'Degree / qualification *',
    this.preVerifiedMobile,
  });

  final UserType role;
  final Color accentColor;
  final String appBarTitle;
  final String welcomeTitle;
  final String subtitle;
  final IconData icon;
  final String nameLabel;
  final String degreeLabel;
  final Future<void> Function({
    required String name,
    required String qualification,
    required String mobile,
    List<String>? degrees,
    List<String>? specializations,
  }) onSubmit;

  /// When set, mobile OTP was already verified in [UnifiedMobileAuthScreen].
  final String? preVerifiedMobile;

  @override
  State<SimpleRoleRegistrationForm> createState() =>
      _SimpleRoleRegistrationFormState();
}

class _SimpleRoleRegistrationFormState
    extends State<SimpleRoleRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();

  String? _qualification;
  List<String> _doctorDegrees = const ['MBBS'];
  List<String> _doctorSpecializations = const ['General Physician'];
  late bool _mobileVerified;
  bool _legalAccepted = false;
  bool _submitting = false;
  String _mobileDialCode = CountryPhoneCodes.defaultDialCode;

  bool get _otpAlreadyVerified => widget.preVerifiedMobile != null;

  @override
  void initState() {
    super.initState();
    final preMobile = widget.preVerifiedMobile;
    final digits = preMobile == null
        ? null
        : (FormValidators.registrationMobileDigits(preMobile) ??
            FormValidators.mobileDigits(preMobile));
    if (digits != null) {
      _mobileController.text = digits;
      _mobileVerified = true;
    } else {
      _mobileVerified = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {Widget? prefixIcon}) {
    return authLoginInputDecoration(
      context: context,
      accentColor: widget.accentColor,
      labelText: label,
      prefixIcon: prefixIcon,
      isRequired: true,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      FormScrollHelper.scrollToFirstError(context);
      return;
    }
    if (widget.role == UserType.doctor) {
      final cleanDegrees = _doctorDegrees
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final cleanSpecializations = _doctorSpecializations
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (cleanDegrees.isEmpty) {
        AppToast.info(context, 'Please select or enter at least one degree');
        return;
      }
      if (cleanSpecializations.isEmpty) {
        AppToast.info(
            context, 'Please select or enter at least one specialization');
        return;
      }
    } else {
      if (_qualification == null || _qualification!.trim().isEmpty) {
        AppToast.info(context, 'Please select your degree / qualification');
        return;
      }
    }
    if (!_mobileVerified) {
      AppToast.info(context, 'Please verify your mobile number with OTP');
      return;
    }
    if (!_legalAccepted) {
      AppToast.info(
        context,
        'Please accept the Terms of Service and Privacy Policy',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final mobile = FormValidators.formatFullPhone(
        _mobileDialCode,
        _mobileController.text.trim(),
      );
      final cleanDegrees = _doctorDegrees
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final cleanSpecializations = _doctorSpecializations
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      await widget.onSubmit(
        name: _nameController.text.trim(),
        qualification: widget.role == UserType.doctor
            ? cleanDegrees.join(', ')
            : _qualification!.trim(),
        mobile: mobile,
        degrees: widget.role == UserType.doctor ? cleanDegrees : null,
        specializations:
            widget.role == UserType.doctor ? cleanSpecializations : null,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<String> get _roleQualifications => switch (widget.role) {
        UserType.medical ||
        UserType.medicalStore =>
          AppConstants.pharmacyQualifications,
        UserType.lab => AppConstants.labQualifications,
        UserType.ambulance => AppConstants.ambulanceQualifications,
        _ => AppConstants.doctorQualifications,
      };

  LegalAudience get _legalAudience => switch (widget.role) {
        UserType.doctor => LegalAudience.doctor,
        UserType.medicalStore => LegalAudience.pharmacy,
        UserType.lab => LegalAudience.lab,
        UserType.ambulance => LegalAudience.ambulance,
        _ => LegalAudience.doctor,
      };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme:
            Theme.of(context).colorScheme.copyWith(primary: widget.accentColor),
      ),
      child: AuthLoginPageShell(
        appBarTitle: widget.appBarTitle,
        accentColor: widget.accentColor,
        icon: widget.icon,
        welcomeTitle: widget.welcomeTitle,
        branding: AuthLoginBranding.forUserType(widget.role),
        maxWidth: 480,
        subtitle: widget.subtitle,
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthRegistrationSection(
                icon: Icons.person_outline,
                title: 'Basic details',
                subtitle: 'Name, qualification and verified mobile number',
                accentColor: widget.accentColor,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      validator: (v) =>
                          FormValidators.required(v, field: 'Name'),
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration(
                        widget.nameLabel,
                        prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (widget.role == UserType.doctor) ...[
                      DoctorCredentialsEditor(
                        initialDegrees: _doctorDegrees,
                        initialSpecializations: _doctorSpecializations,
                        onDegreesChanged: (d) =>
                            setState(() => _doctorDegrees = d),
                        onSpecializationsChanged: (s) =>
                            setState(() => _doctorSpecializations = s),
                        accentColor: widget.accentColor,
                        registrationStyle: true,
                      ),
                    ] else ...[
                      QualificationSelector(
                        initialValue: _qualification,
                        items: _roleQualifications,
                        onChanged: (v) => setState(() => _qualification = v),
                        accentColor: widget.accentColor,
                        registrationStyle: true,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_otpAlreadyVerified)
                      _VerifiedMobileField(
                        mobile: FormValidators.formatFullPhone(
                          _mobileDialCode,
                          _mobileController.text.trim(),
                        ),
                        accentColor: widget.accentColor,
                      )
                    else
                      RegistrationMobileOtpSection(
                        role: widget.role,
                        accentColor: widget.accentColor,
                        mobileController: _mobileController,
                        initialDialCode: _mobileDialCode,
                        onDialCodeChanged: (v) =>
                            setState(() => _mobileDialCode = v),
                        phoneDecoration: _fieldDecoration(
                          'Mobile number *',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            size: 20,
                          ),
                        ),
                        onVerifiedChanged: (v) =>
                            setState(() => _mobileVerified = v),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              RegistrationLegalConsentCheckbox(
                value: _legalAccepted,
                onChanged: (v) => setState(() => _legalAccepted = v ?? false),
                audience: _legalAudience,
                accentColor: widget.accentColor,
              ),
              const SizedBox(height: 16),
              AuthLoginPrimaryButton(
                accentColor: widget.accentColor,
                label: 'Create account',
                loading: _submitting,
                loadingText: 'Creating account...',
                onPressed: _mobileVerified && !_submitting ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedMobileField extends StatelessWidget {
  const _VerifiedMobileField({required this.mobile, required this.accentColor});

  final String mobile;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: authLoginInputDecoration(
        context: context,
        accentColor: accentColor,
        labelText: 'Mobile number',
        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
        isRequired: true,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              mobile,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.verified_rounded, size: 18, color: accentColor),
        ],
      ),
    );
  }
}
