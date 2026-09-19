import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../lab/lab_report_screen.dart';
import '../../../../core/theme/app_typography.dart';

abstract final class PatientBloodTestSheet {
  static Future<void> show(BuildContext context, LabBookingRecord booking) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PatientBloodTestSheet(booking: booking),
    );
  }
}

class _PatientBloodTestSheet extends StatelessWidget {
  const _PatientBloodTestSheet({required this.booking});

  final LabBookingRecord booking;

  String _statusLabel(String status) => switch (status.toLowerCase()) {
        'completed' => booking.hasReport ? 'Report ready' : 'Completed',
        'processing' => 'Processing',
        'requested' => 'Awaiting lab approval',
        'declined' => 'Declined by lab',
        'cancelled' => 'Cancelled',
        _ => 'Confirmed',
      };

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    final labName = booking.labName?.trim().isNotEmpty == true ? booking.labName!.trim() : 'Lab';
    final tests = booking.allTestNames;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bloodtype_outlined, color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.displayTestName,
                          style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd MMM yyyy · hh:mm a').format(booking.dateTime),
                          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (tests.length > 1) ...[
                Text(
                  '${tests.length} tests in this booking',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.labPurple,
                  ),
                ),
                const SizedBox(height: 10),
                ...tests.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: AppColors.labPurple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textPrimaryOf(context), height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (booking.patientName.trim().isNotEmpty)
                _InfoRow(label: 'Patient', value: booking.patientName),
              _InfoRow(label: 'Booked by', value: 'Patient'),
              _InfoRow(label: 'Lab', value: labName),
              _InfoRow(label: 'Status', value: _statusLabel(booking.status)),
              _InfoRow(label: 'Slot', value: booking.slotLabel),
              _InfoRow(
                label: 'Collection',
                value: booking.collectionType == 'home' ? 'Home collection' : 'Walk-in',
              ),
              if (booking.address.trim().isNotEmpty)
                _InfoRow(label: 'Address', value: booking.address),
              const SizedBox(height: 20),
              if (booking.hasReport)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LabReportScreen(booking: booking),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.patientTeal),
                    child: const Text('View report'),
                  ),
                )
              else
                Text(
                  'Your lab will share the report here once it is ready.',
                  style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
                ),
              const SizedBox(height: 12),
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
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
