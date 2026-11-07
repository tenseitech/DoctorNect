import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/firebase/firestore_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/doctor_patient_cutover_flag.dart';
import '../../../../core/session/patient_session.dart';
import '../../../../core/supabase/supabase_bootstrap.dart';
import '../../../../core/supabase/support_ticket_supabase_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/patient_profile_form_styles.dart';
import 'support_ticket_chat_screen.dart';
import '../../../../core/theme/app_typography.dart';

class _TicketItemData {
  const _TicketItemData({
    required this.ticketId,
    required this.issueType,
    required this.message,
    required this.status,
    this.screenshot,
    this.createdAt,
  });

  final String ticketId;
  final String issueType;
  final String message;
  final String status;
  final String? screenshot;
  final DateTime? createdAt;
}

class SupportTicketsHistoryScreen extends StatelessWidget {
  const SupportTicketsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar(
        'Ticket History',
        context: context,
      ),
      body: (DoctorPatientCutoverFlag.isEnabled && SupabaseBootstrap.isReady)
          ? _buildSupabaseTickets(context)
          : _buildFirestoreTickets(context),
    );
  }

  Widget _buildSupabaseTickets(BuildContext context) {
    return StreamBuilder<List<SupportTicketModel>>(
      stream: SupportTicketSupabaseRepository.instance.watchMyTickets(
        patientId: PatientSession.loggedInPatientId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.patientTeal),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(fontFamily: 'Inter', color: Colors.red),
            ),
          );
        }

        final tickets = snapshot.data ?? [];
        if (tickets.isEmpty) {
          return _buildEmptyState(context);
        }

        final items = tickets
            .map((t) => _TicketItemData(
                  ticketId: t.ticketId,
                  issueType: t.issueType,
                  message: t.message,
                  status: t.status,
                  screenshot: t.screenshotName,
                  createdAt: t.createdAt,
                ))
            .toList();

        return _buildTicketsList(context, items);
      },
    );
  }

  Widget _buildFirestoreTickets(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreClient.instance
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
              style: const TextStyle(fontFamily: 'Inter', color: Colors.red),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(context);
        }

        // Sort in memory by createdAt descending
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

        final items = sortedDocs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = data['createdAt'] as Timestamp?;
          return _TicketItemData(
            ticketId: doc.id,
            issueType: data['issueType'] as String? ?? 'General',
            message: data['message'] as String? ?? '',
            status: data['status'] as String? ?? 'open',
            screenshot: data['screenshotName'] as String?,
            createdAt: timestamp?.toDate(),
          );
        }).toList();

        return _buildTicketsList(context, items);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If you face any issues, submit a ticket in the support section.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketsList(BuildContext context, List<_TicketItemData> items) {
    return PatientProfileFormStyles.constrainedScrollBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Raised Tickets (${items.length})',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            Color statusColor;
            Color statusBg;
            final statusLabel = item.status.toUpperCase();

            switch (item.status.toLowerCase()) {
              case 'resolved':
                statusColor = const Color(0xFF2E7D32);
                statusBg = const Color(0xFFE8F5E9);
                break;
              case 'in_progress':
                statusColor = const Color(0xFFE65100);
                statusBg = const Color(0xFFFFF3E0);
                break;
              default:
                statusColor = const Color(0xFF1565C0);
                statusBg = const Color(0xFFE3F2FD);
            }

            final formattedDate = item.createdAt != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(item.createdAt!)
                : 'Just now';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Material(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupportTicketChatScreen(
                        ticketId: item.ticketId,
                        issueType: item.issueType,
                        message: item.message,
                        status: item.status,
                        screenshot: item.screenshot,
                        createdAt: item.createdAt ?? DateTime.now(),
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.patientTeal.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.issueType,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: AppTypography.labelMedium,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.patientTeal,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontFamily: 'Inter',
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
                          item.message,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: AppTypography.bodyMedium,
                            color: AppColors.textPrimaryOf(context),
                            height: 1.4,
                          ),
                        ),
                        if (item.screenshot != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.attach_file,
                                size: 14,
                                color: AppColors.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.screenshot!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: AppTypography.labelMedium,
                                    color: AppColors.textSecondaryOf(
                                      context,
                                    ),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: AppColors.borderOf(context),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ticket ID: ${item.ticketId.substring(0, item.ticketId.length > 8 ? 8 : item.ticketId.length).toUpperCase()}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context),
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontFamily: 'Inter',
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
              ),
            );
          }),
        ],
      ),
    );
  }
}
