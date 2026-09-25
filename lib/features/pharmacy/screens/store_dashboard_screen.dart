import '../../../core/firebase/firestore_service.dart';
import 'dart:async'; // FIXED: for the realtime delivery subscription

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_icons.dart';
// FIXED: realtime delivery stream
import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/theme_toggle_button.dart';
import '../../../widgets/verification_status_banner.dart';
import '../data/pharmacy_connection_store.dart';
import '../data/pharmacy_prescription_store.dart';
import '../models/pharmacy_models.dart';
import 'store_prescription_detail_screen.dart';
import '../../../core/theme/app_typography.dart';

String pharmacyDeliveryStatusLabel(PharmacyDeliveryStatus s) => switch (s) {
      PharmacyDeliveryStatus.sent => 'New',
      PharmacyDeliveryStatus.viewed => 'Viewed',
      PharmacyDeliveryStatus.partiallyDispensed => 'Partial',
      PharmacyDeliveryStatus.dispensed => 'Dispensed',
    };

/// One entry per doctor — duplicate active connections must not break dropdowns.
List<PharmacyConnection> uniquePharmacyDoctors(
    List<PharmacyConnection> doctors) {
  final seen = <String>{};
  final unique = <PharmacyConnection>[];
  for (final doctor in doctors) {
    if (seen.add(doctor.doctorId)) unique.add(doctor);
  }
  return unique;
}

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key});

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedDoctorId;
  late final TabController _orderTabController;
  final _patientSearchController = TextEditingController();
  StreamSubscription<List<PharmacyPrescriptionDelivery>>?
      _deliverySub; // FIXED: realtime delivery sync

  @override
  void initState() {
    super.initState();
    _orderTabController = TabController(length: 2, vsync: this);
    _orderTabController.addListener(() {
      if (!_orderTabController.indexIsChanging) setState(() {});
    });
    // FIXED: live-sync incoming deliveries so prescriptions appear without an app restart
    final storeId = MedicalStoreSession.loggedInStoreId;
    _deliverySub = FirestoreService.instance.pharmacyFirestore
        .watchDeliveriesForStore(storeId)
        .listen((deliveries) {
      PharmacyPrescriptionStore.instance.mergeFromFirestore(deliveries);
    });
  }

  // FIXED: pull-to-refresh fallback when realtime sync is unavailable
  Future<void> _refreshDeliveries() async {
    final storeId = MedicalStoreSession.loggedInStoreId;
    final deliveries = await FirestoreService.instance.pharmacyFirestore
        .fetchDeliveriesForStore(storeId);
    PharmacyPrescriptionStore.instance.mergeFromFirestore(deliveries);
  }

  @override
  void dispose() {
    _orderTabController.dispose();
    _deliverySub?.cancel(); // FIXED: tear down realtime listener
    _patientSearchController.dispose();
    super.dispose();
  }

  bool _isDispensedOrder(PharmacyPrescriptionDelivery delivery) =>
      delivery.status == PharmacyDeliveryStatus.dispensed ||
      delivery.status == PharmacyDeliveryStatus.partiallyDispensed;

  List<PharmacyPrescriptionDelivery> _filterPrescriptions(
    List<PharmacyPrescriptionDelivery> prescriptions,
  ) {
    final search = _patientSearchController.text.trim().toLowerCase();
    if (search.isEmpty) return prescriptions;
    return prescriptions
        .where(
            (p) => p.draft.patient.patientName.toLowerCase().contains(search))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PharmacyPrescriptionStore.instance,
        PharmacyConnectionStore.instance,
      ]),
      builder: (context, _) {
        final storeId = MedicalStoreSession.loggedInStoreId;
        final doctors = uniquePharmacyDoctors(
          PharmacyConnectionStore.instance.activeForStore(storeId),
        );
        final grouped =
            PharmacyPrescriptionStore.instance.groupedByDoctorForStore(storeId);

        if (doctors.isEmpty) {
          return Column(
            children: [
              const VerificationStatusBanner(role: UserType.medicalStore),
              Expanded(
                child: _emptyState(
                  'No connected doctors',
                  'Go to Connect Doctors to send connection requests to registered doctors.',
                ),
              ),
            ],
          );
        }

        // FIXED: do not mutate state during build — compute the effective selection locally
        final doctorId = (_selectedDoctorId != null &&
                doctors.any((d) => d.doctorId == _selectedDoctorId))
            ? _selectedDoctorId!
            : doctors.first.doctorId;
        var prescriptions = PharmacyPrescriptionStore.instance
            .forStoreAndDoctor(storeId, doctorId);
        prescriptions = _filterPrescriptions(prescriptions);
        final newOrders =
            prescriptions.where((p) => !_isDispensedOrder(p)).toList();
        final dispensedOrders = prescriptions.where(_isDispensedOrder).toList();
        final allStorePrescriptions =
            PharmacyPrescriptionStore.instance.forStore(storeId);

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final statsHeader =
                _buildStatsHeader(allStorePrescriptions, doctors.length, wide);

            if (wide) {
              return Column(
                children: [
                  const VerificationStatusBanner(role: UserType.medicalStore),
                  statsHeader,
                  Expanded(
                    child: _prescriptionPanel(
                      doctors,
                      newOrders: newOrders,
                      dispensedOrders: dispensedOrders,
                      doctorId: doctorId,
                      showTitleBlock: true,
                      isWide: wide,
                      grouped: grouped,
                      storeId: storeId,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                const VerificationStatusBanner(role: UserType.medicalStore),
                Expanded(
                  child: _prescriptionPanel(
                    doctors,
                    newOrders: newOrders,
                    dispensedOrders: dispensedOrders,
                    doctorId: doctorId,
                    showTitleBlock: false,
                    isWide: wide,
                    grouped: grouped,
                    storeId: storeId,
                    statsHeader: statsHeader,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_pharmacy_outlined,
                size: 48,
                color:
                    AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsHeader(List<PharmacyPrescriptionDelivery> allPrescriptions,
      int doctorCount, bool isWide) {
    final today = DateTime.now();
    final pendingCount =
        allPrescriptions.where((p) => !_isDispensedOrder(p)).length;
    final dispensedCount = allPrescriptions.where(_isDispensedOrder).length;
    final badges = [
      _buildStatBadge(AppIcons.prescription, '$pendingCount New'),
      _buildStatBadge(Icons.check_circle_outline, '$dispensedCount Done'),
      _buildStatBadge(Icons.people_outline, '$doctorCount Dr.'),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.pharmacyGreen, const Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: isWide
          ? Row(
              children: [
                Text('Dashboard',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(width: 20),
                ...badges
                    .expand((badge) => [badge, const SizedBox(width: 8)])
                    .toList()
                  ..removeLast(),
                const Spacer(),
                const ThemeToggleButton(highlighted: true),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEE, dd MMM').format(today),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const ThemeToggleButton(highlighted: true),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: badges,
                ),
              ],
            ),
    );
  }

  Widget _buildStatBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _prescriptionPanel(
    List<PharmacyConnection> doctors, {
    required List<PharmacyPrescriptionDelivery> newOrders,
    required List<PharmacyPrescriptionDelivery> dispensedOrders,
    required String doctorId,
    required bool showTitleBlock,
    required bool isWide,
    required Map<String, List<PharmacyPrescriptionDelivery>> grouped,
    required String storeId,
    Widget? statsHeader,
  }) {
    final doctor = doctors.firstWhere((d) => d.doctorId == doctorId);

    final controlBar = Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: isWide
          ? Row(
              children: [
                SizedBox(
                  width: 200,
                  child: _doctorDropdown(doctors, grouped, storeId, doctorId,
                      compact: true),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: _OrderTabSwitcher(
                    controller: _orderTabController,
                    newCount: newOrders.length,
                    dispensedCount: dispensedOrders.length,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PharmacySearchField(
                    controller: _patientSearchController,
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _doctorDropdown(doctors, grouped, storeId, doctorId),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _OrderTabSwitcher(
                        controller: _orderTabController,
                        newCount: newOrders.length,
                        dispensedCount: dispensedOrders.length,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _PharmacySearchField(
                        controller: _patientSearchController,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );

    final tabViews = [
      _prescriptionList(
        newOrders,
        isNewTab: true,
        emptyMessage: 'No new prescriptions',
        emptySubtitle:
            'Incoming orders from ${_pharmacyDoctorLabel(doctor.doctorName)} will appear here.',
      ),
      _prescriptionList(
        dispensedOrders,
        isNewTab: false,
        emptyMessage: 'No dispensed prescriptions',
        emptySubtitle: 'Completed orders will be listed here for your records.',
      ),
    ];

    if (!isWide) {
      return RefreshIndicator(
        onRefresh: _refreshDeliveries,
        color: AppColors.pharmacyGreen,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            if (statsHeader != null) SliverToBoxAdapter(child: statsHeader),
            SliverToBoxAdapter(child: controlBar),
          ],
          body: TabBarView(
            controller: _orderTabController,
            children: tabViews,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controlBar,
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshDeliveries,
            color: AppColors.pharmacyGreen,
            child: TabBarView(
              controller: _orderTabController,
              children: tabViews,
            ),
          ),
        ),
      ],
    );
  }

  Widget _doctorDropdown(
    List<PharmacyConnection> doctors,
    Map<String, List<PharmacyPrescriptionDelivery>> grouped,
    String storeId,
    String selectedDoctorId, {
    bool compact = false,
  }) {
    final uniqueDoctors = uniquePharmacyDoctors(doctors);
    if (uniqueDoctors.isEmpty) return const SizedBox.shrink();

    final dropdownValue =
        uniqueDoctors.any((d) => d.doctorId == selectedDoctorId)
            ? selectedDoctorId
            : uniqueDoctors.first.doctorId;

    return Container(
      height: compact ? 36 : 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: dropdownValue,
          isExpanded: true,
          icon: Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondaryOf(context), size: 20),
          ),
          dropdownColor: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          items: uniqueDoctors.map((d) {
            final unread = PharmacyPrescriptionStore.instance
                .unreadCountForStoreDoctor(storeId, d.doctorId);
            return DropdownMenuItem<String>(
              value: d.doctorId,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pharmacyDoctorLabel(d.doctorName),
                        style: GoogleFonts.inter(
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.doctorBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unread',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surfaceOf(context)),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedDoctorId = val);
          },
        ),
      ),
    );
  }

  Widget _prescriptionList(
    List<PharmacyPrescriptionDelivery> prescriptions, {
    required bool isNewTab,
    required String emptyMessage,
    required String emptySubtitle,
  }) {
    if (prescriptions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 80),
          _EmptyPrescriptionsState(
            isNewTab: isNewTab,
            title: emptyMessage,
            subtitle: emptySubtitle,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: prescriptions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _PrescriptionCard(
        delivery: prescriptions[i],
        isNewTab: isNewTab,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StorePrescriptionDetailScreen(
                  deliveryId: prescriptions[i].id),
            ),
          );
          setState(() {});
        },
      ),
    );
  }
}

String _pharmacyDoctorLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Doctor';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({
    required this.delivery,
    required this.onTap,
    required this.isNewTab,
  });

  final PharmacyPrescriptionDelivery delivery;
  final VoidCallback onTap;
  final bool isNewTab;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: wide
                ? _WidePrescriptionTile(delivery: delivery, isNewTab: isNewTab)
                : _CompactPrescriptionTile(
                    delivery: delivery, isNewTab: isNewTab),
          ),
        );
      },
    );
  }
}

