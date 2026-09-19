import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../doctor/clinical/data/clinical_prescription_store.dart';
import '../../doctor/clinical/data/lab_order_store.dart';
import '../../doctor/clinical/prescription/prescription_preview_modal.dart';
import 'data/medical_records_mapper.dart';
import 'data/patient_lab_booking_store.dart';
import 'models/health_record_models.dart';
import 'widgets/health_record_row.dart';
import 'widgets/patient_blood_test_sheet.dart';
import 'widgets/patient_lab_order_sheet.dart';
import 'widgets/records_tab_summary.dart';
import '../widgets/patient_shell_tab.dart';

class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    (MedicalRecordFilter.prescription, 'Prescription'),
    (MedicalRecordFilter.tests, 'Tests'),
  ];

  late TabController _tabController;
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    unawaited(_loadRecords());
  }

  void _onTabChanged() {
    if (_tabController.index != _tabIndex) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  List<HealthRecord> _recordsFor(MedicalRecordFilter filter) {
    final patientId = PatientSession.loggedInPatientId;
    final all = MedicalRecordsMapper.mergeForPatient(patientId);
    return MedicalRecordsMapper.filter(all, filter);
  }

  Future<void> _loadRecords() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      await Future.wait([
        ClinicalPrescriptionStore.instance
            .refreshForPatient(patientId, preferCache: false),
        LabOrderStore.instance.refreshForPatient(patientId, preferCache: false),
        PatientLabBookingStore.instance
            .refreshForPatient(patientId, preferCache: false),
      ]);
    } catch (_) {
      if (mounted) {
        AppToast.info(context, 'Could not load medical records');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _openRecord(HealthRecord record) {
    if (record.prescriptionId != null) {
      final draft =
          ClinicalPrescriptionStore.instance.findById(record.prescriptionId!);
      if (draft == null) {
        AppToast.info(
            context, 'Prescription not found. Pull to refresh and try again.');
        return;
      }
      PrescriptionPreviewModal.show(context, draft: draft);
      return;
    }

    if (record.labOrderId != null) {
      final order = LabOrderStore.instance.findById(record.labOrderId!);
      if (order == null) {
        AppToast.info(
            context, 'Lab test not found. Pull to refresh and try again.');
        return;
      }
      PatientLabOrderSheet.show(context, order);
      return;
    }

    if (record.labBookingId != null) {
      final booking =
          PatientLabBookingStore.instance.findById(record.labBookingId!);
      if (booking == null) {
        AppToast.info(
            context, 'Blood test not found. Pull to refresh and try again.');
        return;
      }
      PatientBloodTestSheet.show(context, booking);
      return;
    }
  }

  List<Widget> _buildGroupedRecordRows(
    List<HealthRecord> records,
    Color accentColor,
  ) {
    final groups = groupHealthRecordsByMonth(records);
    final widgets = <Widget>[];

    for (var g = 0; g < groups.length; g++) {
      final (monthLabel, monthRecords) = groups[g];
      widgets.add(HealthRecordMonthHeader(label: monthLabel));
      for (var i = 0; i < monthRecords.length; i++) {
        final isLastInMonth = i == monthRecords.length - 1;
        final isLastOverall = g == groups.length - 1 && isLastInMonth;
        widgets.add(
          HealthRecordRow(
            record: monthRecords[i],
            accentColor: accentColor,
            showDivider: !isLastOverall,
            onTap: () => _openRecord(monthRecords[i]),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildTabBody(MedicalRecordFilter filter, String label) {
    final records = _recordsFor(filter);
    final style = RecordsTabStyle.forLabel(label);

    if (_loading) {
      return ColoredBox(
        color: AppColors.surfaceOf(context),
        child: Center(
          child: CircularProgressIndicator(color: style.accentColor),
        ),
      );
    }

    if (records.isEmpty) {
      return PatientShellTabList(
        onRefresh: _loadRecords,
        empty: PatientTabEmptyState(
          icon: style.icon,
          title: style.emptyTitle,
          message: style.emptyMessage,
          accentColor: style.accentColor,
        ),
        children: const [],
      );
    }

    return PatientShellTabList(
      onRefresh: _loadRecords,
      children: [
        RecordsTabSummary(
          icon: style.icon,
          count: records.length,
          label: style.summaryLabel,
          hint: style.summaryHint,
          accentColor: style.accentColor,
        ),
        Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
        ..._buildGroupedRecordRows(records, style.accentColor),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ClinicalPrescriptionStore.instance,
        LabOrderStore.instance,
        PatientLabBookingStore.instance,
      ]),
      builder: (context, _) {
        final counts = _tabs.map((t) => _recordsFor(t.$1).length).toList();
        final activeStyle = RecordsTabStyle.forLabel(_tabs[_tabIndex].$2);

        return PatientShellTabPage(
          title: 'Medical Record',
          subtitle: 'Prescriptions, lab tests & blood reports',
          tabController: _tabController,
          accentColor: activeStyle.accentColor,
          tabLabels: [
            for (var i = 0; i < _tabs.length; i++)
              '${_tabs[i].$2} (${counts[i]})',
          ],
          tabBodies: [
            for (final tab in _tabs) _buildTabBody(tab.$1, tab.$2),
          ],
        );
      },
    );
  }
}
