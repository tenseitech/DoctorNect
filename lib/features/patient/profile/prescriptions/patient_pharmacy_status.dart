import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../pharmacy/models/pharmacy_models.dart';
import '../../../../core/theme/app_typography.dart';

class PatientPharmacyStatus {
  const PatientPharmacyStatus({
    required this.storeName,
    required this.status,
    required this.sentAt,
  });

  final String storeName;
  final PharmacyDeliveryStatus status;
  final DateTime sentAt;

  String get label => switch (status) {
        PharmacyDeliveryStatus.sent => 'Sent to $storeName',
        PharmacyDeliveryStatus.viewed => '$storeName is preparing your order',
        PharmacyDeliveryStatus.partiallyDispensed => 'Partially ready at $storeName',
        PharmacyDeliveryStatus.dispensed => 'Ready for pickup at $storeName',
      };

  Color get color => switch (status) {
        PharmacyDeliveryStatus.sent => Colors.blue.shade700,
        PharmacyDeliveryStatus.viewed => Colors.orange.shade700,
        PharmacyDeliveryStatus.partiallyDispensed => Colors.purple.shade700,
        PharmacyDeliveryStatus.dispensed => AppColors.pharmacyGreen,
      };

  IconData get icon => switch (status) {
        PharmacyDeliveryStatus.dispensed => Icons.check_circle_outline,
        PharmacyDeliveryStatus.partiallyDispensed => Icons.inventory_2_outlined,
        _ => Icons.local_pharmacy_outlined,
      };
}

class PatientPharmacyStatusChip extends StatelessWidget {
  const PatientPharmacyStatusChip({super.key, required this.status});

  final PatientPharmacyStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: status.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(status.icon, size: 16, color: status.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status.label,
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w600, color: status.color),
            ),
          ),
        ],
      ),
    );
  }
}
