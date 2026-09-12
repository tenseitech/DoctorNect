import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../booking/booking_flow_screen.dart';
import '../data/patient_favorites_store.dart';
import '../data/registered_doctors_store.dart';
import '../doctor_profile/patient_doctor_profile_screen.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../widgets/labeled_remove_button.dart';
import '../widgets/patient_favorites_sheets.dart';

class MyDoctorsScreen extends StatefulWidget {
  const MyDoctorsScreen({super.key});

  @override
  State<MyDoctorsScreen> createState() => _MyDoctorsScreenState();
}

class _MyDoctorsScreenState extends State<MyDoctorsScreen> {
  final _favoritesStore = PatientFavoritesStore.instance;
  final _doctorsStore = RegisteredDoctorsStore.instance;

  @override
  void initState() {
    super.initState();
    _favoritesStore.addListener(_onChanged);
    _doctorsStore.addListener(_onChanged);
  }

  @override
  void dispose() {
    _favoritesStore.removeListener(_onChanged);
    _doctorsStore.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _favoritesStore.visibleDoctors();

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        centerTitle: true,
        title: Text('My Doctor', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.cardBgOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => PatientFavoritesSheets.showAddDoctorSheet(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveLayout.contentMaxWidth(context).clamp(0, 560),
          ),
          child: doctors.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                  child: Text(
                    'No doctors in your list yet. Tap Add to search registered doctors or book a visit.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context), fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: doctors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doctor = doctors[index];
                    return _MyDoctorManageTile(
                      doctor: doctor,
                      onRemove: () async {
                        final confirmed =
                            await PatientFavoritesSheets.confirmRemoveDoctor(context, doctor);
                        if (!confirmed || !context.mounted) return;
                        await _favoritesStore.removeDoctor(doctor.id);
                      },
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatientDoctorProfileScreen(doctorId: doctor.id),
                          ),
                        );
                      },
                      onBook: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookingFlowScreen(doctorId: doctor.id),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MyDoctorManageTile extends StatelessWidget {
  const _MyDoctorManageTile({
    required this.doctor,
    required this.onRemove,
    required this.onTap,
    required this.onBook,
  });

  final MyDoc doctor;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dr. ${doctor.name}',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doctor.specialization,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                    ),
                    if (doctor.city.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doctor.city,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ],
                ),
              ),
              LabeledRemoveButton(onPressed: onRemove),
              FilledButton(
                onPressed: onBook,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.patientTeal,
                  minimumSize: const Size(64, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Book'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
