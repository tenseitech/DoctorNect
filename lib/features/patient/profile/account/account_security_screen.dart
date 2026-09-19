import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import '../../../../core/firebase/firebase_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/overflow_safe_layout.dart';
import '../widgets/patient_profile_form_styles.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  void _changePassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ChangePasswordDialog(
        onSaved: () {
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Account & Security', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                children: [
                  PatientProfileFormStyles.settingsRowCard(
                  context: context,
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lock_outline, color: AppColors.patientTeal),
                      title: Text('Change password'),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                      onTap: _changePassword,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      setState(() {});
      return;
    }
    if (_saving) return;

    setState(() => _saving = true);
    try {
      await FirebaseAuthService.instance.updatePassword(
        _oldCtrl.text,
        _newCtrl.text,
      );
      if (!mounted) return;
      widget.onSaved();
    } on WrongPasswordAuthException {
      if (!mounted) return;
      AppToast.info(context, 'Current password is incorrect');
    } on WeakPasswordAuthException {
      if (!mounted) return;
      AppToast.info(context, 'Password too weak, min 6 characters');
    } on AuthUpdateException catch (e) {
      if (!mounted) return;
      AppToast.info(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: scrollableDialogContent(
        context: context,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _oldCtrl,
                obscureText: true,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(labelText: 'Current password'),
                validator: FormValidators.password,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newCtrl,
                obscureText: true,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (v) => FormValidators.changePassword(v, _oldCtrl.text),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }
}
