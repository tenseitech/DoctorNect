import 'package:flutter/material.dart';

import '../../../core/firebase/models/doctor_lab_order.dart';
import '../../../core/theme/app_colors.dart';
import '../clinical/data/lab_order_store.dart';
import '../shared/doctor_partner_patients_base_screen.dart';

class DoctorLabPatientsScreen extends StatelessWidget {
  const DoctorLabPatientsScreen({
    super.key,
    required this.labId,
    required this.labName,
    required this.doctorId,
  });

  final String labId;
  final String labName;
  final String doctorId;

  static bool _isCompleted(DoctorLabOrder o) => o.status == 'completed';

  static String _statusLabel(DoctorLabOrder o) => switch (o.status) {
        'completed' => 'Ready',
        'in_progress' => 'Processing',
        'cancelled' => 'Cancelled',
        _ => 'Pending',
      };

  static Color? _statusColor(DoctorLabOrder o) => switch (o.status) {
        'completed' => AppColors.pharmacyGreen,
        'in_progress' => const Color(0xFFEA580C),
        'cancelled' => AppColors.error,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return DoctorPartnerPatientsBaseView<DoctorLabOrder>(
      partnerTitle: labName,
      sectionTitle: 'Patient test orders',
      accentColor: const Color(0xFF8B5CF6),
      listenable: LabOrderStore.instance,
      allItems: () => LabOrderStore.instance.forLabAndDoctor(labId, doctorId),
      itemDate: (o) => o.createdAt,
      searchPredicate: (o, q) {
        final patient = o.patientName.toLowerCase();
        final tests = o.testNames.join(' ').toLowerCase();
        final note = (o.indication ?? '').toLowerCase();
        return patient.contains(q) || tests.contains(q) || note.contains(q);
      },
      isCompleted: _isCompleted,
      completedStatusLabel: 'completed',
      pendingStatusLabel: 'pending',
      emptyAllMessage: 'No test orders sent to this lab yet.',
      tableHeaders: const [
        'Date',
        'Patient',
        'Tests ordered',
        'Status',
        'Indication / Note'
      ],
      columnWidths: const {
        0: FixedColumnWidth(108),
        1: FixedColumnWidth(130),
        2: FixedColumnWidth(180),
        3: FixedColumnWidth(90),
        4: FixedColumnWidth(160),
      },
      rowBuilder: (context, o, dateFormat) => [
        DocPartnerTableBodyCell(dateFormat.format(o.createdAt)),
        DocPartnerTableBodyCell(o.patientName, bold: true),
        DocPartnerTableBodyCell(o.testNames.join(', ')),
        DocPartnerTableBodyCell(_statusLabel(o),
            color: _statusColor(o), bold: true),
        DocPartnerTableBodyCell(
            o.indication?.trim().isNotEmpty == true ? o.indication! : '—'),
      ],
    );
  }
}
