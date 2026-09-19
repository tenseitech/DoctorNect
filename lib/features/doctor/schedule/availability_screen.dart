import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/firebase/models/doctor_availability.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import '../../../core/theme/app_typography.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _slotDurations = [10, 15, 20, 30];
  static const _times = [
    '06:00 AM', '06:30 AM', '07:00 AM', '07:30 AM', '08:00 AM', '08:30 AM',
    '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
    '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM', '02:00 PM', '02:30 PM',
    '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM',
    '06:00 PM', '06:30 PM', '07:00 PM', '07:30 PM', '08:00 PM', '08:30 PM',
    '09:00 PM', '09:30 PM', '10:00 PM', '10:30 PM', '11:00 PM',
  ];

  final _formKey = GlobalKey<FormState>();
  final _maxPatientsController = TextEditingController(text: '20');
  final Set<String> _workingDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};
  String _morningStart = '09:00 AM';
  String _morningEnd = '01:00 PM';
  String _eveningStart = '04:00 PM';
  String _eveningEnd = '08:00 PM';
  int _slotDuration = 15;
  bool _breakEnabled = false;
  bool _eveningEnabled = false;
  String _breakStart = '01:00 PM';
  String _breakEnd = '02:00 PM';
  final Set<DateTime> _blockedDates = {};
  DateTime? _leaveStart;
  DateTime? _leaveEnd;
  bool _loading = true;
  bool _saving = false;

  static final _timeFormat = DateFormat('hh:mm a');

  int _timeSortKey(String time) {
    try {
      final parsed = _timeFormat.parse(time.trim());
      return parsed.hour * 60 + parsed.minute;
    } catch (_) {
      return -1;
    }
  }

  List<String> _timesAfter(String start, {bool strict = true}) {
    final startKey = _timeSortKey(start);
    return _times.where((t) {
      final key = _timeSortKey(t);
      return strict ? key > startKey : key >= startKey;
    }).toList();
  }

  List<String> _timesBefore(String end) {
    final endKey = _timeSortKey(end);
    return _times.where((t) => _timeSortKey(t) < endKey).toList();
  }

  void _normalizeBreakTimes() {
    if (!_breakEnabled) return;
    final endOptions = _timesAfter(_breakStart);
    if (endOptions.isEmpty) {
      _breakEnd = _breakStart;
      return;
    }
    if (_timeSortKey(_breakEnd) <= _timeSortKey(_breakStart) || !endOptions.contains(_breakEnd)) {
      _breakEnd = endOptions.first;
    }
  }

  String? get _breakTimeError {
    if (!_breakEnabled) return null;
    if (_timeSortKey(_breakEnd) <= _timeSortKey(_breakStart)) {
      return 'Break end must be after start time';
    }
    final clinicStartKey = _timeSortKey(_morningStart);
    final clinicEndKey = _timeSortKey(_morningEnd);
    if (_timeSortKey(_breakStart) < clinicStartKey) {
      return 'Break must start after Opens At';
    }
    if (_timeSortKey(_breakEnd) > clinicEndKey) {
      return 'Break must end before Closes At';
    }
    return null;
  }

  String? get _clinicTimeError {
    if (_timeSortKey(_morningEnd) <= _timeSortKey(_morningStart)) {
      return 'Closes At must be after Opens At';
    }
    return null;
  }

  void _onBreakStartChanged(String? value) {
    if (value == null) return;
    setState(() {
      _breakStart = value;
      _normalizeBreakTimes();
    });
  }

  void _onBreakEndChanged(String? value) {
    if (value == null) return;
    setState(() => _breakEnd = value);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSchedule());
  }

  Future<void> _loadSchedule() async {
    final saved = await FirestoreService.instance.doctorAvailability.fetch(
      DoctorSession.loggedInDoctorId,
      preferCache: false,
    );
    if (!mounted) return;

    if (saved != null) {
      setState(() {
        _workingDays
          ..clear()
          ..addAll(saved.workingDays);
        _morningStart = saved.morningStart;
        _eveningEnabled = saved.eveningEnabled;
        if (saved.eveningEnabled) {
          _morningEnd = saved.eveningEnd;
          _breakEnabled = true;
          _breakStart = saved.morningEnd;
          _breakEnd = saved.eveningStart;
        } else {
          _morningEnd = saved.morningEnd;
          _breakEnabled = saved.breakEnabled;
          _breakStart = saved.breakStart;
          _breakEnd = saved.breakEnd;
        }
        _eveningStart = saved.eveningStart;
        _eveningEnd = saved.eveningEnd;
        _slotDuration = saved.slotDurationMins;
        _maxPatientsController.text = '${saved.maxPatientsPerDay}';
        _blockedDates
          ..clear()
          ..addAll(saved.blockedDates);
        _leaveStart = saved.leaveStart;
        _leaveEnd = saved.leaveEnd;
        _normalizeBreakTimes();
        _loading = false;
      });
      return;
    }

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _maxPatientsController.dispose();
    super.dispose();
  }

  Future<void> _pickDates({required bool range}) async {
    if (range) {
      final start = await showDatePicker(
        context: context,
        initialDate: _leaveStart ?? DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: _datePickerTheme,
      );
      if (start == null || !mounted) return;

      final end = await showDatePicker(
        context: context,
        initialDate: _leaveEnd ?? start,
        firstDate: start,
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: _datePickerTheme,
      );
      if (end != null) {
        setState(() {
          _leaveStart = start;
          _leaveEnd = end;
        });
      }
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _datePickerTheme,
    );
    if (picked != null) {
      setState(() => _blockedDates.add(DateTime(picked.year, picked.month, picked.day)));
    }
  }

  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
      ),
      child: child!,
    );
  }

  DoctorScheduleAvailability _buildSchedule() {
    if (_eveningEnabled && _breakEnabled) {
      return DoctorScheduleAvailability(
        workingDays: _workingDays.toList(),
        morningStart: _morningStart,
        morningEnd: _breakStart,
        eveningEnabled: true,
        eveningStart: _breakEnd,
        eveningEnd: _morningEnd,
        slotDurationMins: _slotDuration,
        maxPatientsPerDay: int.parse(_maxPatientsController.text.trim()),
        breakEnabled: true,
        breakStart: _breakStart,
        breakEnd: _breakEnd,
        blockedDates: Set.from(_blockedDates),
        leaveStart: _leaveStart,
        leaveEnd: _leaveEnd,
      );
    }

    return DoctorScheduleAvailability(
      workingDays: _workingDays.toList(),
      morningStart: _morningStart,
      morningEnd: _morningEnd,
      eveningEnabled: false,
      eveningStart: _eveningStart,
      eveningEnd: _eveningEnd,
      slotDurationMins: _slotDuration,
      maxPatientsPerDay: int.parse(_maxPatientsController.text.trim()),
      breakEnabled: _breakEnabled,
      breakStart: _breakStart,
      breakEnd: _breakEnd,
      blockedDates: Set.from(_blockedDates),
      leaveStart: _leaveStart,
      leaveEnd: _leaveEnd,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_workingDays.isEmpty) {
      AppToast.info(context, 'Select at least one working day');
      return;
    }
    if (_clinicTimeError != null) {
      AppToast.info(context, _clinicTimeError!);
      return;
    }
    if (_breakTimeError != null) {
      AppToast.info(context, _breakTimeError!);
      return;
    }

    setState(() => _saving = true);
    try {
      await FirestoreService.instance.doctorAvailability.save(
        DoctorSession.loggedInDoctorId,
        _buildSchedule(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not save schedule. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        title: const Text('Availability & Schedule'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.doctorBlue))
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: ResponsiveLayout.contentMaxWidth(context)),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _card(
                        title: 'Working Days',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _days.map((day) {
                            final active = _workingDays.contains(day);
                            return FilterChip(
                              label: Text(day),
                              selected: active,
                              onSelected: (v) => setState(() {
                                if (v) {
                                  _workingDays.add(day);
                                } else {
                                  _workingDays.remove(day);
                                }
                              }),
                              selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
                              checkmarkColor: AppColors.doctorBlue,
                              labelStyle: GoogleFonts.inter(
                                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                color: active ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
                              ),
                              side: BorderSide(
                                color: active ? AppColors.doctorBlue : AppColors.borderOf(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Clinic Timings',
                        child: Row(
                          children: [
                            Expanded(
                              child: _TimeDropdown(
                                label: 'Opens At',
                                value: _morningStart,
                                times: _times,
                                onChanged: (v) => setState(() => _morningStart = v!),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.arrow_forward, size: 18, color: AppColors.textSecondaryOf(context)),
                            ),
                            Expanded(
                              child: _TimeDropdown(
                                label: 'Closes At',
                                value: _morningEnd,
                                times: _times,
                                onChanged: (v) => setState(() => _morningEnd = v!),
                                errorText: _clinicTimeError,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Break Time',
                        trailing: Switch(
                          value: _breakEnabled,
                          activeTrackColor: AppColors.doctorBlue.withValues(alpha: 0.5),
                          activeThumbColor: AppColors.doctorBlue,
                          onChanged: (v) => setState(() {
                            _breakEnabled = v;
                            if (!v) _eveningEnabled = false;
                            if (v) _normalizeBreakTimes();
                          }),
                        ),
                        child: _breakEnabled
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TimeDropdown(
                                          label: 'Start',
                                          value: _breakStart,
                                          times: _timesBefore(_breakEnd).isEmpty
                                              ? _times.sublist(0, _times.length - 1)
                                              : _timesBefore(_breakEnd),
                                          onChanged: _onBreakStartChanged,
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Icon(Icons.arrow_forward, size: 18, color: AppColors.textSecondaryOf(context)),
                                      ),
                                      Expanded(
                                        child: _TimeDropdown(
                                          label: 'End',
                                          value: _breakEnd,
                                          times: _timesAfter(_breakStart).isEmpty
                                              ? [_breakEnd]
                                              : _timesAfter(_breakStart),
                                          onChanged: _onBreakEndChanged,
                                          errorText: _breakTimeError,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Text(
                                'No break scheduled',
                                style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context), fontSize: AppTypography.bodyMedium),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Slot Duration',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _slotDurations.map((mins) {
                            final selected = _slotDuration == mins;
                            return ChoiceChip(
                              label: Text('$mins mins'),
                              selected: selected,
                              onSelected: (_) => setState(() => _slotDuration = mins),
                              selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
                              labelStyle: GoogleFonts.inter(
                                color: selected ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              ),
                              side: BorderSide(
                                color: selected ? AppColors.doctorBlue : AppColors.borderOf(context),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Max Patients Per Day',
                        child: TextFormField(
                          controller: _maxPatientsController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          validator: FormValidators.maxAppointments,
                          decoration: const InputDecoration(hintText: 'e.g. 20'),
                        ),
                      ),

                      const SizedBox(height: 16),
                      _card(
                        title: 'Block Specific Dates',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _pickDates(range: false),
                              icon: const Icon(Icons.event_busy_outlined, size: 18),
                              label: const Text('Add Blocked Date'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.doctorBlue,
                                foregroundColor: AppColors.white,
                              ),
                            ),
                            if (_blockedDates.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _blockedDates.map((d) {
                                  final label = DateFormat('dd MMM yyyy').format(d);
                                  return InputChip(
                                    label: Text(label, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
                                    onDeleted: () => setState(() => _blockedDates.remove(d)),
                                    deleteIconColor: AppColors.textSecondaryOf(context),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Leave Dates',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pickDates(range: true),
                              icon: const Icon(Icons.date_range_outlined, size: 18),
                              label: Text(
                                _leaveStart == null
                                    ? 'Select Leave Range'
                                    : '${DateFormat('dd MMM').format(_leaveStart!)} – ${DateFormat('dd MMM yyyy').format(_leaveEnd!)}',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.doctorBlue,
                                side: const BorderSide(color: AppColors.doctorBlue),
                              ),
                            ),
                            if (_leaveStart != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _leaveStart = null;
                                  _leaveEnd = null;
                                }),
                                child: const Text('Clear leave dates'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                              )
                            : const Text('Save Schedule'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({
    required this.label,
    required this.value,
    required this.times,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final String value;
  final List<String> times;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final items = times.contains(value) ? times : [value, ...times];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppColors.surfaceOf(context),
            errorText: errorText,
          ),
          items: items
              .map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.inter(fontSize: AppTypography.bodySmall))))
              .toList(),
          onChanged: onChanged,
          validator: errorText != null ? (_) => errorText : null,
        ),
      ],
    );
  }
}
