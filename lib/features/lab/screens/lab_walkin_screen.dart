import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/country_phone_codes.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/validators/form_validators.dart';
import '../../patient/lab/models/lab_models.dart';
import '../data/lab_walkin_test_suggestions.dart';
import '../../../widgets/multi_tag_input_field.dart';
import '../../../widgets/phone_number_field.dart';
import '../../../widgets/required_field_label.dart';
import '../data/lab_registry.dart';
import '../data/lab_worklist_store.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../widgets/lab_report_upload_sheet.dart';
import 'lab_all_patients_screen.dart';
import '../../../core/theme/app_typography.dart';

class LabWalkInScreen extends StatefulWidget {
  const LabWalkInScreen({super.key});

  @override
  State<LabWalkInScreen> createState() => _LabWalkInScreenState();
}

class _LabWalkInScreenState extends State<LabWalkInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<String> _tests = [];

  String _gender = AppConstants.genders.first;
  bool _submitting = false;
  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;

  static const _labPurple = AppColors.labPurple;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  List<LabBookingRecord> _todayWalkIns() {
    final labId = LabSession.loggedInLabId;
    final today = DateTime.now();
    return LabWorklistStore.instance.bookings.where((booking) {
      if (booking.labId != labId) return false;
      if (booking.collectionType != LabCollectionType.walkIn.name) return false;
      return booking.dateTime.year == today.year &&
          booking.dateTime.month == today.month &&
          booking.dateTime.day == today.day;
    }).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tests.isEmpty) {
      _snack('Add at least one test');
      return;
    }

    final labId = LabSession.loggedInLabId;
    if (labId.isEmpty) {
      _snack('Lab session not found. Please sign in again.');
      return;
    }

    final age = int.tryParse(_ageController.text.trim());
    if (age == null) return;

    final lab = LabRegistry.findById(labId);
    final labName = lab?.labName ?? LabSession.loggedInLabName;

    setState(() => _submitting = true);

    try {
      final booking = await FirestoreService.instance.labBooking.saveWalkInBooking(
        labId: labId,
        labName: labName.isNotEmpty ? labName : 'Lab',
        patientName: _nameController.text.trim(),
        patientAge: age,
        patientGender: _gender,
        testNames: _tests,
        contactNumber: FormValidators.formatFullPhone(
          _phoneDialCode,
          _phoneController.text.trim(),
        ),
      );
      LabWorklistStore.instance.mergeBookings([booking]);

      if (!mounted) return;
      _nameController.clear();
      _ageController.clear();
      _phoneController.clear();
      setState(() {
        _tests.clear();
        _gender = AppConstants.genders.first;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.info(context, describeUserFacingError(e, fallback: 'Could not add walk-in patient. Please try again.'));
    }
  }

  void _snack(String message) {
    AppToast.info(context, message);
  }

  Future<void> _shareReport(LabBookingRecord booking) async {
    await LabReportUploadSheet.show(context, booking: booking);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LabWorklistStore.instance,
      builder: (context, _) {
        final walkIns = _todayWalkIns();

        return LabPageLayout(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Walk-in Patient',
                          style: GoogleFonts.inter(fontSize: AppTypography.headlineLarge, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LabAllPatientsScreen()),
                          );
                        },
                        style: FilledButton.styleFrom(backgroundColor: _labPurple),
                        child: Text(
                          'View all patients',
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
              const SizedBox(height: 4),
              Text(
                'Register a patient at the lab counter without an app booking.',
                style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s\.\-']")),
                      ],
                      decoration: RequiredFieldLabels.decorate(
                        InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceOf(context),
                        ),
                        'Patient Name',
                        isRequired: true,
                      ),
                      validator: FormValidators.patientName,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: RequiredFieldLabels.decorate(
                              InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceOf(context),
                              ),
                              'Age',
                              isRequired: true,
                            ),
                            validator: FormValidators.walkInAge,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _gender,
                            decoration: RequiredFieldLabels.decorate(
                              InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceOf(context),
                              ),
                              'Gender',
                              isRequired: true,
                            ),
                            items: AppConstants.genders
                                .map(
                                  (gender) => DropdownMenuItem(
                                    value: gender,
                                    child: Text(gender),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _gender = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PhoneNumberField(
                      controller: _phoneController,
                      initialDialCode: _phoneDialCode,
                      onDialCodeChanged: (code) => _phoneDialCode = code,
                      labelText: 'Phone Number',
                      isRequired: true,
                    ),
                    const SizedBox(height: 12),
                    MultiTagInputField(
                      label: 'Tests',
                      hintText: 'e.g. CBC, Lipid profile',
                      addButtonLabel: '+ Add test',
                      tags: _tests,
                      suggestionFetcher: LabWalkInTestSuggestions.matching,
                      onAdd: (value) => setState(() {
                        if (!_tests.any((t) => t.toLowerCase() == value.toLowerCase())) {
                          _tests.add(value);
                        }
                      }),
                      onRemove: (value) => setState(
                        () => _tests.removeWhere((t) => t.toLowerCase() == value.toLowerCase()),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _labPurple,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Add Walk-in'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Container(width: 3, height: 14, color: _labPurple),
                  const SizedBox(width: 8),
                  Text(
                    "Today's walk-ins",
                    style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${walkIns.length})',
                    style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (walkIns.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No walk-in patients registered today',
                      style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                )
              else
                ...walkIns.map(
                  (booking) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.patientName,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          booking.displayTestName,
                          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textPrimaryOf(context)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('hh:mm a').format(booking.dateTime)} · ${booking.status}',
                          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                        ),
                        if (booking.hasReport) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline, size: 15, color: AppColors.pharmacyGreen),
                              const SizedBox(width: 6),
                              Text(
                                'Report sent',
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  color: AppColors.pharmacyGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => _shareReport(booking),
                            icon: const Icon(Icons.upload_file_outlined, size: 18),
                            label: const Text('Share report'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _labPurple,
                              minimumSize: const Size(double.infinity, 40),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      },
    );
  }
}
