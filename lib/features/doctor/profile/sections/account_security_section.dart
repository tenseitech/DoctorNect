import '../../../../core/notifications/app_toast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/overflow_safe_layout.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/section_save_bar.dart';
import '../../../../core/theme/app_typography.dart';

class AccountSecuritySection extends StatefulWidget {
  const AccountSecuritySection({super.key});

  @override
  State<AccountSecuritySection> createState() => _AccountSecuritySectionState();
}

class _AccountSecuritySectionState extends State<AccountSecuritySection> {
  final _formKey = GlobalKey<FormState>();
  late final _recoveryEmail = TextEditingController(text: _p.recoveryEmail);

  bool _dirty = false;

  DoctorProfileData get _p => DoctorProfileStore.instance.profile;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _p.recoveryEmail = _recoveryEmail.text.trim();

    try {
      await DoctorProfileStore.instance.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context,
          'Could not save changes. Please check your connection and try again.');
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.pop(context, true);
  }

  void _changePassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ChangePasswordDialog(parentContext: context),
    );
  }

  @override
  void dispose() {
    _recoveryEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & Security')),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.lock_outline),
                              title: const Text('Change password'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _changePassword,
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: TextFormField(
                                controller: _recoveryEmail,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Recovery email (optional)',
                                  hintText: 'e.g. backup@example.com',
                                  prefixIcon: Icon(
                                      Icons.alternate_email_outlined,
                                      size: 20),
                                  helperText:
                                      'Used for account recovery if you lose access',
                                ),
                                validator: FormValidators.optionalEmail,
                                onChanged: (_) => _markDirty(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SectionSaveBar(visible: _dirty, onSave: _save),
        ],
      ),
    );
  }
}

// ── Change Password Dialog ────────────────────────────────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.parentContext});
  final BuildContext parentContext;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() {
          _errorMsg = 'No logged-in user found. Please re-login.';
          _loading = false;
        });
        return;
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentCtrl.text,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newCtrl.text);

      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'wrong-password' ||
        'invalid-credential' =>
          'Current password is incorrect.',
        'weak-password' =>
          'New password is too weak. Use at least 6 characters.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => e.message ?? 'Password change failed.',
      };
      setState(() {
        _errorMsg = msg;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _errorMsg = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.doctorBlue, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Change Password',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTypography.headlineSmall),
            ),
          ),
        ],
      ),
      content: scrollableDialogContent(
        context: context,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMsg != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: const Color(0xFFDC2626)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showCurrent
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showCurrent = !_showCurrent),
                  ),
                ),
                validator: FormValidators.currentPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                obscureText: !_showNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _showNew = !_showNew),
                  ),
                ),
                validator: (v) =>
                    FormValidators.changePassword(v, _currentCtrl.text),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
                validator: (v) =>
                    FormValidators.confirmNewPassword(v, _newCtrl.text),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.doctorBlue,
            foregroundColor: Colors.white,
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}
