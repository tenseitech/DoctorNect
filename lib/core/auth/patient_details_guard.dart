import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_constants.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../features/patient/booking/utils/booking_flow_helpers.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';

/// Guard that ensures required patient details (age & gender) are filled
/// just-in-time before booking an appointment or creating a record doctors will see.
abstract final class PatientDetailsGuard {
  PatientDetailsGuard._();

  /// Returns true if the patient's age and gender are validly filled.
  static bool hasRequiredDetails() {
    final profile = PatientProfileMock.profile;
    final validAge = profile.age >= 1 && profile.age <= 120;
    final validGender =
        BookingFlowHelpers.resolvePatientGender(profile.gender) != null;
    return validAge && validGender;
  }

  /// Runs [onAllowed] immediately if patient has valid age and gender.
  /// Otherwise, presents a modal bottom sheet collecting age and gender.
  /// Upon saving, persists details to [PatientProfileMock] and executes [onAllowed].
  static Future<bool> run(
    BuildContext context,
    FutureOr<void> Function() onAllowed,
  ) async {
    if (hasRequiredDetails()) {
      await onAllowed();
      return true;
    }

    final saved = await showPatientDetailsSheet(context);
    if (saved == true && hasRequiredDetails()) {
      if (context.mounted) {
        await onAllowed();
      }
      return true;
    }
    return false;
  }

  /// Displays the JIT patient details bottom sheet (or dialog on wide displays).
  static Future<bool?> showPatientDetailsSheet(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);

    if (wide) {
      return showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: AppColors.surfaceOf(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const PatientDetailsSheet(),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: const PatientDetailsSheet(),
      ),
    );
  }
}

/// Modal bottom sheet collecting ONLY required age (1-120) and gender (explicit choice).
/// All other fields (blood group, height, weight, address) remain optional and are NOT asked here.
class PatientDetailsSheet extends StatefulWidget {
  const PatientDetailsSheet({super.key});

  @override
  State<PatientDetailsSheet> createState() => _PatientDetailsSheetState();
}

class _PatientDetailsSheetState extends State<PatientDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ageController;
  String? _selectedGender;
  String? _genderError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = PatientProfileMock.profile;
    _ageController = TextEditingController(
      text: profile.age > 0 ? profile.age.toString() : '',
    );
    _selectedGender = BookingFlowHelpers.resolvePatientGender(profile.gender);
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() {
      _genderError =
          _selectedGender == null ? 'Please select your gender' : null;
    });

    if (!_formKey.currentState!.validate() || _selectedGender == null) {
      return;
    }

    final parsedAge = int.tryParse(_ageController.text.trim());
    if (parsedAge == null || parsedAge < 1 || parsedAge > 120) {
      return;
    }

    setState(() => _saving = true);

    try {
      PatientProfileMock.profile.age = parsedAge;
      PatientProfileMock.profile.gender = _selectedGender!;
      PatientProfileMock.notifyProfileUpdated();
      await PatientProfileMock.persistCurrentProfile();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save details: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppColors.surfaceOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final borderColor = AppColors.borderOf(context);

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.patientTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.patientTeal,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient Details',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please provide your age and gender to continue booking. Doctors need this for proper clinical diagnosis.',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // AGE INPUT
              Text(
                'Age (in years) *',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 28',
                  hintStyle: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    color: textSecondary.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.cake_outlined,
                    size: 20,
                    color: textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  filled: true,
                  fillColor: AppColors.cardBgOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.patientTeal,
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.error,
                      width: 1.5,
                    ),
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Please enter your age';
                  }
                  final age = int.tryParse(text);
                  if (age == null || age < 1 || age > 120) {
                    return 'Please enter a valid age (1-120)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              // GENDER INPUT
              Text(
                'Gender *',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: AppConstants.genders.map((gender) {
                  final isSelected = _selectedGender == gender;
                  return ChoiceChip(
                    label: Text(gender),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedGender = selected ? gender : null;
                        _genderError = null;
                      });
                    },
                    selectedColor:
                        AppColors.patientTeal.withValues(alpha: 0.18),
                    backgroundColor: AppColors.cardBgOf(context),
                    labelStyle: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppColors.patientTeal : textSecondary,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppColors.patientTeal : borderColor,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: isSelected,
                    checkmarkColor: AppColors.patientTeal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  );
                }).toList(),
              ),
              if (_genderError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _genderError!,
                  style: GoogleFonts.inter(
                    color: AppColors.error,
                    fontSize: AppTypography.labelSmall,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              // SAVE & CONTINUE BUTTON
              ElevatedButton(
                onPressed: _saving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.patientTeal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.patientTeal.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Save & Continue',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
