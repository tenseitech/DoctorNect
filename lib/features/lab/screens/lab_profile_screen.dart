import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/app_logout.dart';
import '../../../core/auth/contact_change_otp_service.dart';
import '../../../core/auth/contact_change_verification.dart';
import '../../../core/firebase/firebase_auth_service.dart';
import '../../../core/legal/medibond_legal_content.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../widgets/phone_number_field.dart';
import '../../patient/profile/about/about_screen.dart';
import '../../auth/widgets/registration_address_section.dart';
import '../data/lab_connection_store.dart';
import '../data/lab_registry.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';

const _lineColor = Color(0xFFE2E8F0);
const _labPurple = AppColors.labPurple;

String _labInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'L';
  return trimmed[0].toUpperCase();
}

class LabProfileScreen extends StatefulWidget {
  const LabProfileScreen({super.key});

  @override
  State<LabProfileScreen> createState() => _LabProfileScreenState();
}

class _LabProfileScreenState extends State<LabProfileScreen> {
  @override
  void initState() {
    super.initState();
    final labId = LabSession.loggedInLabId;
    if (labId.isNotEmpty) {
      unawaited(LabRegistry.ensureLabLoaded(labId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LabRegistry.instance,
        LabConnectionStore.instance,
      ]),
      builder: (context, _) {
        final labId = LabSession.loggedInLabId;
        final lab = LabRegistry.findById(labId);
        if (lab == null) {
          return const Center(child: CircularProgressIndicator(color: _labPurple));
        }

        final connectedDoctors = LabConnectionStore.instance.activeForLab(labId).length;

        return LabPageLayout(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: ListView(
            children: [
              Text(
                'Profile',
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Lab details, contact info & account settings',
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 20),
              _LabHeroCard(lab: lab, connectedDoctors: connectedDoctors),
              const SizedBox(height: 20),
              _LabProfileSection(
                title: 'Lab details',
                subtitle: 'Registered diagnostic lab information',
                children: [
                  _LabInfoTile(
                    icon: Icons.biotech_outlined,
                    label: 'Lab name',
                    value: lab.labName,
                    onEdit: () => _showEditDialog(
                      context,
                      labId: labId,
                      field: 'Lab name',
                      currentValue: lab.labName,
                    ),
                  ),
                  _LabInfoTile(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: lab.address,
                    onEdit: () => showDialog(
                      context: context,
                      builder: (context) => _AddressEditDialog(labId: labId, lab: lab),
                    ),
                  ),
                  _LabInfoTile(
                    icon: Icons.badge_outlined,
                    label: 'License number',
                    value: lab.licenseNumber,
                    locked: true,
                    supportMessage:
                        'License number cannot be changed after registration. Contact support@doctornect.com if this needs to be corrected.',
                  ),
                  _LabInfoTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'GST number',
                    value: lab.gstNumber?.trim() ?? '',
                    placeholder: 'Not added',
                    onEdit: () => _showEditDialog(
                      context,
                      labId: labId,
                      field: 'GST number (optional)',
                      currentValue: lab.gstNumber?.trim() ?? '',
                      optional: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LabProfileSection(
                title: 'Contact',
                subtitle: 'How doctors and patients reach your lab',
                children: [
                  _LabInfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: lab.phone,
                    onEdit: () => _showEditDialog(
                      context,
                      labId: labId,
                      field: 'Phone',
                      currentValue: lab.phone,
                    ),
                  ),
                  _LabInfoTile(
                    icon: Icons.email_outlined,
                    label: 'Email (immutable)',
                    value: lab.email,
                  ),
                ],
              ),
              StreamBuilder<BannerConfigModel>(
                stream: BannerConfigService.streamConfig(),
                builder: (context, snapshot) {
                  final config = snapshot.data;
                  if (config != null && !config.enabled) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      _LabProfileSection(
                        title: 'Advertising',
                        subtitle: 'Grow lab orders & patient reach',
                        children: [
                          _LabActionTile(
                            icon: Icons.campaign_rounded,
                            label: 'Promote Banner Ad',
                            subtitle: 'Advertise lab services on Patient Home',
                            onTap: () {
                              final isVerified = lab.verified;
                              PromotedAdsManagementScreen.open(
                                context,
                                providerType: 'lab',
                                providerId: labId,
                                providerEmail: lab.email,
                                providerContact: lab.phone,
                                isVerified: isVerified,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _LabProfileSection(
                title: 'Account',
                subtitle: 'Security and session',
                children: [
                  _LabActionTile(
                    icon: Icons.info_outline,
                    label: 'About DoctorNect',
                    subtitle: 'Terms, privacy & lab policies',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AboutScreen(
                            accentColor: _labPurple,
                            audience: LegalAudience.lab,
                          ),
                        ),
                      );
                    },
                  ),
                  _LabActionTile(
                    icon: Icons.lock_reset_outlined,
                    label: 'Change password',
                    subtitle: 'Update your login password',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => const _ChangePasswordDialog(),
                      );
                    },
                  ),
                  _LabActionTile(
                    icon: Icons.logout,
                    label: 'Log out',
                    subtitle: 'Sign out from this lab account',
                    destructive: true,
                    onTap: () => AppLogout.confirmAndSignOut(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditDialog(
    BuildContext context, {
    required String labId,
    required String field,
    required String currentValue,
    bool optional = false,
  }) async {
    final parsedPhone = FormValidators.parsePhone(currentValue);
    final initialText = field == 'Phone' ? parsedPhone.localNumber : currentValue;
    final controller = TextEditingController(text: initialText);
    var dialCode = parsedPhone.dialCode;
    var saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              final trimmed = controller.text.trim();
              if (!optional && trimmed.isEmpty) {
                setDialogState(() => errorText = '$field is required');
                return;
              }
              if (field == 'Email' && trimmed.isNotEmpty) {
                final emailError = FormValidators.email(trimmed);
                if (emailError != null) {
                  setDialogState(() => errorText = emailError);
                  return;
                }
              }
              if (field == 'Phone') {
                final phoneError = FormValidators.phoneLocal(controller.text, dialCode: dialCode);
                if (phoneError != null) {
                  setDialogState(() => errorText = phoneError);
                  return;
                }
              }

              final phoneValue = field == 'Phone'
                  ? ContactChangeVerification.canonicalMobile(
                      dialCode,
                      controller.text.trim(),
                    )
                  : null;
              final emailValue = field == 'Email'
                  ? ContactChangeVerification.canonicalEmail(trimmed)
                  : null;

              if (field == 'Phone' &&
                  !ContactChangeVerification.mobilesEqual(phoneValue!, currentValue)) {
                final verified = await ContactChangeVerification.verifyIfNeeded(
                  context: context,
                  channel: ContactVerificationChannel.mobile,
                  destination: phoneValue,
                  purpose: 'verify your new mobile number',
                  verifiedCanonical: null,
                  accentColor: _labPurple,
                );
                if (!context.mounted) return;
                if (!verified) return;
              }

              if (field == 'Email' &&
                  !ContactChangeVerification.emailsEqual(emailValue!, currentValue)) {
                final verified = await ContactChangeVerification.verifyIfNeeded(
                  context: context,
                  channel: ContactVerificationChannel.email,
                  destination: trimmed,
                  purpose: 'verify your new email address',
                  verifiedCanonical: null,
                  accentColor: _labPurple,
                );
                if (!context.mounted) return;
                if (!verified) return;
              }

              setDialogState(() {
                saving = true;
                errorText = null;
              });

              final saveError = await LabRegistry.updateLabProfile(
                labId: labId,
                labName: field == 'Lab name' ? trimmed : null,
                phone: phoneValue,
                email: emailValue,
                gstNumber: field == 'GST number (optional)' && trimmed.isNotEmpty ? trimmed : null,
                clearGstNumber: field == 'GST number (optional)' && trimmed.isEmpty,
              );

              if (!context.mounted) return;
              if (saveError != null) {
                setDialogState(() {
                  saving = false;
                  errorText = saveError;
                });
                return;
              }

              Navigator.pop(context);
              AppToast.info(dialogContext, '$field updated successfully');
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Edit $field', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errorText != null) ...[
                      Text(
                        errorText!,
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (field == 'Phone')
                      PhoneNumberField(
                        controller: controller,
                        initialDialCode: dialCode,
                        onDialCodeChanged: (code) => dialCode = code,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          helperText: 'OTP verification required when changing your number',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      TextField(
                        controller: controller,
                        maxLines: field == 'Address' ? 4 : 1,
                        minLines: field == 'Address' ? 2 : 1,
                        keyboardType: field == 'Email' ? TextInputType.emailAddress : TextInputType.text,
                        textCapitalization: field == 'GST number (optional)'
                            ? TextCapitalization.characters
                            : TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: field,
                          hintText: optional ? 'Leave blank if not applicable' : null,
                          helperText: field == 'Email'
                              ? 'OTP verification required when changing your email'
                              : null,
                          alignLabelWithHint: field == 'Address',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  style: FilledButton.styleFrom(backgroundColor: _labPurple),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }
}

class _LabHeroCard extends StatelessWidget {
  const _LabHeroCard({
    required this.lab,
    required this.connectedDoctors,
  });

  final RegisteredLabProfile lab;
  final int connectedDoctors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_labPurple, Color(0xFF6D28D9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _labPurple.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceOf(context).withValues(alpha: 0.28)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _labInitial(lab.labName),
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.surfaceOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lab.labName,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surfaceOf(context),
                        height: 1.2,
                      ),
                    ),
                    if (lab.area.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        lab.area,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.surfaceOf(context).withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _HeroChip(
                          icon: Icons.verified_outlined,
                          label: lab.verified ? 'Verified lab' : 'Diagnostic Lab',
                        ),
                        if (connectedDoctors > 0)
                          _HeroChip(
                            icon: Icons.people_outline,
                            label: '$connectedDoctors connected doctors',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (lab.licenseNumber.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, size: 16, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'License · ${lab.licenseNumber}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.surfaceOf(context).withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.surfaceOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabProfileSection extends StatelessWidget {
  const _LabProfileSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _lineColor),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _lineColor),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LabInfoTile extends StatelessWidget {
  const _LabInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder = '—',
    this.onEdit,
    this.locked = false,
    this.supportMessage,
  });

  final IconData icon;
  final String label;
  final String value;
  final String placeholder;
  final VoidCallback? onEdit;
  final bool locked;
  final String? supportMessage;

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? placeholder : value;
    final isPlaceholder = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _labPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _labPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  display,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isPlaceholder ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: _labPurple,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            )
          else if (locked)
            IconButton(
              onPressed: supportMessage == null
                  ? null
                  : () {
                      AppToast.info(context, supportMessage!);
                    },
              icon: const Icon(Icons.lock_outline, size: 18),
              color: AppColors.textSecondaryOf(context),
              tooltip: 'Locked',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _LabActionTile extends StatelessWidget {
  const _LabActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : _labPurple;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: destructive ? AppColors.error : AppColors.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _updatePassword() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    if (current.isEmpty || newPass.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await FirebaseAuthService.instance.updatePassword(current, newPass);
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.info(context, 'Password updated successfully!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Change password', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      content: scrollableDialogContent(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(_error!, style: GoogleFonts.inter(color: AppColors.error, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _updatePassword,
          style: FilledButton.styleFrom(backgroundColor: _labPurple),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

class _AddressEditDialog extends StatefulWidget {
  const _AddressEditDialog({required this.labId, required this.lab});

  final String labId;
  final RegisteredLabProfile lab;

  @override
  State<_AddressEditDialog> createState() => _AddressEditDialogState();
}

class _AddressEditDialogState extends State<_AddressEditDialog> {
  late final _address1Controller = TextEditingController(text: widget.lab.addressLine1);
  late final _address2Controller = TextEditingController(text: widget.lab.addressLine2);
  late final _pincodeController = TextEditingController(text: widget.lab.pincode);
  
  late String? _country = widget.lab.country.isNotEmpty ? widget.lab.country : null;
  late String? _state = widget.lab.state.isNotEmpty ? widget.lab.state : null;
  late String? _city = widget.lab.city.isNotEmpty ? widget.lab.city : null;

  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _address1Controller.dispose();
    _address2Controller.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a1 = _address1Controller.text.trim();
    final pc = _pincodeController.text.trim();
    if (a1.isEmpty || pc.isEmpty || _city == null || _state == null || _country == null) {
      setState(() => _errorText = 'Please fill all required address fields.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final err = await LabRegistry.updateLabProfile(
      labId: widget.labId,
      addressLine1: a1,
      addressLine2: _address2Controller.text.trim(),
      country: _country,
      state: _state,
      city: _city,
      pincode: pc,
    );

    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _errorText = err;
      });
      return;
    }

    Navigator.pop(context);
    AppToast.info(context, 'Address updated successfully');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Address', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorText != null) ...[
              Text(
                _errorText!,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.error),
              ),
              const SizedBox(height: 12),
            ],
            RegistrationAddressSection(
              initialCountry: _country,
              initialState: _state,
              initialCity: _city,
              onCountryChanged: (v) => setState(() => _country = v),
              onStateChanged: (v) => setState(() => _state = v),
              onCityChanged: (v) => setState(() => _city = v),
              address1Controller: _address1Controller,
              address2Controller: _address2Controller,
              pinCodeController: _pincodeController,
              accentColor: AppColors.labPurple,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: _labPurple),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

