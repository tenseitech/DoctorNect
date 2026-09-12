import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/firebase/models/doctor_lab_order.dart';
import '../../../../core/theme/app_colors.dart';
import '../../lab/lab_report_screen.dart';

abstract final class PatientLabOrderSheet {
  static Future<void> show(BuildContext context, DoctorLabOrder order) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PatientLabOrderSheet(order: order),
    );
  }
}

class _PatientLabOrderSheet extends StatelessWidget {
  const _PatientLabOrderSheet({required this.order});

  final DoctorLabOrder order;

  String _statusLabel(String status) => switch (status) {
        'completed' => 'Completed',
        'in_progress' => 'In progress',
        'sample_collected' => 'Sample collected',
        'cancelled' => 'Cancelled',
        _ => 'Ordered',
      };

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.patientTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.science_outlined, color: AppColors.patientTeal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lab test order',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat('dd MMM yyyy · hh:mm a').format(order.createdAt),
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (order.patientName.trim().isNotEmpty)
              _InfoRow(
                label: 'Patient',
                value: order.patientAge > 0
                    ? '${order.patientName} (${order.patientAge}y)'
                    : order.patientName,
              ),
            _InfoRow(
              label: 'Booked by',
              value: order.doctorName.trim().startsWith('Dr.')
                  ? order.doctorName.trim()
                  : 'Dr. ${order.doctorName.trim()}',
            ),
            if (order.labName != null && order.labName!.trim().isNotEmpty)
              _InfoRow(label: 'Lab', value: order.labName!),
            _InfoRow(label: 'Status', value: _statusLabel(order.status)),
            _InfoRow(label: 'Urgency', value: order.urgency),
            if (order.indication != null && order.indication!.trim().isNotEmpty)
              _InfoRow(label: 'Indication', value: order.indication!),
            if (order.fastingRequired)
              _InfoRow(label: 'Preparation', value: 'Fasting required'),
            if (order.homeCollection)
              _InfoRow(label: 'Collection', value: 'Home collection requested'),
            const SizedBox(height: 12),
            Text(
              'Tests (${order.testNames.length})',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...order.testNames.map(
              (test) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 6, color: AppColors.patientTeal),
                    const SizedBox(width: 8),
                    Expanded(child: Text(test, style: GoogleFonts.inter(fontSize: 14))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (order.status == 'completed')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LabReportScreen(
                          testName: order.testNames.isNotEmpty ? order.testNames.first : 'Lab test',
                          bookingId: order.orderId,
                          patientId: order.patientId,
                          reportFileName: order.reportFileName,
                          storageUrl: order.reportStorageUrl,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.patientTeal),
                  child: const Text('View report'),
                ),
              ),
            if (order.status == 'completed') const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
