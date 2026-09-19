import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/firebase/models/doctor_lab_order.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../clinical/data/lab_order_store.dart';
import '../../patients/data/doctor_patients_service.dart';
import '../../widgets/patient_sharing_blocked_notice.dart';
import '../../../../core/theme/app_typography.dart';

class LabDataSection extends StatefulWidget {
  const LabDataSection({super.key});

  @override
  State<LabDataSection> createState() => _LabDataSectionState();
}

class _LabDataSectionState extends State<LabDataSection> {
  String _search = '';
  List<DoctorLabOrder> _visibleOrders = const [];
  int _filterGeneration = 0;

  @override
  void initState() {
    super.initState();
    LabOrderStore.instance.addListener(_onOrdersChanged);
    unawaited(LabOrderStore.instance.refreshForDoctor(preferCache: true));
    unawaited(_recomputeVisibleOrders());
  }

  @override
  void dispose() {
    LabOrderStore.instance.removeListener(_onOrdersChanged);
    super.dispose();
  }

  void _onOrdersChanged() {
    unawaited(_recomputeVisibleOrders());
  }

  List<DoctorLabOrder> get _orders =>
      LabOrderStore.instance.forDoctor(DoctorSession.loggedInDoctorId);

  List<DoctorLabOrder> get _filteredBySearch {
    if (_search.trim().isEmpty) return _orders;
    final q = _search.trim().toLowerCase();
    return _orders
        .where((o) =>
            o.patientName.toLowerCase().contains(q) ||
            o.testNames.any((t) => t.toLowerCase().contains(q)) ||
            (o.labName ?? '').toLowerCase().contains(q) ||
            (o.indication ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _recomputeVisibleOrders() async {
    final generation = ++_filterGeneration;
    final candidates = _filteredBySearch;
    final visible = <DoctorLabOrder>[];

    for (final order in candidates) {
      if (await DoctorPatientsService.canViewClinicalHistoryForKey(
          order.patientId)) {
        visible.add(order);
      }
    }

    if (!mounted || generation != _filterGeneration) return;
    setState(() => _visibleOrders = visible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lab Data')),
      body: ListenableBuilder(
        listenable: LabOrderStore.instance,
        builder: (context, _) {
          final orders = _visibleOrders;
          final total = _orders.length;
          final totalTests =
              _orders.fold<int>(0, (sum, o) => sum + o.testNames.length);
          final hiddenCount = total - orders.length;

          return Column(
            children: [
              Container(
                color: AppColors.labPurple.withValues(alpha: 0.07),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.biotech_outlined,
                        color: AppColors.labPurple, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$total orders · $totalTests tests',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.labPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hiddenCount > 0) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: PatientSharingBlockedNotice(
                      compact: true, showSubtitle: false),
                ),
              ],
              Padding(
                padding:
                    EdgeInsets.fromLTRB(16, hiddenCount > 0 ? 8 : 12, 16, 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by patient, test, or lab',
                    hintStyle: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: Colors.grey[400]),
                    prefixIcon:
                        Icon(Icons.search, color: Colors.grey[400], size: 20),
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    setState(() => _search = v);
                    unawaited(_recomputeVisibleOrders());
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.biotech_outlined,
                                size: 52, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              _search.isEmpty
                                  ? (total == 0
                                      ? 'No lab orders yet'
                                      : 'No visible lab orders')
                                  : 'No results for "$_search"',
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
                                  color: Colors.grey[500]),
                            ),
                            if (_search.isEmpty &&
                                total > 0 &&
                                hiddenCount > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Some orders are hidden because those patients turned off sharing.',
                                style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelMedium,
                                    color: Colors.grey[400]),
                                textAlign: TextAlign.center,
                              ),
                            ] else if (_search.isEmpty && total == 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Orders from prescriptions or connected labs appear here',
                                style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelMedium,
                                    color: Colors.grey[400]),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      )
                    : Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: orders.length +
                                (LabOrderStore.instance.hasMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              if (i == orders.length) {
                                return TextButton(
                                  onPressed: () => LabOrderStore.instance
                                      .loadMoreForDoctor(preferCache: false),
                                  child: const Text('Load more'),
                                );
                              }
                              return _LabOrderRow(order: orders[i], index: i);
                            },
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LabOrderRow extends StatelessWidget {
  const _LabOrderRow({required this.order, required this.index});

  final DoctorLabOrder order;
  final int index;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('hh:mm a');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}.',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium, color: Colors.grey[400]),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.labPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.science_outlined,
                color: AppColors.labPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.patientName,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  '${order.patientAge} yrs · ${order.testNames.length} test(s)',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 10, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '${df.format(order.createdAt)}  ${tf.format(order.createdAt)}',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: Colors.grey[500]),
                    ),
                  ],
                ),
                if (order.labName != null && order.labName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.local_hospital_outlined,
                          size: 10, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        order.labName!,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
                if (order.indication != null &&
                    order.indication!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    order.indication!,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        color: Colors.grey[500]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: order.testNames
                      .map(
                        (name) => Chip(
                          label: Text(name,
                              style: GoogleFonts.inter(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              AppColors.labPurple.withValues(alpha: 0.08),
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.labPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.status,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.labPurple,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                order.urgency,
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