class _PrescriptionTileData {
  _PrescriptionTileData({required this.delivery, required this.isNewTab});

  final PharmacyPrescriptionDelivery delivery;
  final bool isNewTab;

  List<Color> get gradient => isNewTab
      ? const [Color(0xFF2563EB), Color(0xFF1D4ED8)]
      : const [Color(0xFF059669), Color(0xFF047857)];

  ({String label, Color color}) get status =>
      _prescriptionStatusStyle(delivery.status);

  String get day => DateFormat('dd').format(delivery.sentAt);

  String get month => DateFormat('MMM').format(delivery.sentAt).toUpperCase();

  String get time => DateFormat('hh:mm a').format(delivery.sentAt);
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.data});

  final _PrescriptionTileData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 18,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: data.gradient),
            ),
            alignment: Alignment.center,
            child: Text(
              data.month,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.surfaceOf(context),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                data.day,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineMedium,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineStrip extends StatelessWidget {
  const _MedicineStrip({required this.data});

  final _PrescriptionTileData data;

  @override
  Widget build(BuildContext context) {
    final medicines = data.delivery.draft.validMedicines;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(AppIcons.prescription,
              size: 16, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              medicines.map((m) => m.name).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: data.gradient.first.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${medicines.length}',
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w600,
                color: data.gradient.first,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidePrescriptionTile extends StatelessWidget {
  const _WidePrescriptionTile({required this.delivery, required this.isNewTab});

  final PharmacyPrescriptionDelivery delivery;
  final bool isNewTab;

  @override
  Widget build(BuildContext context) {
    final data = _PrescriptionTileData(delivery: delivery, isNewTab: isNewTab);
    final patient = delivery.draft.patient;
    final status = data.status;

    return Ink(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimaryOf(context).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            _DateBadge(data: data),
            const SizedBox(width: 14),
            SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${patient.age} yrs · ${patient.gender ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 13,
                          color: AppColors.textSecondaryOf(context)
                              .withValues(alpha: 0.9)),
                      const SizedBox(width: 4),
                      Text(
                        data.time,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: _MedicineStrip(data: data)),
            const SizedBox(width: 14),
            SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusChip(label: status.label, color: status.color),
                  const SizedBox(height: 8),
                  Text(
                    delivery.prescriptionId,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 22, color: data.gradient.first.withValues(alpha: 0.65)),
          ],
        ),
      ),
    );
  }
}

class _CompactPrescriptionTile extends StatelessWidget {
  const _CompactPrescriptionTile(
      {required this.delivery, required this.isNewTab});

  final PharmacyPrescriptionDelivery delivery;
  final bool isNewTab;

  @override
  Widget build(BuildContext context) {
    final data = _PrescriptionTileData(delivery: delivery, isNewTab: isNewTab);
    final patient = delivery.draft.patient;
    final status = data.status;

    return Ink(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimaryOf(context).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateBadge(data: data),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient.patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          _StatusChip(label: status.label, color: status.color),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${patient.age} yrs · ${patient.gender ?? '—'} · ${data.time}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        delivery.prescriptionId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MedicineStrip(data: data),
          ],
        ),
      ),
    );
  }
}

