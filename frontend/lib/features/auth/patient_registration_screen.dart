import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/registration_credentials.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/invite/pending_doctor_invite_store.dart';
import '../../core/legal/medibond_legal_content.dart';
import '../../core/legal/registration_legal_consent_checkbox.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/form_scroll_helper.dart';
import '../../widgets/registration_mobile_otp_section.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../dashboard/dashboard_shell.dart';
import '../patient/profile/data/patient_profile_mock.dart';
import '../patient/sharing/patient_sharing_utils.dart';
import 'widgets/auth_login_branding.dart';
import 'widgets/auth_login_page_shell.dart';
import 'widgets/auth_registration_page_shell.dart';

class PatientRegistrationScreen extends StatefulWidget {
  const PatientRegistrationScreen({super.key, this.preVerifiedMobile});

  /// 10-digit mobile already verified via [UnifiedMobileAuthScreen].
  final String? preVerifiedMobile;

  @override
  State<PatientRegistrationScreen> createState() =>
      _PatientRegistrationScreenState();
}

class _PatientRegistrationScreenState extends State<PatientRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();

  final _nameFieldKey = GlobalKey();
  final _mobileFieldKey = GlobalKey();

  late bool _mobileVerified;
  bool _legalAccepted = false;
  bool _submitting = false;
  String? _mobileError;
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

  InputDecoration _fieldDecoration({
    required String label,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? counterText,
    bool isRequired = true,
  }) {
    return authLoginInputDecoration(
      context: context,
      accentColor: AppColors.patientTeal,
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      counterText: counterText,
      isRequired: isRequired,
    );
  }

  Future<void> _createAccount() async {
    setState(() {
      _mobileError =
          !_mobileVerified ? 'Please verify your mobile number with OTP' : null;
    });

    final isFormValid = _formKey.currentState!.validate();

    if (!isFormValid || _mobileError != null) {
      FormScrollHelper.scrollToFirstError(context);
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
      final patientId = await SupabaseBootstrap.resolveRegistrationProfileId(
        role: 'patient',
        defaultClientId: 'p${DateTime.now().millisecondsSinceEpoch}',
      );
      final name = _nameController.text.trim();

      final invitedDoctorId = PendingDoctorInviteStore.pendingDoctorId;

      final mobile = FormValidators.formatFullPhone(
        _mobileDialCode,
        _mobileController.text.trim(),
      );

      final mobileDigitsOnly = FormValidators.mobileDigits(mobile) ??
          mobile.replaceAll(RegExp(r'\D'), '');
      final authEmail =
          RegistrationCredentials.emailForMobile(mobileDigitsOnly);
      final password = RegistrationCredentials.generatePassword();

      final result = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: authEmail,
        password: password,
        profileId: patientId,
        displayName: name,
        mobile: mobile,
        otpVerificationSessionId: RegistrationOtpService.verificationSessionId,
        roleData: {
          'patientId': patientId,
          'verified': true,
          'status': 'approved',
          'name': name,
          'age': null,
          'gender': null,
          'bloodGroup': null,
          'height': null,
          'weight': null,
          'country': null,
          'state': null,
          'city': null,
          'pincode': null,
          'addressLine1': null,
          'addressLine2': null,
          'mobile': mobile,
          'email': null,
          if (invitedDoctorId != null && invitedDoctorId.isNotEmpty)
            'invitedDoctorId': invitedDoctorId,
          if (invitedDoctorId != null && invitedDoctorId.isNotEmpty)
            'primaryDoctorId': invitedDoctorId,
          'shareRecordsWithDoctors':
              PatientSharingUtils.deriveInitialShareRecordsWithDoctors(
            invitedDoctorId,
          ),
          if (invitedDoctorId != null && invitedDoctorId.isNotEmpty)
            'careTeamDoctorIds': [invitedDoctorId],
        },
      );
      if (!mounted) return;
      if (!result.success) {
        AppToast.info(context, result.message ?? 'Registration failed');
        return;
      }

      PatientProfileMock.applyRegistration(
        id: patientId,
        name: name,
        mobile: mobile,
        invitedDoctorId: invitedDoctorId,
      );
      PendingDoctorInviteStore.clear();
      TextInput.finishAutofillContext(shouldSave: true);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const DashboardShell(userType: UserType.patient),
        ),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.patientTeal;

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: accent),
      ),
      child: AuthLoginPageShell(
        appBarTitle: 'Patient Registration',
        accentColor: accent,
        icon: Icons.person_outline,
        welcomeTitle: 'Join as Patient',
        branding: AuthLoginBranding.patient,
        maxWidth: 480,
        subtitle:
            'Create your account to book doctors and manage health records',
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthRegistrationSection(
                icon: Icons.person_outline,
                title: 'Personal details',
                subtitle: 'Enter your name to complete signup',
                accentColor: accent,
                child: TextFormField(
                  key: _nameFieldKey,
                  controller: _nameController,
                  validator: FormValidators.fullName,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _fieldDecoration(
                    label: 'Full name *',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  ),
                ),
              ),
              AuthRegistrationSection(
                key: _mobileFieldKey,
                icon: Icons.sms_outlined,
                title: _otpAlreadyVerified
                    ? 'Mobile number'
                    : 'Mobile verification',
                subtitle: _otpAlreadyVerified
                    ? 'Verified during sign-in'
                    : 'One-time SMS code',
                accentColor: accent,
                showDivider: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_otpAlreadyVerified)
                      InputDecorator(
                        decoration: _fieldDecoration(
                          label: 'Mobile number *',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            size: 20,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                FormValidators.formatFullPhone(
                                  _mobileDialCode,
                                  _mobileController.text.trim(),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: AppTypography.bodyMedium,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.verified_rounded,
                              size: 18,
                              color: accent,
                            ),
                          ],
                        ),
                      )
                    else
                      RegistrationMobileOtpSection(
                        mobileController: _mobileController,
                        role: UserType.patient,
                        initialDialCode: _mobileDialCode,
                        onDialCodeChanged: (code) =>
                            setState(() => _mobileDialCode = code),
                        accentColor: accent,
                        phoneDecoration: _fieldDecoration(
                          label: 'Mobile number *',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            size: 20,
                          ),
                        ).copyWith(errorText: _mobileError),
                        onVerifiedChanged: (v) => setState(() {
                          _mobileVerified = v;
                          if (v) _mobileError = null;
                        }),
                      ),
                    if (_mobileError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          _mobileError!,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: AppTypography.labelMedium,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              RegistrationLegalConsentCheckbox(
                value: _legalAccepted,
                onChanged: (v) => setState(() => _legalAccepted = v ?? false),
                audience: LegalAudience.patient,
                accentColor: accent,
              ),
              const SizedBox(height: 16),
              AuthLoginPrimaryButton(
                accentColor: accent,
                label: 'Create Account',
                loading: _submitting,
                onPressed: _legalAccepted ? _createAccount : null,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
