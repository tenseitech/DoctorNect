import '../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/theme/app_colors.dart';
import '../auth/widgets/auth_login_branding.dart';
import '../auth/widgets/auth_login_page_shell.dart';
import '../welcome/welcome_screen.dart';
import 'ambulance_shell.dart';
import 'data/ambulance_store.dart';
import '../../core/theme/app_typography.dart';

/// Resumes a persisted ambulance session only after PIN re-verification.
class AmbulanceShellAuto extends StatefulWidget {
  const AmbulanceShellAuto({super.key});

  @override
  State<AmbulanceShellAuto> createState() => _AmbulanceShellAutoState();
}

class _AmbulanceShellAutoState extends State<AmbulanceShellAuto> {
  static const _accent = Color(0xFFDC2626);

  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  bool _loading = true;
  bool _submitting = false;
  bool _obscurePin = true;
  String? _username;
  String _driverName = '';
  String _serviceName = '';
  String _ambulanceId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final restored = await AmbulanceSession.restoreSession();
    if (!mounted) return;

    if (!restored) {
      _goWelcome();
      return;
    }

    _ambulanceId = AmbulanceSession.loggedInAmbulanceId;
    _driverName = AmbulanceSession.loggedInDriverName;
    _serviceName = AmbulanceSession.loggedInAmbulanceName;

    if (_ambulanceId.isEmpty) {
      _goWelcome();
      return;
    }

    final profile = await FirestoreService.instance.ambulance
        .fetchAmbulanceById(_ambulanceId);
    if (!mounted) return;

    final username = profile?.username.trim().toLowerCase() ?? '';
    if (username.isEmpty) {
      await AmbulanceSession.clear();
      if (!mounted) return;
      _goWelcome();
      return;
    }

    if (profile != null) {
      AmbulanceStore.instance.registerAmbulance(profile);
      _serviceName = profile.serviceName;
      _driverName = profile.driverName;
    }

    setState(() {
      _username = username;
      _loading = false;
    });
  }

  Future<void> _continueWithPin() async {
    if (_submitting || _username == null) return;

    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      _showError('Enter your 6-digit security PIN.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
      if (!mounted) return;
      if (!signedIn) {
        _showError(
          'Could not start a secure session. Please try again or use a different account.',
        );
        return;
      }

      final login = await FirestoreService.instance.ambulance.verifyDriverLogin(
        username: _username!,
        pin: pin,
      );
      if (!mounted) return;
      if (!login.ok) {
        _showError(
          login.pinUpgradeRequired
              ? 'Your PIN must be reset for security. Use Forgot PIN on the login screen.'
              : 'Incorrect PIN. Please try again.',
        );
        return;
      }

      final match = login.profile!;

      await FirestoreService.instance.ambulance.linkDriverAuth(
        match.id,
        username: _username!,
        pin: pin,
      );
      await AmbulanceSession.setAmbulance(
        id: match.id,
        serviceName: match.serviceName,
        driverName: match.driverName,
      );

      final fresh = AmbulanceStore.instance.findAmbulance(match.id) ?? match;
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AmbulanceShell(ambulance: fresh)),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      _showError('Could not verify PIN. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _useDifferentAccount() async {
    await AmbulanceSession.clear();
    if (!mounted) return;
    _goWelcome();
  }

  void _goWelcome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        body: Center(
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    final greetingName = _driverName.isNotEmpty ? _driverName : 'Driver';

    return AuthLoginPageShell(
      appBarTitle: 'Ambulance Login',
      accentColor: _accent,
      icon: Icons.local_hospital,
      subtitle: 'Welcome back, $greetingName — enter your PIN to continue.',
      branding: AuthLoginBranding.ambulance,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serviceName.isNotEmpty) ...[
            Text(
              _serviceName,
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            'Username: ${_username ?? ''}',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Security PIN',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _pinController,
            focusNode: _pinFocusNode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: _obscurePin,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _continueWithPin(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w500,
              letterSpacing: _obscurePin ? 6 : 1.5,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accent, width: 1.5),
              ),
              prefixIcon: Icon(Icons.lock_outline_rounded,
                  size: 20, color: AppColors.textSecondaryOf(context)),
              suffixIcon: IconButton(
                tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
                icon: Icon(
                  _obscurePin
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textSecondaryOf(context),
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _continueWithPin,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Continue',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _submitting ? null : _useDifferentAccount,
            child: Text(
              'Use a different account',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
