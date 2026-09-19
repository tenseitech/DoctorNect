import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/session/patient_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

class SupportTicketsHistoryScreen extends StatelessWidget {
  const SupportTicketsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Ticket History', context: context),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('support_tickets')
            .where('patientId', isEqualTo: PatientSession.loggedInPatientId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.patientTeal),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.inter(color: Colors.red),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.patientTeal.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        size: 48,
                        color: AppColors.patientTeal,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tickets raised yet',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If you face any issues, submit a ticket in the support section.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Sort in memory by createdAt descending to avoid index requirement
          final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
          sortedDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['createdAt'] as Timestamp?;
            final bTime = bData['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          return PatientProfileFormStyles.constrainedScrollBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Raised Tickets (${sortedDocs.length})',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                ...sortedDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final issueType = data['issueType'] as String? ?? 'General';
                  final message = data['message'] as String? ?? '';
                  final status = data['status'] as String? ?? 'open';
                  final screenshot = data['screenshotName'] as String?;
                  final timestamp = data['createdAt'] as Timestamp?;

                  Color statusColor;
                  Color statusBg;
                  String statusLabel = status.toUpperCase();

                  switch (status.toLowerCase()) {
                    case 'resolved':
                      statusColor = const Color(0xFF2E7D32); // dark green
                      statusBg = const Color(0xFFE8F5E9); // light green
                      break;
                    case 'in_progress':
                      statusColor = const Color(0xFFE65100); // orange
                      statusBg = const Color(0xFFFFF3E0); // light orange
                      break;
                    default: // 'open'
                      statusColor = const Color(0xFF1565C0); // blue
                      statusBg = const Color(0xFFE3F2FD); // light blue
                  }

                  String formattedDate = '';
                  if (timestamp != null) {
                    formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp.toDate());
                  } else {
                    formattedDate = 'Just now';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Material(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderOf(context), width: 0.5),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.patientTeal.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      issueType,
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.labelMedium,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.patientTeal,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                message,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
                                  color: AppColors.textPrimaryOf(context),
                                  height: 1.4,
                                ),
                              ),
                              if (screenshot != null) ...[
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.attach_file, size: 14, color: AppColors.textSecondaryOf(context)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        screenshot,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: AppTypography.labelMedium,
                                          color: AppColors.textSecondaryOf(context),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              SizedBox(height: 12),
                              Divider(height: 1, color: AppColors.borderOf(context)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Ticket ID: ${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length).toUpperCase()}',
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.labelSmall,
                                      color: AppColors.textSecondaryOf(context),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.labelSmall,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
