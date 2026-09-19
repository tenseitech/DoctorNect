import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../patient/booking/models/booking_models.dart';
import '../../models/doctor_models.dart';
import '../../../../core/theme/app_typography.dart';

class RescheduleModal extends StatefulWidget {
  const RescheduleModal({
    super.key,
    required this.appointment,
    required this.onConfirm,
    this.showDragHandle = false,
  });

  final Appointment appointment;
  final void Function(DateTime date, String slot, String reason, bool notify)
      onConfirm;
  final bool showDragHandle;

  static const rescheduleReasons = [
    'Doctor unavailable',
    'Emergency',
    'Patient request',
    'Clinic schedule change',
    'Other',
  ];

  static Future<void> show(
    BuildContext context, {
    required Appointment appointment,
    required void Function(
            DateTime date, String slot, String reason, bool notify)
        onConfirm,
  }) {
    final compact = ResponsiveLayout.isCompact(context);

    if (compact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: RescheduleModal(
                  appointment: appointment,
                  onConfirm: onConfirm,
                  showDragHandle: true,
                ),
              ),
            ),
          );
        },
      );
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceOf(context),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: RescheduleModal(
              appointment: appointment,
              onConfirm: onConfirm,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<RescheduleModal> createState() => _RescheduleModalState();
}

class _RescheduleModalState extends State<RescheduleModal> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedSlot;
  String? _reason;
  bool _notifyPatient = true;
  List<String> _availableSlots = [];
  bool _loadingSlots = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSlots());
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    final slots =
        await FirestoreService.instance.doctorAvailability.slotsForDate(
      doctorId: DoctorSession.loggedInDoctorId,
      date: _selectedDate,
    );
    if (!mounted) return;
    setState(() {
      _availableSlots = slots
          .where((s) => s.status == SlotStatus.available)
          .map((s) => s.label)
          .toList();
      _selectedSlot =
          _availableSlots.contains(_selectedSlot) ? _selectedSlot : null;
      _loadingSlots = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.doctorBlue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadSlots();
    }
  }

  void _confirm() {
    if (_selectedSlot == null || _reason == null) {
      AppToast.info(context, 'Select a time slot and reason');
      return;
    }
    widget.onConfirm(_selectedDate, _selectedSlot!, _reason!, _notifyPatient);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointment;
    final currentLabel =
        '${DateFormat('dd MMM yyyy').format(appt.appointmentDate)} · ${appt.timeSlot}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showDragHandle)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
            children: [
              const Icon(AppIcons.reschedule,
                  size: 22, color: AppColors.doctorBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reschedule Appointment',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              if (!widget.showDragHandle)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondaryOf(context),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _PatientSummaryCard(
            patientName: appt.patientName,
            currentLabel: currentLabel,
          ),
          const SizedBox(height: 16),
          _SectionLabel('New date'),
          const SizedBox(height: 8),
          _DatePickerTile(
            label: DateFormat('EEE, dd MMM yyyy').format(_selectedDate),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          _SectionLabel('Available time'),
          const SizedBox(height: 8),
          if (_loadingSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.doctorBlue,
                  ),
                ),
              ),
            )
          else if (_availableSlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Text(
                'No slots available on this date. Update your availability schedule first.',
                style: GoogleFonts.inter(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: AppTypography.bodySmall),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableSlots.map((slot) {
                final selected = _selectedSlot == slot;
                return _SlotChip(
                  label: slot,
                  selected: selected,
                  onTap: () => setState(() => _selectedSlot = slot),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          _SectionLabel('Reason'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select a reason',
              filled: true,
              fillColor: AppColors.cardBgOf(context),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.inputRadius),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
            items: RescheduleModal.rescheduleReasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _reason = v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Notify patient',
                style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
            subtitle: Text(
              'Send SMS & app notification',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
            value: _notifyPatient,
            activeTrackColor: AppColors.doctorBlue.withValues(alpha: 0.5),
            activeThumbColor: AppColors.doctorBlue,
            onChanged: (v) => setState(() => _notifyPatient = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.doctorBlue,
              foregroundColor: AppColors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              ),
            ),
            child: Text(
              'Confirm Reschedule',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: AppTypography.bodySmall,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
      ),
    );
  }
}

class _PatientSummaryCard extends StatelessWidget {
  const _PatientSummaryCard({
    required this.patientName,
    required this.currentLabel,
  });

  final String patientName;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    final initial = patientName.trim().isNotEmpty
        ? patientName.trim()[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.15),
            child: Text(
              initial,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: AppColors.doctorBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patientName,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Current: $currentLabel',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 18, color: AppColors.doctorBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textSecondaryOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.doctorBlue.withValues(alpha: 0.12)
                : AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  selected ? AppColors.doctorBlue : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppColors.doctorBlue
                  : AppColors.textSecondaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
