import '../../../core/notifications/app_toast.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/app_logout.dart';
import '../../../core/auth/contact_change_otp_service.dart';
import '../../../core/auth/contact_change_verification.dart';
import '../../../core/firebase/firebase_auth_service.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/legal/medibond_legal_content.dart';
import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../widgets/phone_number_field.dart';
import '../../patient/profile/about/about_screen.dart';
import '../../auth/widgets/registration_address_section.dart';
import '../data/medical_store_registry.dart';
import '../data/pharmacy_connection_store.dart';
import '../models/pharmacy_models.dart';
import '../../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';
import '../../../widgets/verification_submission_card.dart';
import '../../../core/theme/app_typography.dart';

const _lineColor = Color(0xFFE2E8F0);
const _headerBg = Color(0xFFF1F5F9);
const _pharmacyMobileBottomNavHeight = 64.0;

/// Scroll clearance under pharmacy mobile bottom nav (`extendBody: true` in shell).
double _mobileProfileBottomClearance(BuildContext context) {
  final mq = MediaQuery.of(context);
  var safeBottom = math.max(mq.viewPadding.bottom, mq.padding.bottom);
  // iPhone Safari often reports 0; home-indicator devices need ~34px.
  if (safeBottom < 20) safeBottom = 34.0;
  return _pharmacyMobileBottomNavHeight + safeBottom + 24.0;
}

