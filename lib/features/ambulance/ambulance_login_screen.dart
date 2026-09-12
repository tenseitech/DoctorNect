import '../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/mobile_registration_lookup.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/firebase/firebase_error_messages.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/widgets/auth_login_branding.dart';
import '../auth/widgets/auth_login_form_field.dart';
import '../auth/widgets/auth_login_page_shell.dart';
import 'ambulance_registration_screen.dart';
import 'ambulance_shell.dart';
import 'data/ambulance_login_cache.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_models.dart';
import 'widgets/ambulance_availability_toggle.dart';
import '../../widgets/overflow_safe_layout.dart';
import '../../widgets/phone_number_field.dart';

enum _AmbulanceLoginMethod { usernamePassword, mobile }

class AmbulanceLoginScreen extends StatefulWidget {
  const AmbulanceLoginScreen({super.key});

  static const _accentColor = Color(0xFFDC2626);

  @override
  State<AmbulanceLoginScreen> createState() => _AmbulanceLoginScreenState();
}

class _AmbulanceLoginScreenState extends State<AmbulanceLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  _AmbulanceLoginMethod _loginMethod = _AmbulanceLoginMethod.usernamePassword;
  bool _loginLoading = false;
  bool _sendingOtp = false;
  bool _obscurePassword = true;
  bool _usernameLocked = false;
  bool _otpSent = false;
  int _otpCountdown = 0;
  RegisteredAmbulance? _cachedProfile;
  Timer? _countdownTimer;
  Timer? _lookupDebounce;
  String? _lastLookupDigits;
  String? _lastLookupMessage;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _mobileController.addListener(_onMobileChanged);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadSavedUsername();
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty || !mounted) return;
    await _hydrateLocalProfile(username);
  }

  void _onUsernameChanged() {
    final username = _usernameController.text.trim().toLowerCase();
    final cachedUsername = _cachedProfile?.username.trim().toLowerCase();

    if (cachedUsername != null && cachedUsername == username) return;

    if (mounted) {
      setState(() => _cachedProfile = null);
    }
    if (username.isNotEmpty) {
      unawaited(_hydrateLocalProfile(username));
    }
  }

  void _onMobileChanged() {
    if (_loginMethod != _AmbulanceLoginMethod.mobile || _otpSent) return;
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 600), _lookupMobileModule);
  }

  Future<void> _lookupMobileModule() async {
    if (_loginMethod != _AmbulanceLoginMethod.mobile || _otpSent) return;
    final digits = FormValidators.registrationMobileDigits(_mobileController.text);
    if (digits == null || digits == _lastLookupDigits) return;

    final result = await MobileRegistrationLookup.check(digits);
    if (!mounted) return;

    if (result == null || !result.found) {
      _lastLookupDigits = digits;
      _lastLookupMessage = null;
      return;
    }

    final message = MobileRegistrationLookup.conflictMessage(
      currentRole: UserType.ambulance,
      isRegistration: false,
      registeredRoleLabel: result.roleLabel ?? 'another module',
      registeredRole: result.role,
    );
    if (message == null || message == _lastLookupMessage) {
      _lastLookupDigits = digits;
      return;
    }

    _lastLookupDigits = digits;
    _lastLookupMessage = message;
    AppToast.error(context, message);
  }

  Future<void> _hydrateLocalProfile(String username) async {
    final cached = await AmbulanceLoginCache.loadForUsername(username);
    if (!mounted) return;
    if (username != _usernameController.text.trim().toLowerCase()) return;
    if (cached == null) return;

    AmbulanceStore.instance.registerAmbulance(cached);
    setState(() => _cachedProfile = cached);
  }

  Future<void> _loadSavedUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('last_login_ambulance_username') ?? '';
      if (saved.isNotEmpty && mounted) {
        setState(() {
          _usernameController.text = saved;
          _usernameLocked = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onUsernameChanged);
    _mobileController.removeListener(_onMobileChanged);
    _lookupDebounce?.cancel();
    _countdownTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    _otpController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
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

  Future<void> _sendOtp() async {
    if (_sendingOtp) return;

    final digits = FormValidators.registrationMobileDigits(_mobileController.text);
    if (digits == null) {
      AppToast.error(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    final lookup = await MobileRegistrationLookup.check(digits);
    if (!mounted) return;
    if (lookup != null && lookup.found) {
      final message = MobileRegistrationLookup.conflictMessage(
        currentRole: UserType.ambulance,
        isRegistration: false,
        registeredRoleLabel: lookup.roleLabel ?? 'another module',
        registeredRole: lookup.role,
      );
      if (message != null) {
        AppToast.error(context, message);
        return;
      }
    }

    setState(() => _sendingOtp = true);
    _otpController.clear();

    try {
      final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
      if (!mounted) return;
      if (!signedIn) {
        AppToast.error(
          context,
          'Could not start a secure session. Please try again.',
        );
        return;
      }

      final res = await RegistrationOtpService.sendOtp(
        digits,
        role: UserType.ambulance,
        otpType: 'login',
      );
      if (!mounted) return;
      if (res.error != null) {
        AppToast.error(context, res.error!);
        return;
      }

      AppToast.info(context, 'OTP sent to +91 $digits');
      setState(() => _otpSent = true);
      _startOtpCountdown();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        describeUserFacingError(e, fallback: 'Failed to send OTP'),
      );
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _completeDriverLogin(
    RegisteredAmbulance match, {
    String? username,
    String? pin,
  }) async {
    final normalizedUsername =
        (username ?? match.username).trim().toLowerCase();

    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('last_login_ambulance_username', normalizedUsername);
      }),
    );
    await AmbulanceLoginCache.save(match);
    await AmbulanceSession.setAmbulance(
      id: match.id,
      serviceName: match.serviceName,
      driverName: match.driverName,
    );
    await AmbulanceAuthHelper.ensureSignedIn();
    await FirestoreService.instance.ambulance.linkDriverAuth(
      match.id,
      username: normalizedUsername,
      pin: pin,
    );

    final fresh = AmbulanceStore.instance.findAmbulance(match.id) ?? match;

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AmbulanceShell(ambulance: fresh)),
      (route) => false,
    );
  }

  Future<void> _loginWithUsernamePassword() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    final login = await FirestoreService.instance.ambulance.verifyDriverLogin(
      username: username,
      pin: password,
    );

    if (!mounted) return;
    if (!login.ok) {
      AppToast.error(
        context,
        login.errorMessage ??
            (login.pinUpgradeRequired
                ? 'Your password must be reset for security. Use Forgot Password.'
                : 'Incorrect username or password. Please try again.'),
      );
      return;
    }

    await _completeDriverLogin(
      login.profile!,
      username: username,
      pin: password,
    );
  }

  Future<void> _loginWithMobileOtp() async {
    final digits = FormValidators.registrationMobileDigits(_mobileController.text);
    if (digits == null) {
      AppToast.error(context, 'Enter a valid 10-digit mobile number.');
      return;
    }

    if (!_otpSent) {
      AppToast.error(context, 'Send OTP first, then enter the 6-digit code.');
      return;
    }

    final otpCode = _otpController.text.trim();
    if (otpCode.length != 6) {
      AppToast.error(context, 'Enter 6-digit OTP code.');
      return;
    }

    final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
    if (!mounted) return;
    if (!signedIn) {
      AppToast.error(context, 'Could not start a secure session. Please try again.');
      return;
    }

    final verifyError = await RegistrationOtpService.verify(
      digits,
      otpCode,
      role: UserType.ambulance,
      otpType: 'login',
    );
    if (!mounted) return;
    if (verifyError != null) {
      AppToast.error(context, verifyError);
      return;
    }

    final sessionId = RegistrationOtpService.verificationSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      AppToast.error(context, 'OTP verification session expired. Send OTP again.');
      return;
    }

    final login = await FirestoreService.instance.ambulance.verifyDriverMobileLogin(
      mobile: digits,
      sessionId: sessionId,
    );
    RegistrationOtpService.clearVerificationSession();

    if (!mounted) return;
    if (!login.ok) {
      AppToast.error(
        context,
        'No ambulance account found for this mobile number or OTP expired.',
      );
      return;
    }

    await _completeDriverLogin(login.profile!);
  }

  Future<void> _login() async {
    if (_loginLoading || _sendingOtp) return;
    if (!_formKey.currentState!.validate()) return;

    if (_loginMethod == _AmbulanceLoginMethod.mobile && !_otpSent) {
      await _sendOtp();
      return;
    }

    setState(() => _loginLoading = true);
    try {
      if (_loginMethod == _AmbulanceLoginMethod.usernamePassword) {
        await _loginWithUsernamePassword();
      } else {
        await _loginWithMobileOtp();
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Login failed. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  Future<void> _useAnotherAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_login_ambulance_username');
    } catch (_) {}
    setState(() {
      _usernameLocked = false;
      _usernameController.clear();
      _cachedProfile = null;
    });
  }

  void _onLoginMethodChanged(_AmbulanceLoginMethod method) {
    setState(() {
      _loginMethod = method;
      _otpSent = false;
      _otpController.clear();
      _otpCountdown = 0;
      _countdownTimer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAvailability =
        _loginMethod == _AmbulanceLoginMethod.usernamePassword &&
        _cachedProfile != null &&
        _usernameController.text.trim().toLowerCase() ==
            _cachedProfile!.username.trim().toLowerCase();

    final isMobile = _loginMethod == _AmbulanceLoginMethod.mobile;
    final primaryLabel = isMobile
        ? (_otpSent ? 'Verify & Login' : 'Send OTP')
        : 'Login';

    return AuthLoginPageShell(
      appBarTitle: 'Ambulance Login',
      accentColor: AmbulanceLoginScreen._accentColor,
      icon: Icons.local_hospital,
      subtitle: isMobile
          ? 'Sign in with your registered mobile number and OTP.'
          : 'Enter your username and password to access the driver dashboard.',
      branding: AuthLoginBranding.ambulance,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!ResponsiveLayout.isCompact(context)) ...[
              AuthLoginFormHeader(
                title: 'Sign in',
                subtitle: isMobile
                    ? 'Use your registered mobile number.'
                    : 'Use your registered username and password.',
                accentColor: AmbulanceLoginScreen._accentColor,
              ),
              const SizedBox(height: 16),
            ],
            _AmbulanceLoginMethodSelector(
              selected: _loginMethod,
              accentColor: AmbulanceLoginScreen._accentColor,
              onChanged: _onLoginMethodChanged,
            ),
            const SizedBox(height: 20),
            if (!isMobile) ...[
              if (_usernameLocked && _usernameController.text.trim().isNotEmpty) ...[
                AuthLoginSavedAccountChip(
                  email: _usernameController.text.trim(),
                  accentColor: AmbulanceLoginScreen._accentColor,
                  onChange: _useAnotherAccount,
                ),
                const SizedBox(height: 18),
              ] else
                AuthLoginFormField(
                  label: 'Username',
                  controller: _usernameController,
                  accentColor: AmbulanceLoginScreen._accentColor,
                  isRequired: true,
                  hint: 'Enter your username',
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                  prefixIcon: Icon(
                    Icons.person_pin_outlined,
                    size: 20,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  validator: FormValidators.loginUsername,
                ),
              const SizedBox(height: 16),
              const AuthLoginFieldLabel(label: 'Password', isRequired: true),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                keyboardType: TextInputType.visiblePassword,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _login(),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: authLoginFieldDecoration(
                  context: context,
                  accentColor: AmbulanceLoginScreen._accentColor,
                  hintText: 'Enter your password',
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Password is required' : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(
                          accentColor: AmbulanceLoginScreen._accentColor,
                          userType: UserType.ambulance,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text(
                    'Forgot Password?',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AmbulanceLoginScreen._accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (showAvailability) ...[
                AmbulanceAvailabilityToggle(ambulanceId: _cachedProfile!.id),
                const SizedBox(height: 20),
              ],
            ] else ...[
              PhoneNumberField(
                controller: _mobileController,
                initialDialCode: CountryPhoneCodes.defaultDialCode,
                labelText: 'Mobile Number',
                hintText: '10-digit mobile number',
                isRequired: true,
                enabled: !_otpSent,
                validator: (v) => FormValidators.phoneLocal(
                  v ?? '',
                  dialCode: CountryPhoneCodes.defaultDialCode,
                ),
                decoration: authLoginFieldDecoration(
                  context: context,
                  accentColor: AmbulanceLoginScreen._accentColor,
                  hintText: '10-digit mobile number',
                ),
              ),
              if (_otpSent) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'Enter 6-Digit OTP',
                    hintText: '000000',
                    prefixIcon: Icon(
                      Icons.pin_outlined,
                      color: AmbulanceLoginScreen._accentColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: _otpCountdown > 0
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '${_otpCountdown}s',
                              style: GoogleFonts.inter(
                                color: AmbulanceLoginScreen._accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: _sendingOtp ? null : _sendOtp,
                            child: const Text('Resend OTP'),
                          ),
                  ),
                  validator: (v) {
                    if (_otpSent && (v == null || v.trim().length != 6)) {
                      return 'Enter 6-digit OTP code';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
            AuthLoginPrimaryButton(
              accentColor: AmbulanceLoginScreen._accentColor,
              label: primaryLabel,
              loading: _loginLoading || _sendingOtp,
              loadingText: _sendingOtp ? 'Sending OTP...' : null,
              onPressed: (_loginLoading || _sendingOtp)
                  ? null
                  : (isMobile && !_otpSent ? _sendOtp : _login),
            ),
            if (!isMobile) ...[
              const SizedBox(height: 14),
              const SafeIconTextRow(
                icon: Icons.verified_user_outlined,
                text: 'Your credentials are encrypted and secure',
              ),
              const SizedBox(height: 22),
              const AuthLoginDividerLabel(label: 'New service?'),
              const SizedBox(height: 14),
              SafeArea(
                top: false,
                child: AuthLoginRegisterButton(
                  accentColor: AmbulanceLoginScreen._accentColor,
                  label: 'Register New Ambulance',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AmbulanceRegistrationScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmbulanceLoginMethodSelector extends StatelessWidget {
  const _AmbulanceLoginMethodSelector({
    required this.selected,
    required this.accentColor,
    required this.onChanged,
  });

  final _AmbulanceLoginMethod selected;
  final Color accentColor;
  final ValueChanged<_AmbulanceLoginMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final isUsername = selected == _AmbulanceLoginMethod.usernamePassword;

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
            child: _MethodPill(
              label: 'Username & Password',
              icon: Icons.person_outline,
              selected: isUsername,
              accentColor: accentColor,
              onTap: () => onChanged(_AmbulanceLoginMethod.usernamePassword),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _MethodPill(
              label: 'Mobile Number',
              icon: Icons.phone_android_outlined,
              selected: !isUsername,
              accentColor: accentColor,
              onTap: () => onChanged(_AmbulanceLoginMethod.mobile),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({
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
        color: selected ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: accentColor.withValues(alpha: 0.35))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? accentColor : AppColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? accentColor
                          : AppColors.textSecondaryOf(context),
                    ),
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
