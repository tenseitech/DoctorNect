import '../../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/overflow_safe_layout.dart';
import '../../../../widgets/phone_number_field.dart';
import '../../../../widgets/required_field_label.dart';
import '../../../../widgets/searchable_multi_select_field.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/section_save_bar.dart';
import '../../../../core/theme/app_typography.dart';

class PersonalInfoSection extends StatefulWidget {
  const PersonalInfoSection({super.key});

  @override
  State<PersonalInfoSection> createState() => _PersonalInfoSectionState();
}

class _PersonalInfoSectionState extends State<PersonalInfoSection> {
  final _formKey = GlobalKey<FormState>();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();

  late final _name = TextEditingController(text: _p.fullName);
  late final String _gender = AppConstants.normalizeGender(_p.gender);
  late final _mobileParsed = FormValidators.parsePhone(_p.mobile);
  late final _mobile = TextEditingController(text: _mobileParsed.localNumber);
  late final String _mobileDialCode = _mobileParsed.dialCode;
  late final _email = TextEditingController(text: _p.email);
  late Set<String> _languages = Set<String>.from(_p.languages);

  bool _dirty = false;

  DoctorProfileStore get _store => DoctorProfileStore.instance;
  DoctorProfileData get _p => _store.profile;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _showContactAdminDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.doctorBlue, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Admin Verification Required',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: AppTypography.headlineSmall),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: scrollableDialogContent(
          context: ctx,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Doctor mobile numbers are verified for medical licensing and regulatory compliance. To update your registered phone number, please contact administration with your medical registration details.',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.doctorBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 16, color: AppColors.doctorBlue),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'support@doctornect.com',
                            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600, color: AppColors.doctorBlue),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 16, color: AppColors.doctorBlue),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '+91 80000 00000 (Admin Desk)',
                            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppColors.doctorBlue),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? true)) return;

    _p.fullName = _name.text.trim();
    _p.gender = _gender;
    _p.languages = List<String>.from(_languages);

    try {
      await _store.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not save changes. Please check your connection and try again.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _dirty = false;
    });

    Navigator.pop(context, true);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _mobileFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Information')),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.1),
                                  child: Text(
                                    _name.text.trim().isNotEmpty
                                        ? _name.text.trim()[0].toUpperCase()
                                        : DoctorProfileStore.displayName.isNotEmpty
                                            ? DoctorProfileStore.displayName[0].toUpperCase()
                                            : 'D',
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.headlineLarge,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.doctorBlue,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      AppToast.info(context, 'Mock: Photo uploaded');
                                    },
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: AppColors.doctorBlue,
                                      child: const Icon(Icons.camera_alt, size: 16, color: AppColors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              DoctorProfileStore.displayNameWithPrefix,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineSmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            SizedBox(height: 24),
                            TextFormField(
                              controller: _name,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Full name',
                                filled: true,
                                fillColor: AppColors.cardBgOf(context),
                              ),
                            ),
                            SizedBox(height: 12),
                            TextFormField(
                              readOnly: true,
                              initialValue: _p.dateOfBirth == null
                                  ? 'Not set'
                                  : DateFormat('dd MMM yyyy').format(_p.dateOfBirth!),
                              decoration: InputDecoration(
                                labelText: 'Date of birth',
                                filled: true,
                                fillColor: AppColors.cardBgOf(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _gender,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Gender'),
                              items: AppConstants.genders
                                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                  .toList(),
                              onChanged: null,
                            ),
                            const SizedBox(height: 12),
                            PhoneNumberField(
                              controller: _mobile,
                              focusNode: _mobileFocus,
                              readOnly: true,
                              onTap: _showContactAdminDialog,
                              initialPhone: _p.mobile,
                              initialDialCode: _mobileDialCode,
                              labelText: 'Mobile number',
                              suffixIcon: TextButton.icon(
                                onPressed: _showContactAdminDialog,
                                icon: const Icon(Icons.lock_outline, size: 14),
                                label: const Text('Contact Admin', style: TextStyle(fontSize: AppTypography.labelMedium)),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.doctorBlue,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                              helperText: 'Doctor mobile number is locked for verification. Contact admin to request a change.',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _email,
                              focusNode: _emailFocus,
                              readOnly: true,
                              showCursor: false,
                              enableInteractiveSelection: false,
                              keyboardType: TextInputType.emailAddress,
                              decoration: RequiredFieldLabels.decorate(
                                const InputDecoration(
                                  suffixIcon: null,
                                ),
                                'Email address (immutable)',
                                isRequired: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SearchableMultiSelectField(
                              label: 'Languages spoken',
                              options: AppConstants.languages,
                              selected: _languages,
                              placeholder: 'Select languages',
                              searchHint: 'Search languages...',
                              accentColor: AppColors.doctorBlue,
                              onChanged: (v) {
                                setState(() => _languages = v);
                                _markDirty();
                              },
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
