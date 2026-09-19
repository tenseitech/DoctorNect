import '../../../../core/notifications/app_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // FIXED: persist support tickets
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/media/gallery_image_picker.dart';

import '../../../../core/session/patient_session.dart'; // FIXED: attach patient id to ticket
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../data/patient_profile_mock.dart';
import '../widgets/patient_profile_form_styles.dart';
import 'support_tickets_history_screen.dart';
import '../../../../core/theme/app_typography.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _issueController = TextEditingController();
  String _issueType = 'Appointment';
  String? _screenshot;

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  bool _submitting = false;

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    // FIXED: actually persist the ticket to Firestore; only show success on a confirmed write.
    try {
      await FirebaseFirestore.instance.collection('support_tickets').add({
        'patientId': PatientSession.loggedInPatientId,
        'issueType': _issueType,
        'message': _issueController.text.trim(),
        if (_screenshot != null) 'screenshotName': _screenshot,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      setState(() => _submitting = false);
      AppToast.info(context, 'Could not submit your issue. Please try again.');
      return;
    }
    if (!mounted) return; // FIXED: mounted check after await
    setState(() {
      _submitting = false;
      _issueController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    const issueTypes = ['Appointment', 'Records', 'Technical', 'Other'];

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Help & Support', context: context),
      body: Form(
        key: _formKey,
        child: PatientProfileFormStyles.constrainedScrollBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PatientProfileFormStyles.contentSurface(context: context, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PatientProfileFormStyles.sectionHeader('FAQs'),
                    const SizedBox(height: 16),
                    ...PatientProfileMock.faqs.asMap().entries.map((e) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderOf(context), width: 0.5),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                          title: Text(
                            e.value.question,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: AppTypography.bodyMedium),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  e.value.answer,
                                  style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PatientProfileFormStyles.contentSurface(context: context, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PatientProfileFormStyles.sectionHeader('Report an issue'),
                    const SizedBox(height: 16),
                    PatientProfileFormStyles.sectionHeader('Issue category'),
                    const SizedBox(height: 8),
                    PatientProfileFormStyles.issueTypeChips(
                      options: issueTypes,
                      selected: _issueType,
                      onSelected: (v) => setState(() => _issueType = v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _issueController,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: PatientProfileFormStyles.fieldDecoration(context, 
                        labelText: 'Description',
                        alignLabelWithHint: true,
                      ),
                      validator: FormValidators.helpMessage,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await GalleryImagePicker.pickSingle();
                          if (picked != null) {
                            setState(() => _screenshot = picked.name);
                          }
                        },
                        icon: const Icon(Icons.upload),
                        label: Text(_screenshot ?? 'Upload screenshot'),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.patientTeal),
                      ),
                    ),
                    const SizedBox(height: 16),
                    PatientProfileFormStyles.cardActionButton(
                      onPressed: _submitting ? null : _submitIssue,
                      label: _submitting ? 'Submitting...' : 'Submit',
                      fullWidth: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PatientProfileFormStyles.contentSurface(context: context, child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, color: AppColors.patientTeal),
                  title: Text('Raised tickets history'),
                  subtitle: Text('View status of your submitted tickets'),
                  trailing: Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupportTicketsHistoryScreen()),
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
