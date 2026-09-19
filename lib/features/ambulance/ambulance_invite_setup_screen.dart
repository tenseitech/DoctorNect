import '../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/firebase/ambulance_auth_helper.dart';
import '../../core/invite/ambulance_invite_service.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../auth/widgets/auth_login_page_shell.dart';
import 'ambulance_shell.dart';
import 'data/ambulance_login_cache.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_invite.dart';
import '../../core/theme/app_typography.dart';

class AmbulanceInviteSetupScreen extends StatefulWidget {
  const AmbulanceInviteSetupScreen({
    super.key,
    required this.inviteId,
    required this.token,
  });

  final String inviteId;
  final String token;

  @override
  State<AmbulanceInviteSetupScreen> createState() => _AmbulanceInviteSetupScreenState();
}

class _AmbulanceInviteSetupScreenState extends State<AmbulanceInviteSetupScreen> {
  static const _accentColor = Color(0xFFDC2626);

  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  String? _error;
  AmbulanceInvite? _invite;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInvite() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
    if (!mounted) return;
    if (!signedIn) {
      setState(() {
        _loading = false;
        _error = 'Could not start a secure session. Sign out of other accounts and try again.';
      });
      return;
    }

    final invite = await AmbulanceInviteService.fetchInvite(
      widget.inviteId,
      token: widget.token,
    );
    if (!mounted) return;

    if (invite == null) {
      setState(() {
        _loading = false;
        _error = 'Invite not found or expired.';
      });
      return;
    }

    if (invite.token != widget.token) {
      setState(() {
        _loading = false;
        _error = 'Invalid invite link.';
      });
      return;
    }

    if (!invite.isPending) {
      setState(() {
        _loading = false;
        _error = 'This invite has already been used.';
      });
      return;
    }

    if (invite.expiresAt != null && DateTime.now().isAfter(invite.expiresAt!)) {
      setState(() {
        _loading = false;
        _error = 'This invite link has expired.';
      });
      return;
    }

    setState(() {
      _invite = invite;
      _loading = false;
      if (_usernameCtrl.text.isEmpty) {
        _usernameCtrl.text = _suggestedUsername(invite);
      }
    });
  }

  String _suggestedUsername(AmbulanceInvite invite) {
    final phone = invite.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length >= 4) return 'driver$phone';
    final name = invite.driverName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    if (name.length >= 3) return name;
    return '';
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate() || _invite == null) return;

    setState(() => _submitting = true);

    final error = await AmbulanceInviteService.completeInviteSetup(
      inviteId: widget.inviteId,
      token: widget.token,
      username: _usernameCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    final ambulanceId = _invite!.ambulanceId;
    final username = _usernameCtrl.text.trim().toLowerCase();
    final pin = _pinCtrl.text.trim();
    await FirestoreService.instance.ambulance.linkDriverAuth(
      ambulanceId,
      username: username,
      pin: pin,
    );
    await FirestoreService.instance.ambulance.fetchAmbulanceById(ambulanceId);

    final fresh = AmbulanceStore.instance.findAmbulance(ambulanceId) ??
        _invite!.toRegisteredAmbulance(
          username: username,
          pinHash: '',
        );

    await AmbulanceLoginCache.save(fresh);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('last_login_ambulance_username', username);
    }).catchError((_) {});

    PendingAmbulanceInviteStore.clear();

    if (!mounted) return;
    setState(() => _submitting = false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AmbulanceShell(ambulance: fresh)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ambulance Setup')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ),
      );
    }

    final invite = _invite;

    return AuthLoginPageShell(
      appBarTitle: 'Ambulance Setup',
      accentColor: _accentColor,
      icon: Icons.local_hospital,
      welcomeTitle: 'Complete Setup',
      subtitle: invite == null
          ? 'Loading invite…'
          : 'Set your username and 6-digit PIN for ${invite.serviceName}.',
      loading: _loading,
      body: invite == null
          ? const SizedBox.shrink()
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.serviceName,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: AppTypography.bodyLarge),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Driver: ${invite.driverName} · ${invite.city}',
                          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                        ),
                        if (invite.doctorName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Invited by Dr. ${invite.doctorName}',
                            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _usernameCtrl,
                    style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
                    decoration: authLoginInputDecoration(
                      context: context,
                      accentColor: _accentColor,
                      labelText: 'Username',
                      hintText: 'Choose a username',
                      prefixIcon: const Icon(Icons.person_pin_outlined, size: 20),
                    ),
                    validator: FormValidators.username,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pinCtrl,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: authLoginInputDecoration(
                      context: context,
                      accentColor: _accentColor,
                      labelText: 'Set 6-Digit PIN',
                      hintText: '••••••',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePin = !_obscurePin),
                      ),
                    ),
                    validator: FormValidators.securityPin,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPinCtrl,
                    obscureText: _obscureConfirm,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: authLoginInputDecoration(
                      context: context,
                      accentColor: _accentColor,
                      labelText: 'Confirm PIN',
                      hintText: '••••••',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) => FormValidators.confirmSecurityPin(v, _pinCtrl.text.trim()),
                  ),
                  const SizedBox(height: 24),
                  AuthLoginPrimaryButton(
                    accentColor: _accentColor,
                    label: 'Set PIN & Login',
                    loading: _submitting,
                    onPressed: _completeSetup,
                  ),
                ],
              ),
            ),
    );
  }
}
