import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/pharmacy_notification_store.dart';
import '../models/pharmacy_models.dart';
import 'store_prescription_detail_screen.dart';

class StoreNotificationsScreen extends StatefulWidget {
  const StoreNotificationsScreen({super.key});

  @override
  State<StoreNotificationsScreen> createState() =>
      _StoreNotificationsScreenState();
}

class _StoreNotificationsScreenState extends State<StoreNotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          final allItems = PharmacyNotificationStore.instance.forStore(storeId);
          final newItems = allItems.where((n) => !n.isRead).toList();
          final readItems = allItems.where((n) => n.isRead).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _NotificationTabSwitcher(
                  controller: _tabController,
                  newCount: newItems.length,
                  readCount: readItems.length,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(context, newItems, isNew: true),
                    _buildList(context, readItems, isNew: false),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<PharmacyNotification> items, {
    required bool isNew,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNew
                  ? Icons.notifications_none_rounded
                  : Icons.mark_email_read_outlined,
              size: 48,
              color: AppColors.textSecondaryOf(context).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              isNew ? 'No new notifications' : 'No read notifications',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppColors.borderOf(context)),
      itemBuilder: (context, i) {
        final n = items[i];
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          tileColor:
              n.isRead ? null : AppColors.pharmacyGreen.withValues(alpha: 0.06),
          title: Text(
            n.title,
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(n.message),
              const SizedBox(height: 4),
              Text(
                DateFormat('dd MMM yyyy, hh:mm a').format(n.createdAt),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppTypography.labelSmall,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          onTap: () {
            PharmacyNotificationStore.instance.markRead(n.id);
            if (n.referenceId != null && n.title.contains('prescription')) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StorePrescriptionDetailScreen(
                    deliveryId: n.referenceId!,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class _NotificationTabSwitcher extends StatelessWidget {
  const _NotificationTabSwitcher({
    required this.controller,
    required this.newCount,
    required this.readCount,
  });

  final TabController controller;
  final int newCount;
  final int readCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.borderOf(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _NotificationTabPill(
                  label: 'New',
                  count: newCount,
                  selected: controller.index == 0,
                  accentColor: const Color(0xFF2563EB),
                  icon: Icons.mark_email_unread_outlined,
                  onTap: () => controller.animateTo(0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _NotificationTabPill(
                  label: 'Read',
                  count: readCount,
                  selected: controller.index == 1,
                  accentColor: AppColors.pharmacyGreen,
                  icon: Icons.done_all_rounded,
                  onTap: () => controller.animateTo(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationTabPill extends StatelessWidget {
  const _NotificationTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.accentColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.textPrimaryOf(context)
                          .withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    selected ? accentColor : AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodySmall,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor.withValues(alpha: 0.1)
                      : AppColors.textSecondaryOf(context)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? accentColor
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
