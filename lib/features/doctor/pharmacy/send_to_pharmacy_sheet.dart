import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../pharmacy/data/medical_store_registry.dart';
import '../../pharmacy/data/pharmacy_connection_store.dart';
import '../../pharmacy/data/pharmacy_prescription_store.dart';
import '../../pharmacy/models/pharmacy_models.dart';
import '../clinical/models/clinical_models.dart';
import '../../../core/theme/app_typography.dart';

/// Bottom sheet to choose which connected stores receive a prescription.
class SendToPharmacySheet {
  static Future<List<String>?> show(
      BuildContext context, PrescriptionDraft draft) {
    final doctorId = DoctorSession.loggedInDoctorId;
    final connections =
        PharmacyConnectionStore.instance.activeForDoctor(doctorId);
    if (connections.isEmpty) return Future.value(<String>[]);

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SendSheet(connections: connections, draft: draft),
    );
  }
}

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.connections, required this.draft});

  final List<PharmacyConnection> connections;
  final PrescriptionDraft draft;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late final Set<String> _selected =
      widget.connections.map((c) => c.medicalStoreId).toSet();
  bool _sendToAll = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send to Medical Stores',
            style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Prescription for ${widget.draft.patient.patientName}',
            style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Send to all connected stores'),
            value: _sendToAll,
            activeThumbColor: AppColors.pharmacyGreen,
            onChanged: (v) => setState(() {
              _sendToAll = v;
              if (v) {
                _selected
                  ..clear()
                  ..addAll(widget.connections.map((c) => c.medicalStoreId));
              }
            }),
          ),
          if (!_sendToAll) ...[
            const SizedBox(height: 8),
            ...widget.connections.map((c) {
              final store = MedicalStoreRegistry.findById(c.medicalStoreId);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(c.medicalStoreId),
                title: Text(c.storeName),
                subtitle: store != null
                    ? Text(store.address,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(c.medicalStoreId);
                    } else {
                      _selected.remove(c.medicalStoreId);
                    }
                  });
                },
              );
            }),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pharmacyGreen,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
                'Send to ${_selected.length} store${_selected.length == 1 ? '' : 's'}'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, <String>[]),
            child: const Text('Skip — save to EMR only'),
          ),
        ],
      ),
    );
  }
}

/// Shows delivery status per store for a prescription.
class PrescriptionPharmacyStatusSection extends StatelessWidget {
  const PrescriptionPharmacyStatusSection(
      {super.key, required this.prescriptionId});

  final String prescriptionId;

  @override
  Widget build(BuildContext context) {
    final doctorId = DoctorSession.loggedInDoctorId;
    final deliveries = PharmacyPrescriptionStore.instance
        .forDoctor(doctorId)
        .where((d) => d.prescriptionId == prescriptionId)
        .toList();

    if (deliveries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pharmacy delivery',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: AppTypography.bodySmall)),
        const SizedBox(height: 6),
        ...deliveries.map((d) {
          final color = switch (d.status) {
            PharmacyDeliveryStatus.sent => AppColors.doctorBlue,
            PharmacyDeliveryStatus.viewed => const Color(0xFFCA8A04),
            PharmacyDeliveryStatus.partiallyDispensed =>
              const Color(0xFFEA580C),
            PharmacyDeliveryStatus.dispensed => AppColors.pharmacyGreen,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.local_pharmacy, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(d.storeName,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium))),
                Text(
                  _statusLabel(d.status),
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  static String _statusLabel(PharmacyDeliveryStatus s) => switch (s) {
        PharmacyDeliveryStatus.sent => 'Sent',
        PharmacyDeliveryStatus.viewed => 'Viewed',
        PharmacyDeliveryStatus.partiallyDispensed => 'Partial',
        PharmacyDeliveryStatus.dispensed => 'Dispensed',
      };
}