String _storeInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'S';
  return trimmed[0].toUpperCase();
}

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  @override
  void initState() {
    super.initState();
    final storeId = MedicalStoreSession.loggedInStoreId;
    if (storeId.isNotEmpty) {
      unawaited(MedicalStoreRegistry.ensureStoreLoaded(storeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        MedicalStoreRegistry.instance,
        PharmacyConnectionStore.instance,
      ]),
      builder: (context, _) {
        final storeId = MedicalStoreSession.loggedInStoreId;
        final store = MedicalStoreRegistry.findById(storeId);
        if (store == null) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.pharmacyGreen));
        }

        final connectedDoctors =
            PharmacyConnectionStore.instance.activeForStore(storeId).length;
        final compact = ResponsiveLayout.isCompact(context);
        final profileSections = Padding(
          padding:
              EdgeInsets.fromLTRB(compact ? 16 : 24, 20, compact ? 16 : 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileSection(
                title: 'Store details',
                subtitle: 'Registered medical store information',
                rows: [
                  _ProfileField(
                    label: 'Store name',
                    value: store.storeName,
                    onEdit: () => _showEditDialog(
                      context,
                      storeId: storeId,
                      field: 'Store name',
                      currentValue: store.storeName,
                    ),
                  ),
                  _ProfileField(
                    label: 'Owner',
                    value: store.ownerName,
                    locked: true,
                    supportMessage:
                        'Owner name is permanent. Contact support@doctornect.com to request a change.',
                  ),
                  _ProfileField(
                    label: 'Address',
                    value: store.address,
                    onEdit: () => showDialog(
                      context: context,
                      builder: (context) =>
                          _AddressEditDialog(storeId: storeId, store: store),
                    ),
                  ),
                  _ProfileField(
                    label: 'Drug license',
                    value: store.drugLicenseNumber,
                    locked: true,
                    supportMessage:
                        'Drug license cannot be changed after registration. Contact support@doctornect.com if this needs to be corrected.',
                  ),
                  _ProfileField(
                    label: 'GST number (optional)',
                    value: store.gstNumber?.trim() ?? '',
                    onEdit: () => _showEditDialog(
                      context,
                      storeId: storeId,
                      field: 'GST number (optional)',
                      currentValue: store.gstNumber?.trim() ?? '',
                      optional: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ProfileSection(
                title: 'Contact',
                subtitle: 'How doctors and patients reach your store',
                rows: [
                  _ProfileField(
                    label: 'Phone',
                    value: store.phone,
                    onEdit: () => _showEditDialog(
                      context,
                      storeId: storeId,
                      field: 'Phone',
                      currentValue: store.phone,
                    ),
                  ),
                  _ProfileField(
                    label: 'Email (immutable)',
                    value: store.email,
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
                      const SizedBox(height: 20),
                      _ProfileSection(
                        title: 'Advertising',
                        subtitle: 'Grow prescription orders & patient reach',
                        rows: const [],
                        footer: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                final isVerified =
                                    store.drugLicenseNumber.isNotEmpty;
                                PromotedAdsManagementScreen.open(
                                  context,
                                  providerType: 'pharmacy',
                                  providerId: storeId,
                                  providerEmail: store.email,
                                  providerContact: store.phone,
                                  isVerified: isVerified,
                                );
                              },
                              icon: const Icon(Icons.campaign_rounded,
                                  size: 20, color: AppColors.pharmacyGreen),
                              label: Text(
                                'Promote Banner Ad on Patient Home',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.pharmacyGreen,
                                side: const BorderSide(
                                    color: AppColors.pharmacyGreen),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _ProfileSection(
                title: 'Account',
                subtitle: 'Security and session',
                rows: const [],
                footer: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(
                              accentColor: AppColors.pharmacyGreen,
                              audience: LegalAudience.pharmacy,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline, size: 20),
                      label: Text(
                        'About',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimaryOf(context),
                        side: const BorderSide(color: _lineColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const _ChangePasswordDialog(),
                        );
                      },
                      icon: const Icon(Icons.lock_reset_outlined, size: 20),
                      label: Text(
                        'Change password',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimaryOf(context),
                        side: const BorderSide(color: _lineColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => AppLogout.confirmAndSignOut(context),
                      icon: const Icon(Icons.logout,
                          size: 20, color: AppColors.error),
                      label: Text(
                        'Log out',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (compact) {
          final bottomClearance = _mobileProfileBottomClearance(context);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _ProfileHeaderBand(
                store: store,
                connectedDoctors: connectedDoctors,
              ),
              const VerificationSubmissionCard(role: UserType.medicalStore),
              profileSections,
              SizedBox(height: bottomClearance),
            ],
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _ProfileHeaderBand(
                  store: store,
                  connectedDoctors: connectedDoctors,
                ),
                const VerificationSubmissionCard(role: UserType.medicalStore),
                profileSections,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditDialog(
    BuildContext context, {
    required String storeId,
    required String field,
    required String currentValue,
    bool optional = false,
  }) async {
    final parsedPhone = FormValidators.parsePhone(currentValue);
    final initialText =
        field == 'Phone' ? parsedPhone.localNumber : currentValue;
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
                final phoneError = FormValidators.phoneLocal(controller.text,
                    dialCode: dialCode);
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
                  !ContactChangeVerification.mobilesEqual(
                      phoneValue!, currentValue)) {
                final verified = await ContactChangeVerification.verifyIfNeeded(
                  context: context,
                  channel: ContactVerificationChannel.mobile,
                  destination: phoneValue,
                  purpose: 'verify your new mobile number',
                  verifiedCanonical: null,
                  accentColor: AppColors.pharmacyGreen,
                );
                if (!context.mounted) return;
                if (!verified) return;
              }

              if (field == 'Email' &&
                  !ContactChangeVerification.emailsEqual(
                      emailValue!, currentValue)) {
                final verified = await ContactChangeVerification.verifyIfNeeded(
                  context: context,
                  channel: ContactVerificationChannel.email,
                  destination: trimmed,
                  purpose: 'verify your new email address',
                  verifiedCanonical: null,
                  accentColor: AppColors.pharmacyGreen,
                );
                if (!context.mounted) return;
                if (!verified) return;
              }

              setDialogState(() {
                saving = true;
                errorText = null;
              });

              final saveError = await MedicalStoreRegistry.updateStoreProfile(
                storeId: storeId,
                storeName: field == 'Store name' ? trimmed : null,
                phone: phoneValue,
                email: emailValue,
                gstNumber:
                    field == 'GST number (optional)' && trimmed.isNotEmpty
                        ? trimmed
                        : null,
                clearGstNumber:
                    field == 'GST number (optional)' && trimmed.isEmpty,
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
            }

            return AlertDialog(
              title: Text('Edit $field',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (errorText != null) ...[
                      Text(
                        errorText!,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.error),
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
                          helperText:
                              'OTP verification required when changing your number',
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      TextField(
                        controller: controller,
                        maxLines: field == 'Address' ? 4 : 1,
                        minLines: field == 'Address' ? 2 : 1,
                        keyboardType: field == 'Email'
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                        textCapitalization: field == 'GST number (optional)'
                            ? TextCapitalization.characters
                            : TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: field,
                          hintText:
                              optional ? 'Leave blank if not applicable' : null,
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
                ElevatedButton(
                  onPressed: saving ? null : save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pharmacyGreen,
                    foregroundColor: AppColors.white,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
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

class _ProfileField {
  const _ProfileField({
    required this.label,
    required this.value,
    this.onEdit,
    this.locked = false,
    this.supportMessage,
  });

  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool locked;
  final String? supportMessage;
}

class _ProfileHeaderBand extends StatelessWidget {
  const _ProfileHeaderBand({
    required this.store,
    required this.connectedDoctors,
  });

  final MedicalStoreProfile store;
  final int connectedDoctors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.pharmacyGreen, Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color:
                          AppColors.surfaceOf(context).withValues(alpha: 0.28)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _storeInitial(store.storeName),
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineLarge,
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
                      store.storeName,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineMedium,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surfaceOf(context),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      store.ownerName,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.surfaceOf(context)
                            .withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context)
                            .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Medical Store',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surfaceOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderStatPill(
                  icon: Icons.people_outline, label: '$connectedDoctors Dr.'),
              _HeaderStatPill(
                  icon: Icons.badge_outlined, label: store.drugLicenseNumber),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStatPill extends StatelessWidget {
  const _HeaderStatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              fontWeight: FontWeight.w700,
              color: AppColors.surfaceOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.subtitle,
    required this.rows,
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<_ProfileField> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 14, color: AppColors.pharmacyGreen),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 10),
        if (rows.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _lineColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(color: _headerBg),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Field',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Details',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < rows.length; i++)
                    _ProfileTableRow(
                      field: rows[i],
                      showTopBorder: true,
                    ),
                ],
              ),
            ),
          ),
        if (footer != null) ...[
          if (rows.isNotEmpty) const SizedBox(height: 12),
          footer!,
        ],
      ],
    );
  }
}

class _ProfileTableRow extends StatelessWidget {
  const _ProfileTableRow({
    required this.field,
    required this.showTopBorder,
  });

  final _ProfileField field;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showTopBorder
            ? const Border(top: BorderSide(color: _lineColor))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                field.label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      field.value.trim().isEmpty ? '—' : field.value,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  if (field.onEdit != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: field.onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.pharmacyGreen.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ] else if (field.locked) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: field.supportMessage ??
                          'This field can only be updated by DoctorNect support',
                      child: InkWell(
                        onTap: field.supportMessage == null
                            ? null
                            : () {
                                AppToast.info(context, field.supportMessage!);
                              },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: AppColors.textSecondaryOf(context)
                                .withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                  ],
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
      title: Text('Change Password',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      content: scrollableDialogContent(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(_error!,
                  style: const TextStyle(
                      color: Colors.red, fontSize: AppTypography.bodySmall)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
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
        ElevatedButton(
          onPressed: _isLoading ? null : _updatePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.pharmacyGreen,
            foregroundColor: AppColors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

class _AddressEditDialog extends StatefulWidget {
  const _AddressEditDialog({required this.storeId, required this.store});

  final String storeId;
  final MedicalStoreProfile store;

  @override
  State<_AddressEditDialog> createState() => _AddressEditDialogState();
}

class _AddressEditDialogState extends State<_AddressEditDialog> {
  late final _address1Controller =
      TextEditingController(text: widget.store.addressLine1);
  late final _address2Controller =
      TextEditingController(text: widget.store.addressLine2);
  late final _pincodeController =
      TextEditingController(text: widget.store.pincode);

  late String? _country =
      widget.store.country.isNotEmpty ? widget.store.country : null;
  late String? _state =
      widget.store.state.isNotEmpty ? widget.store.state : null;
  late String? _city = widget.store.city.isNotEmpty ? widget.store.city : null;

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
    if (a1.isEmpty ||
        pc.isEmpty ||
        _city == null ||
        _state == null ||
        _country == null) {
      setState(() => _errorText = 'Please fill all required address fields.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final err = await MedicalStoreRegistry.updateStoreProfile(
      storeId: widget.storeId,
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
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Address',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorText != null) ...[
              Text(
                _errorText!,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall, color: AppColors.error),
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
              accentColor: AppColors.pharmacyGreen,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.pharmacyGreen,
            foregroundColor: AppColors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
