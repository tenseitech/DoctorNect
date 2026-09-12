import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../profile/widgets/patient_profile_form_styles.dart';
import 'data/health_records_mock.dart';
import 'models/health_record_models.dart';

class VitalsTrackerScreen extends StatefulWidget {
  const VitalsTrackerScreen({super.key});

  @override
  State<VitalsTrackerScreen> createState() => _VitalsTrackerScreenState();
}

class _VitalsTrackerScreenState extends State<VitalsTrackerScreen> {
  final List<VitalsLog> _logs = [];
  bool _loading = true;
  bool _showForm = false;
  VitalsTrend _trend = VitalsTrend.bp;

  final _notesController = TextEditingController();
  final _sysController = TextEditingController();
  final _diaController = TextEditingController();
  final _pulseController = TextEditingController();
  final _glucoseController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController(text: '165');
  final _tempController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _stepsController = TextEditingController();
  final _sleepController = TextEditingController();
  DateTime _logTime = DateTime.now();
  GlucoseReadingType _glucoseType = GlucoseReadingType.fasting;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVitals());
  }

  Future<void> _loadVitals() async {
    final patientId = PatientSession.loggedInPatientId;
    var logs = HealthRecordsMock.vitalsHistory();

    if (patientId.isNotEmpty) {
      try {
        if (logs.isEmpty) {
          final records = await FirestoreService.instance.patientProfile.fetchHealthRecords(patientId);
          HealthRecordsMock.applyFromFirestore(records);
          logs = HealthRecordsMock.vitalsHistory();
        }
      } catch (_) {
        if (mounted) {
          AppToast.info(context, 'Could not load vitals history');
        }
      }
    }

    final height = HealthRecordsMock.patientHeightCm();
    if (!mounted) return;
    setState(() {
      _logs
        ..clear()
        ..addAll(logs);
      if (height != null) {
        _heightController.text = height.toStringAsFixed(0);
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _sysController.dispose();
    _diaController.dispose();
    _pulseController.dispose();
    _glucoseController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _tempController.dispose();
    _spo2Controller.dispose();
    _stepsController.dispose();
    _sleepController.dispose();
    super.dispose();
  }

  double? get _bmi {
    final w = double.tryParse(_weightController.text);
    final h = double.tryParse(_heightController.text);
    if (w == null || h == null || h <= 0) return null;
    return w / ((h / 100) * (h / 100));
  }

  HealthRecord _healthRecordFromLog(VitalsLog log) {
    final payload = <String, dynamic>{
      'kind': 'vitalsLog',
      'dateTime': log.dateTime.toIso8601String(),
      if (log.systolic != null) 'systolic': log.systolic,
      if (log.diastolic != null) 'diastolic': log.diastolic,
      if (log.pulse != null) 'pulse': log.pulse,
      if (log.glucose != null) 'glucose': log.glucose,
      if (log.glucoseType != null) 'glucoseType': log.glucoseType!.name,
      if (log.weightKg != null) 'weightKg': log.weightKg,
      if (log.heightCm != null) 'heightCm': log.heightCm,
      if (log.temperatureF != null) 'temperatureF': log.temperatureF,
      if (log.spo2 != null) 'spo2': log.spo2,
      if (log.steps != null) 'steps': log.steps,
      if (log.sleepHours != null) 'sleepHours': log.sleepHours,
      if (log.notes != null) 'userNotes': log.notes,
    };

    return HealthRecord(
      id: log.id,
      title: 'Vitals log — ${DateFormat('dd MMM yyyy, hh:mm a').format(log.dateTime)}',
      type: HealthRecordType.other,
      date: log.dateTime,
      source: RecordSource.selfUploaded,
      fileName: 'vitals',
      notes: jsonEncode(payload),
    );
  }

  Future<void> _saveLog() async {
    final log = VitalsLog(
      id: 'v${DateTime.now().millisecondsSinceEpoch}',
      dateTime: _logTime,
      systolic: int.tryParse(_sysController.text),
      diastolic: int.tryParse(_diaController.text),
      pulse: int.tryParse(_pulseController.text),
      glucose: double.tryParse(_glucoseController.text),
      glucoseType: _glucoseType,
      weightKg: double.tryParse(_weightController.text),
      heightCm: double.tryParse(_heightController.text),
      temperatureF: double.tryParse(_tempController.text),
      spo2: int.tryParse(_spo2Controller.text),
      steps: int.tryParse(_stepsController.text),
      sleepHours: double.tryParse(_sleepController.text),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isNotEmpty) {
      try {
        await FirestoreService.instance.patientProfile.saveHealthRecord(
          patientId,
          _healthRecordFromLog(log),
        );
      } catch (_) {
        if (!mounted) return;
        AppToast.info(context, 'Failed to save vitals. Please try again.');
        return;
      }
    }

    HealthRecordsMock.addVitalsLog(log);
    if (!mounted) return;
    setState(() {
      _logs.insert(0, log);
      _showForm = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vitals log saved'), backgroundColor: Color(0xFF16A34A)),
    );
  }

  List<FlSpot> _spotsForTrend() {
    final reversed = _logs.reversed.take(15).toList();
    return reversed.asMap().entries.map((e) {
      final log = e.value;
      final y = switch (_trend) {
        VitalsTrend.bp => (log.systolic ?? 0).toDouble(),
        VitalsTrend.glucose => log.glucose ?? 0,
        VitalsTrend.weight => log.weightKg ?? 0,
      };
      return FlSpot(e.key.toDouble(), y);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        appBar: PatientProfileFormStyles.profileAppBar('Vitals Tracker', context: context),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.patientTeal),
        ),
      );
    }

    final spots = _spotsForTrend();
    final maxY = spots.isEmpty ? 100.0 : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.15;

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Vitals Tracker', context: context),
      body: PatientProfileFormStyles.constrainedScrollBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // UI FIX: constrained layout
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Track your health metrics',
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _showForm
                        ? OutlinedButton.icon(
                            onPressed: () => setState(() => _showForm = !_showForm),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Close'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.patientTeal),
                          )
                        : FilledButton.icon(
                            onPressed: () => setState(() => _showForm = true),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add vitals'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.patientTeal,
                              foregroundColor: AppColors.white,
                            ),
                          ),
                  ),
                  if (_showForm) ...[
                    const SizedBox(height: 16),
                    _buildForm(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // UI FIX: constrained layout
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PatientProfileFormStyles.sectionHeader('Trends (last 30 days)'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: VitalsTrend.values.map((trend) {
                      final selected = _trend == trend;
                      final label = switch (trend) {
                        VitalsTrend.bp => 'BP',
                        VitalsTrend.glucose => 'Glucose',
                        VitalsTrend.weight => 'Weight',
                      };
                      return FilterChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (_) => setState(() => _trend = trend),
                        selectedColor: AppColors.patientTeal.withValues(alpha: 0.15),
                        checkmarkColor: AppColors.patientTeal,
                        labelStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: selected ? AppColors.patientTeal : AppColors.textSecondaryOf(context),
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                        side: BorderSide(color: selected ? AppColors.patientTeal : AppColors.borderOf(context)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBgOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderOf(context), width: 0.5),
                    ),
                    child: spots.isEmpty
                        ? Center(child: Text('No data yet', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context))))
                        : LineChart(
                            LineChartData(
                              minY: _trend == VitalsTrend.glucose ? 70 : 0,
                              maxY: maxY,
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (_) => FlLine(color: AppColors.borderOf(context), strokeWidth: 1),
                              ),
                              titlesData: const FlTitlesData(
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: AppColors.patientTeal,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: AppColors.patientTeal.withValues(alpha: 0.08),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // UI FIX: constrained layout
            PatientProfileFormStyles.contentSurface(context: context, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PatientProfileFormStyles.sectionHeader('History'),
                  const SizedBox(height: 16),
                  if (_logs.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(Icons.monitor_heart_outlined, size: 48, color: AppColors.patientTeal.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('No vitals logged yet', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context))),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._logs.map(_historyTile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientProfileFormStyles.dobPickerRow(
          context: context,
          label: 'Date & time',
          valueText: DateFormat('dd MMM yyyy, hh:mm a').format(_logTime),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _logTime,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now(),
            );
            if (d == null || !mounted) return;
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_logTime),
              initialEntryMode: TimePickerEntryMode.dialOnly,
            );
            if (t != null) {
              setState(() {
                _logTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
              });
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sysController,
                keyboardType: TextInputType.number,
                decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'BP Sys'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _diaController,
                keyboardType: TextInputType.number,
                decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'BP Dia'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pulseController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Pulse (bpm)'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _glucoseController,
                keyboardType: TextInputType.number,
                decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Blood glucose'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<GlucoseReadingType>(
                initialValue: _glucoseType,
                isExpanded: true,
                decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: GlucoseReadingType.fasting, child: Text('Fasting')),
                  DropdownMenuItem(value: GlucoseReadingType.postPrandial, child: Text('PP')),
                  DropdownMenuItem(value: GlucoseReadingType.random, child: Text('Random')),
                ],
                onChanged: (v) => setState(() => _glucoseType = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weightController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Weight (kg)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _heightController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, 
            labelText: 'Height (cm)',
            hintText: HealthRecordsMock.patientHeightCm() != null ? 'Saved from profile' : null,
          ),
        ),
        if (_bmi != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('BMI: ${_bmi!.toStringAsFixed(1)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.patientTeal)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _tempController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Temperature (°F)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _spo2Controller,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'SpO2 (%)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _stepsController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Steps today'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sleepController,
          keyboardType: TextInputType.number,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Sleep (hours)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Notes', alignLabelWithHint: true),
        ),
        const SizedBox(height: 16),
        PatientProfileFormStyles.cardActionButton(onPressed: _saveLog, label: 'Save log'),
      ],
    );
  }

  Widget _historyTile(VitalsLog log) {
    return PatientProfileFormStyles.recordItemCard(
        context: context,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite_outline, color: AppColors.patientTeal, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(log.dateTime),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (log.systolic != null) 'BP ${log.systolic}/${log.diastolic}',
                    if (log.glucose != null) 'Glucose ${log.glucose} mg/dL',
                    if (log.weightKg != null) 'Weight ${log.weightKg} kg',
                    if (log.pulse != null) 'Pulse ${log.pulse}',
                  ].join(' · '),
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum VitalsTrend { bp, glucose, weight }
