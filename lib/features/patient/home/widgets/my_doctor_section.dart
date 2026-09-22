import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/patient_favorites_store.dart';
import '../../data/registered_doctors_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../widgets/patient_favorites_sheets.dart';
import 'home_doctor_tile.dart';
import '../../../../core/theme/app_typography.dart';

class MyDoctorSection extends StatelessWidget {
  const MyDoctorSection({
    super.key,
    required this.onAdd,
    required this.onDoctorTap,
    required this.onBook,
  });

  final VoidCallback onAdd;
  final ValueChanged<MyDoc> onDoctorTap;
  final ValueChanged<MyDoc> onBook;

  static const _maxDoctors = 6;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PatientFavoritesStore.instance,
        RegisteredDoctorsStore.instance,
        SharedAppointmentsStore.instance,
      ]),
      builder: (context, _) {
        final compact = ResponsiveLayout.isCompact(context);
        final doctors = PatientFavoritesStore.instance
            .visibleDoctors()
            .take(_maxDoctors)
            .toList();
        final subtitle = doctors.isEmpty
            ? 'Doctors you have added'
            : doctors.length == 1
                ? '1 doctor in your list'
                : '${doctors.length} doctors in your list';

        return Padding(
          padding:
              EdgeInsets.fromLTRB(16, compact ? 12 : 20, 16, compact ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Doctor',
                          style: GoogleFonts.inter(
                            fontSize: compact ? 14 : 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (doctors.isNotEmpty) _buildAddButton(),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),
              if (doctors.isEmpty)
                HomeDoctorInlineMessage(
                  icon: Icons.person_add_outlined,
                  text:
                      'You haven’t added any doctors yet — add one to get started.',
                  action: _buildAddButton(),
                )
              else
                SizedBox(
                  height: HomeDoctorTile.cardHeight + 4,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    itemCount: doctors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final doctor = doctors[index];
                      return HomeDoctorTile(
                        doctor: doctor,
                        onTap: () => onDoctorTap(doctor),
                        onBook: () => onBook(doctor),
                        onRemove: () => _confirmRemoveDoctor(context, doctor),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddButton() {
    return FilledButton(
      onPressed: onAdd,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.patientTeal,
        foregroundColor: AppColors.white,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Add',
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _confirmRemoveDoctor(BuildContext context, MyDoc doctor) async {
    final confirmed =
        await PatientFavoritesSheets.confirmRemoveDoctor(context, doctor);
    if (!confirmed || !context.mounted) return;
    await PatientFavoritesStore.instance.removeDoctor(doctor.id);
  }
}
