import '../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/country_phone_codes.dart';
import '../../core/constants/countries.dart';
import '../../core/constants/app_constants.dart';
import '../../core/invite/pending_doctor_invite_store.dart';
import '../../core/legal/medibond_legal_content.dart';
import '../../core/legal/registration_legal_consent_checkbox.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_error_messages.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/form_scroll_helper.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../widgets/password_field.dart';
import '../../widgets/registration_mobile_otp_section.dart';
import '../../widgets/text_field_focus_helper.dart';
import '../dashboard/dashboard_shell.dart';
import '../patient/profile/data/patient_profile_mock.dart';
import '../patient/sharing/patient_sharing_utils.dart';
import 'widgets/auth_login_page_shell.dart';
import 'widgets/auth_registration_page_shell.dart';
import 'widgets/registration_address_section.dart';
import '../../core/theme/app_typography.dart';

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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _heightFtController = TextEditingController();
  final _heightInController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightFtFocusNode = FocusNode();
  final _heightInFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();

  double cmFromFtIn(int ft, int inch) => (ft * 30.48) + (inch * 2.54);

  final _nameFieldKey = GlobalKey();
  final _dobFieldKey = GlobalKey();
  final _mobileFieldKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();
  final _confirmPasswordFieldKey = GlobalKey();
  final _locationFieldKey = GlobalKey();

  DateTime? _dob;
  String? _gender;
  String? _country = Countries.defaultCountry;
  String? _state;
  String? _bloodGroup;
  String? _city;
  bool _mobileVerified = false;
  bool _legalAccepted = false;
  bool _submitting = false;
  String? _dobError;
  String? _mobileError;
  String? _locationError;
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
    }
    TextFieldFocusHelper.bindSelectAllOnFocus(
      focusNode: _heightFtFocusNode,
      controller: _heightFtController,
    );
    TextFieldFocusHelper.bindSelectAllOnFocus(
      focusNode: _heightInFocusNode,
      controller: _heightInController,
    );
    TextFieldFocusHelper.bindSelectAllOnFocus(
      focusNode: _weightFocusNode,
      controller: _weightController,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pincodeController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _heightFtController.dispose();
    _heightInController.dispose();
    _weightController.dispose();
    _heightFtFocusNode.dispose();
    _heightInFocusNode.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1920),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.patientTeal),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _dob = picked;
        _dobError = null;
      });
    }
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
      _dobError = _dob == null ? 'Please select date of birth' : null;
      _locationError = (_country == null || _state == null || _city == null)
          ? 'Please select Country, State, and City'
          : null;
      _mobileError = !_mobileVerified
          ? 'Please verify your mobile number with OTP'
          : null;
    });

    final isFormValid = _formKey.currentState!.validate();

    if (!isFormValid || _dobError != null || _locationError != null || _mobileError != null) {
      FormScrollHelper.scrollToFirstError(context);
      return;
    }
    if (!_legalAccepted) {
      AppToast.info(context, 'Please accept the Terms of Service and Privacy Policy');
      return;
    }

    setState(() => _submitting = true);

    try {
      final patientId = 'p${DateTime.now().millisecondsSinceEpoch}';
      final name = _nameController.text.trim();
      final age =
          _dob == null ? 25 : DateTime.now().difference(_dob!).inDays ~/ 365;

      final invitedDoctorId = PendingDoctorInviteStore.pendingDoctorId;

      final mobile = FormValidators.formatFullPhone(
        _mobileDialCode,
        _mobileController.text.trim(),
      );

      final rawEmail = _emailController.text.trim();
      final mobileDigitsOnly = mobile.replaceAll(RegExp(r'\D'), '');
      final authEmail = rawEmail.isNotEmpty
          ? rawEmail
          : '${mobileDigitsOnly.isNotEmpty ? mobileDigitsOnly : patientId}@patient.doctornect.com';
      final storedEmail = rawEmail.isNotEmpty ? rawEmail : null;

      final result = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: authEmail,
        password: _passwordController.text,
        profileId: patientId,
        displayName: name,
        mobile: mobile,
        otpVerificationSessionId: RegistrationOtpService.verificationSessionId,
        roleData: {
          'patientId': patientId,
          'verified': true,
          'status': 'approved',
          'name': name,
          'age': age,
          'gender': _gender ?? 'Female',
          'bloodGroup': _bloodGroup ?? 'O+',
          'height': cmFromFtIn(
            int.tryParse(_heightFtController.text.trim()) ?? 0,
            int.tryParse(_heightInController.text.trim()) ?? 0,
          ),
          'weight': double.tryParse(_weightController.text.trim()) ?? 0.0,
          'country': _country?.trim() ?? Countries.defaultCountry,
          'state': _state?.trim() ?? '',
          'city': _city?.trim() ?? '',
          'pincode': _pincodeController.text.trim(),
          'addressLine1': _address1Controller.text.trim(),
          'addressLine2': _address2Controller.text.trim(),
          'mobile': mobile,
          'email': storedEmail,
          if (invitedDoctorId != null && invitedDoctorId.isNotEmpty)
            'invitedDoctorId': invitedDoctorId,
          if (invitedDoctorId != null && invitedDoctorId.isNotEmpty)
            'primaryDoctorId': invitedDoctorId,
          'shareRecordsWithDoctors':
              PatientSharingUtils.deriveInitialShareRecordsWithDoctors(
                  invitedDoctorId),
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
        age: age,
        gender: _gender ?? 'Female',
        mobile: mobile,
        email: storedEmail ?? '',
        city: _city?.trim() ?? '',
        state: _state,
        country: _country,
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

  bool _prefillingGoogle = false;

  Future<void> _prefillFromGoogle() async {
    if (_prefillingGoogle || _submitting) return;
    setState(() => _prefillingGoogle = true);
    try {
      final googleProfile = await FirebaseAuthService.instance
          .fetchGoogleRegistrationProfile(role: UserType.patient);
      if (googleProfile != null && mounted) {
        setState(() {
          _nameController.text = googleProfile.displayName;
          _emailController.text = googleProfile.email;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        describeUserFacingError(e,
            fallback: 'Failed to pre-fill from Google. Please try again.'),
      );
    } finally {
      if (mounted) setState(() => _prefillingGoogle = false);
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
        maxWidth: 520,
        subtitle:
            'Create your account to book doctors and manage health records',
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthRegistrationStepIndicator(
                labels: ['Personal', 'Account', 'Location'],
                accentColor: accent,
              ),
              AuthRegistrationSection(
                icon: Icons.person_outline,
                title: 'Personal details',
                subtitle: 'Name, date of birth and health details',
                accentColor: accent,
                child: Column(
                  children: [
                    TextFormField(
                      key: _nameFieldKey,
                      controller: _nameController,
                      validator: FormValidators.fullName,
                      textInputAction: TextInputAction.next,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Full name *',
                        prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      key: _dobFieldKey,
                      onTap: _pickDob,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _fieldDecoration(
                          label: 'Date of birth *',
                          suffixIcon: const Icon(Icons.calendar_today_outlined,
                              size: 20),
                        ).copyWith(errorText: _dobError),
                        child: Text(
                          _dob == null
                              ? 'Select date of birth'
                              : DateFormat('dd MMM yyyy').format(_dob!),
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w600,
                            color: _dob == null
                                ? AppColors.textSecondaryOf(context)
                                : AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        label: 'Gender *',
                        prefixIcon: const Icon(Icons.wc_outlined, size: 20),
                      ),
                      items: AppConstants.genders
                          .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (v) => setState(() => _gender = v),
                      validator: (v) =>
                          FormValidators.dropdown(v, field: 'gender'),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _bloodGroup,
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        label: 'Blood group *',
                        prefixIcon:
                            const Icon(Icons.bloodtype_outlined, size: 20),
                      ),
                      items: AppConstants.bloodGroups
                          .map((bg) =>
                              DropdownMenuItem(value: bg, child: Text(bg)))
                          .toList(),
                      onChanged: (v) => setState(() => _bloodGroup = v),
                      validator: (v) =>
                          FormValidators.dropdown(v, field: 'blood group'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heightFtController,
                            focusNode: _heightFtFocusNode,
                            keyboardType: TextInputType.number,
                            autofillHints: const <String>[],
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(1),
                            ],
                            validator: FormValidators.heightFeet,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodyMedium,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _fieldDecoration(
                              label: 'Height (ft) *',
                              hintText: 'e.g. 5',
                              prefixIcon:
                                  const Icon(Icons.height_outlined, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _heightInController,
                            focusNode: _heightInFocusNode,
                            keyboardType: TextInputType.number,
                            autofillHints: const <String>[],
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            validator: FormValidators.heightInches,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodyMedium,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: _fieldDecoration(
                              label: 'Inches (in) *',
                              hintText: 'e.g. 8',
                              prefixIcon: const Icon(Icons.straighten_outlined,
                                  size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _weightController,
                      focusNode: _weightFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofillHints: const <String>[],
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      validator: (v) =>
                          FormValidators.required(v, field: 'Weight'),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Weight (kg) *',
                        hintText: 'e.g. 65',
                        prefixIcon: const Icon(
                            Icons.monitor_weight_outlined,
                            size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              AuthRegistrationSection(
                key: _mobileFieldKey,
                icon: Icons.sms_outlined,
                title: _otpAlreadyVerified ? 'Mobile number' : 'Mobile verification',
                subtitle: _otpAlreadyVerified
                    ? 'Verified during sign-in'
                    : 'One-time SMS code',
                accentColor: accent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_otpAlreadyVerified)
                      InputDecorator(
                        decoration: _fieldDecoration(
                          label: 'Mobile number *',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                FormValidators.formatFullPhone(
                                  _mobileDialCode,
                                  _mobileController.text.trim(),
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(Icons.verified_rounded, size: 18, color: accent),
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
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
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
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AuthRegistrationSection(
                icon: Icons.lock_outline,
                title: 'Account credentials',
                subtitle: 'Email and password for login',
                accentColor: accent,
                child: Column(
                  children: [
                    GoogleSignInButton(
                      onPressed: (_submitting || _prefillingGoogle) ? null : _prefillFromGoogle,
                      isLoading: _prefillingGoogle,
                      text: 'Continue with Google',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: _emailFieldKey,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: FormValidators.optionalEmail,
                      textInputAction: TextInputAction.next,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _fieldDecoration(
                        label: 'Email address (optional)',
                        prefixIcon: const Icon(Icons.email_outlined, size: 20),
                        isRequired: false,
                      ),
                    ),
                    const SizedBox(height: 14),
                    PasswordField(
                      key: _passwordFieldKey,
                      controller: _passwordController,
                      accentColor: accent,
                      validator: FormValidators.password,
                      textInputAction: TextInputAction.next,
                      showStrengthIndicator: true,
                    ),
                    const SizedBox(height: 14),
                    PasswordField(
                      key: _confirmPasswordFieldKey,
                      controller: _confirmPasswordController,
                      label: 'Confirm password *',
                      accentColor: accent,
                      validator: (v) => FormValidators.confirmPassword(
                        v,
                        _passwordController.text,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
              ),
              AuthRegistrationSection(
                key: _locationFieldKey,
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle: 'Country, state, city and pincode',
                accentColor: accent,
                showDivider: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RegistrationAddressSection(
                      initialCountry: _country,
                      initialState: _state,
                      initialCity: _city,
                      onCountryChanged: (value) => setState(() {
                        _country = value;
                        _state = null;
                        _city = null;
                        if (value != null) _locationError = null;
                      }),
                      onStateChanged: (value) => setState(() {
                        _state = value;
                        _city = null;
                        if (value != null) _locationError = null;
                      }),
                      onCityChanged: (value) => setState(() {
                        _city = value;
                        if (value != null) _locationError = null;
                      }),
                      address1Controller: _address1Controller,
                      address2Controller: _address2Controller,
                      pinCodeController: _pincodeController,
                      accentColor: accent,
                    ),
                    if (_locationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          _locationError!,
                          style: GoogleFonts.inter(
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
