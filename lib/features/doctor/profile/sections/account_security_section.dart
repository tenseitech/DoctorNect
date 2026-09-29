import '../../../../core/notifications/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/validators/form_validators.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/section_save_bar.dart';

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
      AppToast.info(
        context,
        'Could not save changes. Please check your connection and try again.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.pop(context, true);
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                    size: 20,
                                  ),
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