({String label, Color color}) _prescriptionStatusStyle(
    PharmacyDeliveryStatus status) {
  return switch (status) {
    PharmacyDeliveryStatus.sent => (label: 'New', color: AppColors.doctorBlue),
    PharmacyDeliveryStatus.viewed => (
        label: 'Viewed',
        color: const Color(0xFFD97706)
      ),
    PharmacyDeliveryStatus.partiallyDispensed => (
        label: 'Partial',
        color: const Color(0xFFEA580C)
      ),
    PharmacyDeliveryStatus.dispensed => (
        label: 'Dispensed',
        color: AppColors.pharmacyGreen
      ),
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _PharmacySearchField extends StatefulWidget {
  const _PharmacySearchField({
    required this.controller,
    required this.onChanged,
  }) : iconOnly = false;

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool iconOnly;

  @override
  State<_PharmacySearchField> createState() => _PharmacySearchFieldState();
}

class _PharmacySearchFieldState extends State<_PharmacySearchField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode
        .addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: _focused
                ? AppColors.surfaceOf(context)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? AppColors.pharmacyGreen.withValues(alpha: 0.5)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(Icons.search_rounded,
                    size: 20,
                    color: _focused
                        ? AppColors.pharmacyGreen
                        : AppColors.textSecondaryOf(context)),
              ),
              // Hidden text field to capture input
              SizedBox(
                width: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  onChanged: (_) => widget.onChanged(),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 44,
      decoration: BoxDecoration(
        color:
            _focused ? AppColors.surfaceOf(context) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focused
              ? AppColors.pharmacyGreen.withValues(alpha: 0.4)
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          if (_focused)
            BoxShadow(
              color: AppColors.pharmacyGreen.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
        decoration: InputDecoration(
          hintText: 'Search patient name',
          hintStyle: GoogleFonts.inter(
              color: AppColors.textSecondaryOf(context),
              fontSize: AppTypography.bodyMedium),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: _focused
                ? AppColors.pharmacyGreen
                : AppColors.textSecondaryOf(context),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
        onChanged: (_) => widget.onChanged(),
      ),
    );
  }
}

class _OrderTabSwitcher extends StatelessWidget {
  const _OrderTabSwitcher({
    required this.controller,
    required this.newCount,
    required this.dispensedCount,
  });

  final TabController controller;
  final int newCount;
  final int dispensedCount;

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
                child: _OrderTabPill(
                  label: 'New',
                  count: newCount,
                  selected: controller.index == 0,
                  accentColor: const Color(0xFF2563EB),
                  icon: Icons.inbox_rounded,
                  onTap: () => controller.animateTo(0),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _OrderTabPill(
                  label: 'Dispensed',
                  count: dispensedCount,
                  selected: controller.index == 1,
                  accentColor: AppColors.pharmacyGreen,
                  icon: Icons.check_circle_outline_rounded,
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

class _OrderTabPill extends StatelessWidget {
  const _OrderTabPill({
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
                  style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
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

class _EmptyPrescriptionsState extends StatelessWidget {
  const _EmptyPrescriptionsState({
    required this.isNewTab,
    required this.title,
    required this.subtitle,
  });

  final bool isNewTab;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final gradient = isNewTab
        ? const [Color(0xFF2563EB), Color(0xFF1D4ED8)]
        : const [Color(0xFF059669), Color(0xFF047857)];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimaryOf(context).withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  isNewTab ? Icons.inbox_outlined : Icons.verified_outlined,
                  size: 30,
                  color: AppColors.surfaceOf(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
