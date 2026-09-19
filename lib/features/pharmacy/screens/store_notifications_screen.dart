import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/pharmacy_notification_store.dart';
import 'store_prescription_detail_screen.dart';
import '../../../core/theme/app_typography.dart';

class StoreNotificationsScreen extends StatelessWidget {
  const StoreNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storeId = MedicalStoreSession.loggedInStoreId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                PharmacyNotificationStore.instance.markAllReadForStore(storeId),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: PharmacyNotificationStore.instance,
        builder: (context, _) {
          final items = PharmacyNotificationStore.instance.forStore(storeId);
          if (items.isEmpty) {
            return Center(
              child: Text('No notifications',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondaryOf(context))),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                tileColor: n.isRead
                    ? null
                    : AppColors.pharmacyGreen.withValues(alpha: 0.06),
                title: Text(n.title,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.message),
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a').format(n.createdAt),
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
                onTap: () {
                  PharmacyNotificationStore.instance.markRead(n.id);
                  if (n.referenceId != null &&
                      n.title.contains('prescription')) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StorePrescriptionDetailScreen(
                            deliveryId: n.referenceId!),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
