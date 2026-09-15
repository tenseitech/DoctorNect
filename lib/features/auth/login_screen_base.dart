import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/auth/last_login_store.dart';
import '../../core/constants/app_constants.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/firebase/firebase_error_messages.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../dashboard/dashboard_shell.dart';
import 'account_under_review_screen.dart';
import 'forgot_password_screen.dart';
import 'widgets/auth_login_branding.dart';
import 'widgets/auth_login_form_field.dart';
import '../../../widgets/overflow_safe_layout.dart';
import 'widgets/auth_login_page_shell.dart';
import 'widgets/auth_login_password_field.dart';

import '../../core/auth/registration_otp_service.dart';
import '../../core/auth/mobile_registration_lookup.dart';
import '../../core/notifications/app_toast.dart';
import '../../widgets/google_sign_in_button.dart';

enum LoginMethod { email, phone }

class LoginScreenBase extends StatefulWidget {
  const LoginScreenBase({
    super.key,
    required this.userType,
    required this.accentColor,
    required this.registerRoute,
    this.title,
    this.icon,
  });

  final UserType userType;
  final Color accentColor;
  final Widget registerRoute;
  final String? title;
  final IconData? icon;

  @override
  State<LoginScreenBase> createState() => _LoginScreenBaseState();
}

class _LoginScreenBaseState extends State<LoginScreenBase> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  LoginMethod _loginMethod = LoginMethod.email;
  bool _loading = false;
  bool _identifierLocked = false;
  bool _otpSent = false;
  bool _sendingOtp = false;
  int _otpCountdown = 0;
  Timer? _countdownTimer;
  Timer? _lookupDebounce;
  String? _lastLookupDigits;
  String? _lastLookupMessage;
  String _loadingStatus = 'Authenticating...';

  @override
  void initState() {
    super.initState();
    _identifierController.addListener(_onControllerChanged);
    _passwordController.addListener(_onControllerChanged);
    _otpController.addListener(_onControllerChanged);
    _applySaved(LastLoginStore.readCached(widget.userType));
    _loadSaved();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
    if (_loginMethod == LoginMethod.phone && !_otpSent) {
      _lookupDebounce?.cancel();
      _lookupDebounce = Timer(const Duration(milliseconds: 600), _lookupMobileModule);
    }
  }

  Future<void> _lookupMobileModule() async {
    if (_loginMethod != LoginMethod.phone || _otpSent) return;
    final digits = FormValidators.registrationMobileDigits(_identifierController.text) ??
        FormValidators.mobileDigits(_identifierController.text);
    if (digits == null || digits == _lastLookupDigits) return;

    final conflict = await MobileRegistrationLookup.check(
      digits,
      role: widget.userType,
      intent: MobileLookupIntent.login,
    );
    if (!mounted) return;

    if (conflict != true) {
      _lastLookupDigits = digits;
      _lastLookupMessage = null;
      return;
    }

    const message = MobileRegistrationLookup.loginConflictMessage;
    if (message == _lastLookupMessage) {
      _lastLookupDigits = digits;
      return;
    }

    _lastLookupDigits = digits;
    _lastLookupMessage = message;
    AppToast.error(context, message);
  }

  void _applySaved(String? saved) {
    if (saved == null || saved.isEmpty) return;
    _identifierController.text = saved;
    _identifierLocked = true;
  }

  Future<void> _loadSaved() async {
    final saved = await LastLoginStore.load(widget.userType);
    if (!mounted || saved == null) return;
    setState(() => _applySaved(saved));
  }

  @override
  void dispose() {
    _identifierController.removeListener(_onControllerChanged);
    _passwordController.removeListener(_onControllerChanged);
    _otpController.removeListener(_onControllerChanged);
    _lookupDebounce?.cancel();
    _identifierController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _passwordFocusNode.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_sendingOtp || _loading) return;
    final mobile = _identifierController.text.trim();
    final digits = FormValidators.registrationMobileDigits(mobile) ??
        FormValidators.mobileDigits(mobile);
    if (digits == null || digits.isEmpty) {
      AppToast.error(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    final conflict = await MobileRegistrationLookup.check(
      digits,
      role: widget.userType,
      intent: MobileLookupIntent.login,
    );
    if (!mounted) return;
    if (conflict == true) {
      AppToast.error(context, MobileRegistrationLookup.loginConflictMessage);
      return;
    }

    _otpController.clear();
    setState(() => _sendingOtp = true);

    try {
      _otpController.clear();
      final res = await RegistrationOtpService.sendOtp(
        digits,
        role: widget.userType,
        otpType: 'login',
      );
      if (!mounted) return;
      if (res.error != null) {
        AppToast.error(context, res.error!);
        return;
      }

      AppToast.info(context, 'OTP sent to +91 $digits');
      setState(() {
        _otpSent = true;
        _startOtpCountdown();
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, describeUserFacingError(e, fallback: 'Failed to send OTP'));
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  void _startOtpCountdown() {
    _countdownTimer?.cancel();
    setState(() => _otpCountdown = AppConstants.otpResendCooldownSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_otpCountdown <= 1) {
        t.cancel();
        setState(() => _otpCountdown = 0);
      } else {
        setState(() => _otpCountdown--);
      }
    });
  }

  String get _roleLabel => switch (widget.userType) {
        UserType.superAdmin => 'Super Admin',
        UserType.doctor => 'Doctor',
        UserType.patient => 'Patient',
        UserType.medicalStore => 'Medical Store',
        UserType.lab => 'Diagnostic Lab',
        UserType.ambulance => 'Ambulance',
      };

  IconData get _roleIcon =>
      widget.icon ??
      switch (widget.userType) {
        UserType.superAdmin => Icons.admin_panel_settings_outlined,
        UserType.doctor => Icons.medical_services_outlined,
        UserType.patient => Icons.person_outline,
        UserType.medicalStore => Icons.local_pharmacy_outlined,
        UserType.lab => Icons.biotech_outlined,
        UserType.ambulance => Icons.local_hospital_outlined,
      };

  String get _subtitle {
    if (_identifierLocked) {
      return 'Enter your password to continue to your $_roleLabel account.';
    }
    return switch (widget.userType) {
      UserType.superAdmin => 'Sign in with your administrative credentials.',
      UserType.doctor =>
        'Sign in with Google or your credentials to access your doctor dashboard.',
      UserType.patient =>
        'Sign in with Google or your credentials to access your health portal.',
      UserType.medicalStore =>
        'Sign in with Google or your credentials to manage prescriptions.',
      UserType.lab =>
        'Sign in with Google or your credentials to manage diagnostic orders.',
      UserType.ambulance =>
        'Sign in with Google or your credentials to access ambulance dashboard.',
    };
  }

  String get _identifierLabel =>
      _loginMethod == LoginMethod.email ? 'Username or email address' : 'Mobile Number';

  String get _identifierHint =>
      _loginMethod == LoginMethod.email
          ? 'Username or email address'
          : '9876543210';

  TextInputType get _identifierKeyboardType =>
      _loginMethod == LoginMethod.email
          ? TextInputType.emailAddress
          : TextInputType.phone;

  Widget get _identifierPrefixIcon {
    if (_loginMethod == LoginMethod.email) {
      return Icon(
        Icons.email_outlined,
        size: 20,
        color: AppColors.textSecondaryOf(context),
      );
    }
    return SizedBox(
      width: 76,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.phone_android_outlined,
            size: 18,
            color: AppColors.textSecondaryOf(context),
          ),
          const SizedBox(width: 4),
          Text(
            '+91',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 1,
            height: 16,
            color: AppColors.borderOf(context),
          ),
        ],
      ),
    );
  }

  String? _validateIdentifier(String? value) {
    if (_loginMethod == LoginMethod.email) {
      return FormValidators.email(value);
    }
    return FormValidators.mobile(value);
  }

  String get _registerLabel => switch (widget.userType) {
        UserType.superAdmin => 'Register Super Admin',
        UserType.doctor => 'Register as Doctor',
        UserType.patient => 'Register as Patient',
        UserType.medicalStore => 'Register Medical Store',
        UserType.lab => 'Register Diagnostic Lab',
        UserType.ambulance => 'Register Ambulance Service',
      };

  String get _newAccountDividerLabel => switch (widget.userType) {
        UserType.superAdmin => 'New admin?',
        UserType.doctor => 'New doctor?',
        UserType.patient => 'New patient?',
        UserType.medicalStore => 'New store?',
        UserType.lab => 'New lab?',
        UserType.ambulance => 'New ambulance service?',
      };

  Future<void> _useAnotherAccount() async {
    await LastLoginStore.clear(widget.userType);
    if (!mounted) return;
    setState(() {
      _identifierLocked = false;
      _identifierController.clear();
    });
  }

  Future<void> _offerReactivation(DateTime? reactivateBefore) async {
    final deadline = reactivateBefore != null
        ? DateFormat('d MMM yyyy').format(reactivateBefore)
        : '30 days';

    final shouldReactivate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Account deactivated'),
        content: Text(
          'Your profile is hidden from patients. Reactivate before $deadline to restore access.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseAuthService.instance.signOut();
              if (ctx.mounted) Navigator.pop(ctx, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate account'),
          ),
        ],
      ),
    );

    if (!mounted || shouldReactivate != true) return;

    setState(() => _loading = true);
    try {
      final result =
          await FirebaseAuthService.instance.reactivateDoctorAccount();
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DashboardShell(userType: widget.userType),
          ),
          (_) => false,
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not reactivate account'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _handleSignInResult(AuthSignInResult result) async {
    if (result.cancelled) {
      return true;
    }

    if (result.needsRegistration) {
      if (result.message != null && result.message!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => widget.registerRoute,
        ),
      );
      return true;
    }

    if (result.pendingReview) {
      await FirebaseAuthService.instance.signOut();
      if (!mounted) return true;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountUnderReviewScreen()),
        (_) => false,
      );
      return true;
    }

    if (result.canReactivateAccount && widget.userType == UserType.doctor) {
      await _offerReactivation(result.reactivateBefore);
      return true;
    }

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Sign-in failed'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      return true;
    }

    TextInput.finishAutofillContext(shouldSave: true);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => DashboardShell(userType: widget.userType),
      ),
      (_) => false,
    );
    return true;
  }

  Future<void> _login() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _loadingStatus = 'Authenticating...';
    });

    try {
      if (!FirebaseBootstrap.isReady) {
        final ready = await FirebaseBootstrap.initialize();
        if (!ready) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                FirebaseBootstrap.lastInitError ??
                    'Could not connect to Firebase. Refresh the page or use Chrome.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
      }
      final rawInput = _identifierController.text.trim();

      if (_loginMethod == LoginMethod.phone) {
        final digits = FormValidators.registrationMobileDigits(rawInput) ??
            FormValidators.mobileDigits(rawInput);
        if (digits == null || digits.isEmpty) {
          if (!mounted) return;
          AppToast.error(context, 'Enter a valid 10-digit mobile number.');
          return;
        }

        if (!_otpSent) {
          await _sendOtp();
          return;
        }

        final otpCode = _otpController.text.trim();
        if (otpCode.length != 6) {
          if (!mounted) return;
          AppToast.error(context, 'Enter 6-digit OTP code.');
          return;
        }

        final result = await FirebaseAuthService.instance.signInWithMobileOtp(
          expectedRole: widget.userType,
          mobile: digits,
          otpCode: otpCode,
        );
        if (!mounted) return;
        await _handleSignInResult(result);
        return;
      }

      await LastLoginStore.save(widget.userType, rawInput);
      if (!_identifierLocked && mounted) {
        setState(() => _identifierLocked = true);
      }
      final result = await FirebaseAuthService.instance.signInWithEmail(
        expectedRole: widget.userType,
        email: rawInput,
        password: _passwordController.text,
      );

      if (!mounted) return;
      await _handleSignInResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e,
                fallback: 'Login failed. Please try again.'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final result = await FirebaseAuthService.instance.signInWithGoogle(
        role: widget.userType,
      );
      if (!mounted) return;
      await _handleSignInResult(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeUserFacingError(e,
                fallback: 'Google Sign-In failed. Please try again.'),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRevampedMobile = ResponsiveLayout.isCompact(context);

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme:
            Theme.of(context).colorScheme.copyWith(primary: widget.accentColor),
      ),
      child: AuthLoginPageShell(
        appBarTitle: widget.title ?? '$_roleLabel Login',
        accentColor: widget.accentColor,
        icon: _roleIcon,
        subtitle: _subtitle,
        maxWidth: 440,
        branding: AuthLoginBranding.forUserType(widget.userType),
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): _login,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): _login,
          },
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isRevampedMobile) ...[
                  AuthLoginFormHeader(
                    title: 'Sign in',
                    subtitle: 'Sign in with Google or your credentials to continue.',
                    accentColor: widget.accentColor,
                  ),
                  const SizedBox(height: 18),
                ],

                // Prominent Google Sign-In button
                GoogleSignInButton(
                  onPressed: _loading ? null : _googleSignIn,
                  isLoading: _loading,
                  text: 'Continue with Google',
                ),

                // Adaptive divider matching screenshot
                AuthOrDivider(
                  text: _loginMethod == LoginMethod.email
                      ? 'Or continue with username/email'
                      : 'Or continue with mobile number',
                ),

                if (!_identifierLocked) ...[
                  _LoginMethodSelector(
                    selectedMethod: _loginMethod,
                    accentColor: widget.accentColor,
                    onChanged: (method) {
                      setState(() {
                        _loginMethod = method;
                        _identifierController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                ],
                if (_identifierLocked &&
                    _identifierController.text.trim().isNotEmpty) ...[
                  Visibility(
                    visible: false,
                    maintainState: true,
                    child: TextFormField(
                      controller: _identifierController,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                    ),
                  ),
                  AuthLoginSavedAccountChip(
                    email: _identifierController.text.trim(),
                    accentColor: widget.accentColor,
                    onChange: _useAnotherAccount,
                  ),
                  const SizedBox(height: 18),
                ] else
                  AuthLoginFormField(
                    label: _identifierLabel,
                    controller: _identifierController,
                    accentColor: widget.accentColor,
                    isRequired: true,
                    hint: _identifierHint,
                    keyboardType: _identifierKeyboardType,
                    autofillHints: _loginMethod == LoginMethod.email
                        ? const [AutofillHints.username, AutofillHints.email]
                        : const [AutofillHints.telephoneNumber],
                    validator: _validateIdentifier,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                    prefixIcon: _identifierPrefixIcon,
                  ),
                if (_loginMethod == LoginMethod.email) ...[
                  const SizedBox(height: 16),
                  AuthLoginPasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    accentColor: widget.accentColor,
                    validator: authLoginPasswordValidator,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    footer: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(
                              accentColor: widget.accentColor,
                              userType: widget.userType,
                            ),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot password?',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: widget.accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ] else if (_otpSent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'Enter 6-Digit OTP',
                      hintText: '123456',
                      prefixIcon: Icon(Icons.pin_outlined, color: widget.accentColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: _otpCountdown > 0
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '${_otpCountdown}s',
                                style: GoogleFonts.inter(
                                  color: widget.accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : TextButton(
                              onPressed: _sendingOtp ? null : _sendOtp,
                              child: const Text('Resend'),
                            ),
                    ),
                    validator: (v) {
                      if (_loginMethod == LoginMethod.phone && _otpSent) {
                        if (v == null || v.trim().length != 6) {
                          return 'Enter 6-digit OTP code';
                        }
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 22),
                AuthLoginPrimaryButton(
                  accentColor: widget.accentColor,
                  label: _loginMethod == LoginMethod.phone && !_otpSent ? 'Send OTP' : 'Login',
                  loading: _loading || _sendingOtp,
                  loadingText: _sendingOtp ? 'Sending OTP...' : _loadingStatus,
                  onPressed: _loginMethod == LoginMethod.phone && !_otpSent ? _sendOtp : _login,
                ),
                const SizedBox(height: 14),
                const SafeIconTextRow(
                  icon: Icons.verified_user_outlined,
                  text: 'Your credentials are encrypted and secure',
                ),
                const SizedBox(height: 22),
                AuthLoginDividerLabel(label: _newAccountDividerLabel),
                const SizedBox(height: 14),
                AuthLoginRegisterButton(
                  accentColor: widget.accentColor,
                  label: _registerLabel,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => widget.registerRoute),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _LoginMethodSelector extends StatelessWidget {
  const _LoginMethodSelector({
    required this.selectedMethod,
    required this.accentColor,
    required this.onChanged,
  });

  final LoginMethod selectedMethod;
  final Color accentColor;
  final ValueChanged<LoginMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final isEmail = selectedMethod == LoginMethod.email;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabPill(
              label: 'Email',
              icon: Icons.email_outlined,
              selected: isEmail,
              accentColor: accentColor,
              onTap: () => onChanged(LoginMethod.email),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabPill(
              label: 'Phone Number',
              icon: Icons.phone_android_outlined,
              selected: !isEmail,
              accentColor: accentColor,
              onTap: () => onChanged(LoginMethod.phone),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: Material(
        color: selected
            ? accentColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? accentColor.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? accentColor
                      : AppColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? accentColor
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
