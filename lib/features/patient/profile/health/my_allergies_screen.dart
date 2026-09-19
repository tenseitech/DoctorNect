import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../data/patient_profile_mock.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

class MyAllergiesScreen extends StatefulWidget {
  const MyAllergiesScreen({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<MyAllergiesScreen> createState() => _MyAllergiesScreenState();
}

class _MyAllergiesScreenState extends State<MyAllergiesScreen> {
  final _controller = TextEditingController();
  String? _errorText;

  static const _suggestions = [
    'Dust',
    'Pollen',
    'Peanuts',
    'Penicillin',
    'Shellfish',
    'Latex',
  ];

  List<String> get _items => PatientProfileMock.allergies;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _persist() {
    widget.onChanged();
    unawaited(PatientProfileMock.persistCurrentProfile());
  }

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return FormValidators.required(trimmed, field: 'Allergy');
    }
    final textErr = FormValidators.tagText(trimmed, field: 'Allergy');
    if (textErr != null) return textErr;
    if (_items.length >= 20) return 'Maximum 20 allergies allowed';
    if (_items.any((t) => t.toLowerCase() == trimmed.toLowerCase())) {
      return 'Already added';
    }
    return null;
  }

  void _add([String? value]) {
    final text = (value ?? _controller.text).trim();
    final error = _validate(text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    setState(() {
      _errorText = null;
      PatientProfileMock.allergies.add(text);
      _controller.clear();
    });
    _persist();
  }

  Future<void> _remove(String allergy) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete allergy?',
      message: 'Remove "$allergy" from your profile?',
    );
    if (!confirmed || !mounted) return;

    setState(() => PatientProfileMock.allergies.remove(allergy));
    _persist();
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFEA580C), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'List all known allergies including medicines and food. Doctors use this for safer prescriptions.',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                height: 1.4,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientProfileFormStyles.sectionHeader('Add allergy'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.sentences,
                decoration: PatientProfileFormStyles.fieldDecoration(context, 
                  labelText: 'Allergy name',
                  hintText: 'e.g. Penicillin, Peanuts',
                ).copyWith(errorText: _errorText),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _add(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                minimumSize: const Size(0, 48),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (_suggestions.any((s) => !_items.any((i) => i.toLowerCase() == s.toLowerCase()))) ...[
          const SizedBox(height: 12),
          Text(
            'Quick add',
            style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .where((s) => !_items.any((i) => i.toLowerCase() == s.toLowerCase()))
                .map(
                  (s) => ActionChip(
                    label: Text(s),
                    onPressed: () => _add(s),
                    backgroundColor: AppColors.surfaceOf(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    labelStyle: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textPrimaryOf(context)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 48,
            color: AppColors.patientTeal.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            'No allergies added yet',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add any medicine or food allergies above',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildAllergyTile(String allergy) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PatientProfileFormStyles.recordItemCard(
        context: context,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.patientTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.coronavirus_outlined,
                color: AppColors.patientTeal,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                allergy,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            LabeledRemoveButton(
              label: 'Delete',
              onPressed: () => _remove(allergy),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('My Allergies', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInfoBanner(),
                  const SizedBox(height: 20),
                  _buildAddSection(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PatientProfileFormStyles.sectionHeader(
                    _items.isEmpty
                        ? 'Your allergies'
                        : 'Your allergies (${_items.length})',
                  ),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    _buildEmptyState()
                  else
                    ..._items.map(_buildAllergyTile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
