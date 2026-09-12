import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../pharmacy/data/pharmacy_connection_store.dart';
import '../../../pharmacy/data/pharmacy_prescription_store.dart';
import '../../../pharmacy/models/pharmacy_models.dart';

class PharmacyDataSection extends StatelessWidget {
  const PharmacyDataSection({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pharmacy Data'),
          bottom: TabBar(
            labelStyle:
                GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
            indicatorColor: AppColors.pharmacyGreen,
            labelColor: AppColors.pharmacyGreen,
            unselectedLabelColor: Colors.grey[600],
            tabs: const [
              Tab(text: 'Connected Stores'),
              Tab(text: 'Prescriptions Sent'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            PharmacyConnectionStore.instance,
            PharmacyPrescriptionStore.instance,
          ]),
          builder: (context, _) {
            final doctorId = DoctorSession.loggedInDoctorId;
            final activeConns =
                PharmacyConnectionStore.instance.activeForDoctor(doctorId);
            final pendingConns =
                PharmacyConnectionStore.instance.pendingForDoctor(doctorId);
            final deliveries =
                PharmacyPrescriptionStore.instance.forDoctor(doctorId);

            return TabBarView(
              children: [
                _ConnectedStoresTab(
                    active: activeConns, pending: pendingConns),
                _PrescriptionsTab(deliveries: deliveries),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Connected stores tab ──────────────────────────────────────────────────────

class _ConnectedStoresTab extends StatelessWidget {
  const _ConnectedStoresTab(
      {required this.active, required this.pending});

  final List<PharmacyConnection> active;
  final List<PharmacyConnection> pending;

  @override
  Widget build(BuildContext context) {
    if (active.isEmpty && pending.isEmpty) {
      return _EmptyState(
        icon: Icons.local_pharmacy_outlined,
        message: 'No connected pharmacy stores yet.',
        color: AppColors.pharmacyGreen,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (active.isNotEmpty) ...[
              _SectionLabel(
                  'Active (${active.length})', AppColors.pharmacyGreen),
              const SizedBox(height: 8),
              ...active.map((c) => _StoreCard(conn: c)),
              const SizedBox(height: 16),
            ],
            if (pending.isNotEmpty) ...[
              _SectionLabel('Pending (${pending.length})', Colors.orange[700]!),
              const SizedBox(height: 8),
              ...pending.map((c) => _StoreCard(conn: c)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.conn});
  final PharmacyConnection conn;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final isActive = conn.status == ConnectionStatus.active;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.pharmacyGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.local_pharmacy_outlined,
                color: AppColors.pharmacyGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conn.storeName,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Since ${df.format(conn.requestedAt)}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.pharmacyGreen.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isActive ? 'Active' : 'Pending',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? AppColors.pharmacyGreen
                    : Colors.orange[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Prescriptions sent tab ────────────────────────────────────────────────────

class _PrescriptionsTab extends StatelessWidget {
  const _PrescriptionsTab({required this.deliveries});
  final List<PharmacyPrescriptionDelivery> deliveries;

  @override
  Widget build(BuildContext context) {
    if (deliveries.isEmpty) {
      return _EmptyState(
        icon: AppIcons.prescription,
        message: 'No prescriptions sent to pharmacies yet.',
        color: AppColors.pharmacyGreen,
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: deliveries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _DeliveryRow(delivery: deliveries[i]),
        ),
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery});
  final PharmacyPrescriptionDelivery delivery;

  Color get _statusColor {
    return switch (delivery.status) {
      PharmacyDeliveryStatus.sent => Colors.blue[600]!,
      PharmacyDeliveryStatus.viewed => Colors.orange[600]!,
      PharmacyDeliveryStatus.partiallyDispensed => Colors.purple[600]!,
      PharmacyDeliveryStatus.dispensed => AppColors.pharmacyGreen,
    };
  }

  String get _statusLabel {
    return switch (delivery.status) {
      PharmacyDeliveryStatus.sent => 'Sent',
      PharmacyDeliveryStatus.viewed => 'Viewed',
      PharmacyDeliveryStatus.partiallyDispensed => 'Partial',
      PharmacyDeliveryStatus.dispensed => 'Dispensed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('hh:mm a');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.pharmacyGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.prescription,
                color: AppColors.pharmacyGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(delivery.storeName,
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  '${delivery.medicineLines.length} medicine(s)  •  ${df.format(delivery.sentAt)} ${tf.format(delivery.sentAt)}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _statusLabel,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.message, required this.color});
  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: color.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(message,
                style: GoogleFonts.inter(
                    fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
}
