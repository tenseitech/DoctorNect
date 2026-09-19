import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../pharmacy/data/pharmacy_prescription_store.dart';
import '../../pharmacy/models/pharmacy_models.dart';
import '../shared/doctor_partner_patients_base_screen.dart';

class DoctorStorePatientsScreen extends StatelessWidget {
  const DoctorStorePatientsScreen({
    super.key,
    required this.storeId,
    required this.storeName,
    required this.doctorId,
  });

  final String storeId;
  final String storeName;
  final String doctorId;

  static bool _isDispensed(PharmacyPrescriptionDelivery d) =>
      d.status == PharmacyDeliveryStatus.dispensed ||
      d.status == PharmacyDeliveryStatus.partiallyDispensed;

  static String _dispenseLabel(PharmacyPrescriptionDelivery d) =>
      switch (d.status) {
        PharmacyDeliveryStatus.dispensed => 'Yes',
        PharmacyDeliveryStatus.partiallyDispensed => 'Partial',
        PharmacyDeliveryStatus.viewed || PharmacyDeliveryStatus.sent => 'No',
      };

  static Color? _dispenseColor(PharmacyPrescriptionDelivery d) =>
      switch (d.status) {
        PharmacyDeliveryStatus.dispensed => AppColors.pharmacyGreen,
        PharmacyDeliveryStatus.partiallyDispensed => const Color(0xFFEA580C),
        _ => AppColors.textSecondary,
      };

  static String _substituteLabel(PharmacyPrescriptionDelivery d) {
    final substituted = d.medicineLines
        .where((l) => l.availability == MedicineAvailability.substituted)
        .toList();
    if (substituted.isEmpty) return 'No';

    final names = substituted
        .map((l) =>
            l.substituteName.isNotEmpty ? l.substituteName : l.medicineName)
        .join(', ');
    return 'Yes — $names';
  }

  @override
  Widget build(BuildContext context) {
    return DoctorPartnerPatientsBaseView<PharmacyPrescriptionDelivery>(
      partnerTitle: storeName,
      sectionTitle: 'Patient prescriptions',
      accentColor: AppColors.pharmacyGreen,
      listenable: PharmacyPrescriptionStore.instance,
      allItems: () => PharmacyPrescriptionStore.instance
          .forStoreAndDoctor(storeId, doctorId),
      itemDate: (d) => d.dispensedAt ?? d.sentAt,
      searchPredicate: (d, q) {
        final patient = d.draft.patient.patientName.toLowerCase();
        final rx = d.prescriptionId.toLowerCase();
        final note = d.dispensingNotes.toLowerCase();
        return patient.contains(q) || rx.contains(q) || note.contains(q);
      },
      isCompleted: _isDispensed,
      completedStatusLabel: 'dispensed',
      pendingStatusLabel: 'pending',
      emptyAllMessage: 'No prescriptions sent to this pharmacy yet.',
      tableHeaders: const [
        'Date',
        'Patient',
        'Dispensed',
        'Dispense note',
        'Substitute'
      ],
      columnWidths: const {
        0: FixedColumnWidth(108),
        1: FixedColumnWidth(130),
        2: FixedColumnWidth(88),
        3: FixedColumnWidth(180),
        4: FixedColumnWidth(160),
      },
      rowBuilder: (context, d, dateFormat) => [
        DocPartnerTableBodyCell(dateFormat.format(d.dispensedAt ?? d.sentAt)),
        DocPartnerTableBodyCell(d.draft.patient.patientName, bold: true),
        DocPartnerTableBodyCell(_dispenseLabel(d),
            color: _dispenseColor(d), bold: true),
        DocPartnerTableBodyCell(
            d.dispensingNotes.isEmpty ? '—' : d.dispensingNotes),
        DocPartnerTableBodyCell(_substituteLabel(d)),
      ],
    );
  }
}
