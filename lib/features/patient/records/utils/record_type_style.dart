import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/health_record_models.dart';

class RecordTypeStyle {
  const RecordTypeStyle({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  static RecordTypeStyle forType(HealthRecordType type) {
    return switch (type) {
      HealthRecordType.prescription => const RecordTypeStyle(
          color: AppColors.doctorBlue,
          icon: AppIcons.prescription,
          label: 'Prescription',
        ),
      HealthRecordType.labReport => const RecordTypeStyle(
          color: AppColors.patientTeal,
          icon: Icons.science_outlined,
          label: 'Lab Report',
        ),
      HealthRecordType.imaging => const RecordTypeStyle(
          color: Color(0xFF7C3AED),
          icon: Icons.medical_information_outlined,
          label: 'Imaging',
        ),
      HealthRecordType.discharge => const RecordTypeStyle(
          color: Color(0xFFF59E0B),
          icon: Icons.description_outlined,
          label: 'Discharge',
        ),
      HealthRecordType.vaccination => RecordTypeStyle(
          color: Color(0xFF16A34A),
          icon: Icons.vaccines_outlined,
          label: 'Vaccination',
        ),
      HealthRecordType.other => RecordTypeStyle(
          color: AppColors.textSecondary,
          icon: Icons.folder_outlined,
          label: 'Other',
        ),
    };
  }

  static HealthRecordType? filterToType(String? filter) {
    return switch (filter) {
      'Prescription' => HealthRecordType.prescription,
      'Lab Report' => HealthRecordType.labReport,
      'Imaging' => HealthRecordType.imaging,
      'Discharge' => HealthRecordType.discharge,
      'Vaccination' => HealthRecordType.vaccination,
      'Other' => HealthRecordType.other,
      _ => null,
    };
  }
}
