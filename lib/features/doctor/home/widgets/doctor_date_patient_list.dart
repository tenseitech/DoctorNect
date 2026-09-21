import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../appointments/appointment_utils.dart';
import '../../models/doctor_models.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../../../../core/theme/app_typography.dart';

String _familyRelationLabel(Appointment appointment) {
  final relation = appointment.patientRelation?.trim();
  final booker = appointment.bookedByName?.trim();
  final patient = appointment.patientName.trim();
  if (relation != null && relation.isNotEmpty) {
    if (relation.toLowerCase() == 'self') {
      return patient;
    }
    if (booker != null &&
        booker.isNotEmpty &&
        booker.toLowerCase() != patient.toLowerCase()) {
      return '$patient ($relation of $booker)';
    }
    return '$patient ($relation)';
  }
  if (booker != null &&
      booker.isNotEmpty &&
      booker.toLowerCase() != patient.toLowerCase()) {
    return '$patient (Relative of $booker)';
  }
  return patient;
}

bool _isBookerSelf(Appointment appointment) {
  final booker = appointment.bookedByName?.trim();
  if (booker == null || booker.isEmpty) return false;
  final relation = appointment.patientRelation?.trim().toLowerCase();
  if (relation == 'self') return true;
  return appointment.patientName.trim().toLowerCase() == booker.toLowerCase();
}

int _familyMemberSortOrder(Appointment appointment) {
  if (_isBookerSelf(appointment)) return 0;
  return 1;
}

bool _belongsToFamilyGroup(
    Appointment candidate, String booker, Appointment anchor) {
  if (candidate.timeSlot != anchor.timeSlot ||
      !_sameDay(candidate.appointmentDate, anchor.appointmentDate)) {
    return false;
  }

  final candidateBooker = candidate.bookedByName?.trim();
  if (candidateBooker != null &&
      candidateBooker.isNotEmpty &&
      candidateBooker == booker) {
    return true;
  }

  if ((candidateBooker == null || candidateBooker.isEmpty) &&
      candidate.patientName.trim().toLowerCase() == booker.toLowerCase()) {
    return true;
  }

  return false;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

List<_QueueEntry> _groupAppointments(List<Appointment> appointments) {
  final used = <String>{};
  final entries = <_QueueEntry>[];

  for (final appt in appointments) {
    if (used.contains(appt.id)) continue;

    final booker = appt.bookedByName?.trim();
    if (booker == null || booker.isEmpty) {
      continue;
    }

    final group = appointments.where((a) {
      if (used.contains(a.id)) return false;
      return _belongsToFamilyGroup(a, booker, appt);
    }).toList()
      ..sort((a, b) {
        final order =
            _familyMemberSortOrder(a).compareTo(_familyMemberSortOrder(b));
        if (order != 0) return order;
        return a.tokenNumber.compareTo(b.tokenNumber);
      });

    if (group.length > 1) {
      for (final member in group) {
        used.add(member.id);
      }
      entries.add(_QueueEntry.family(group));
    }
  }

  for (final appt in appointments) {
    if (used.contains(appt.id)) continue;
    entries.add(_QueueEntry.single(appt));
    used.add(appt.id);
  }

  return entries;
}

class _QueueEntry {
  const _QueueEntry._({this.appointment, this.members});

  factory _QueueEntry.single(Appointment appointment) =>
      _QueueEntry._(appointment: appointment);

  factory _QueueEntry.family(List<Appointment> members) =>
      _QueueEntry._(members: members);

  final Appointment? appointment;
  final List<Appointment>? members;

  bool get isFamily => members != null;

  Appointment get primary => isFamily ? members!.first : appointment!;
}

String _formatUpcomingAppointmentDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final tomorrow = today.add(const Duration(days: 1));

  if (day == today) {
    return 'Today · ${DateFormat('EEE, d MMM yyyy').format(date)}';
  }
  if (day == tomorrow) {
    return 'Tomorrow · ${DateFormat('EEE, d MMM yyyy').format(date)}';
  }
  return DateFormat('EEE, d MMM yyyy').format(date);
}

List<_QueueEntry> _sortedUpcomingEntries(List<Appointment> appointments) {
  final sorted = List<Appointment>.from(appointments)
    ..sort((a, b) {
      final byDate = a.appointmentDate.compareTo(b.appointmentDate);
      if (byDate != 0) return byDate;
      return a.timeSlot.compareTo(b.timeSlot);
    });

  final entries = _groupAppointments(sorted)
    ..sort((a, b) {
      final pa = a.primary;
      final pb = b.primary;
      final byDate = pa.appointmentDate.compareTo(pb.appointmentDate);
      if (byDate != 0) return byDate;
      return pa.timeSlot.compareTo(pb.timeSlot);
    });

  return entries;
}

List<_QueueEntry> _sortedTodayEntries(List<Appointment> appointments) {
  final entries = _groupAppointments(appointments)
    ..sort((a, b) => a.primary.timeSlot.compareTo(b.primary.timeSlot));
  return entries;
}

/// Clean appointment list for doctor home (today + upcoming).
class DoctorDatePatientList extends StatelessWidget {
  const DoctorDatePatientList({
    super.key,
    required this.selectedDate,
    required this.appointments,
    this.onViewAppointment,
    this.onAccept,
    this.onAcceptFamily,
    this.onDecline,
    this.onStart,
    this.onCancel,
    this.showActions = true,
    this.showDateHeader = false,
    this.emptyMessage = 'No patients on this date',
  });

  final DateTime selectedDate;
  final List<Appointment> appointments;
  final void Function(Appointment appointment)? onViewAppointment;
  final void Function(Appointment appointment)? onAccept;
  final void Function(List<Appointment> members)? onAcceptFamily;
  final void Function(Appointment appointment)? onDecline;
  final void Function(Appointment appointment)? onStart;
  final void Function(Appointment appointment)? onCancel;
  final bool showActions;
  final bool showDateHeader;
  final String emptyMessage;

  bool get _isToday {
    final now = DateTime.now();
    return selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return _EmptyQueueCard(message: emptyMessage);
    }

    final entries = _sortedTodayEntries(appointments);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateHeader) ...[
          _DateGroupHeader(
            date: selectedDate,
            count: appointments.length,
            emphasizeToday: _isToday,
          ),
          const SizedBox(height: 10),
        ],
        _TodayPatientsGrid(
          entries: entries,
          showActions: showActions && _isToday,
          onViewAppointment: onViewAppointment,
          onAccept: onAccept,
          onAcceptFamily: onAcceptFamily,
          onDecline: onDecline,
          onStart: onStart,
        ),
        if (_isToday && ResponsiveLayout.isCompact(context))
          SizedBox(height: 56 + MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

/// Today's patients shown side by side, sorted by appointment time.
class _TodayPatientsGrid extends StatelessWidget {
  const _TodayPatientsGrid({
    required this.entries,
    required this.showActions,
    this.onViewAppointment,
    this.onAccept,
    this.onAcceptFamily,
    this.onDecline,
    this.onStart,
  });

  final List<_QueueEntry> entries;
  final bool showActions;
  final void Function(Appointment appointment)? onViewAppointment;
  final void Function(Appointment appointment)? onAccept;
  final void Function(List<Appointment> members)? onAcceptFamily;
  final void Function(Appointment appointment)? onDecline;
  final void Function(Appointment appointment)? onStart;

  bool _hasActionableStatus(Appointment appt) {
    return appt.status == AppointmentStatus.pendingRequest ||
        appt.status == AppointmentStatus.confirmed ||
        appt.status == AppointmentStatus.waiting ||
        appt.status == AppointmentStatus.inProgress;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final count = entries.length;
        final columns = switch (count) {
          1 => 1,
          _ when maxWidth < 560 => 1,
          _ when maxWidth >= 1000 => count.clamp(2, 3),
          _ => 2,
        };
        const gap = 14.0;
        final tileWidth = columns == 1
            ? maxWidth
            : (maxWidth - gap * (columns - 1)) / columns;
        final narrowTile = tileWidth < 220;
        final rows = <List<_QueueEntry>>[];

        for (var i = 0; i < entries.length; i += columns) {
          rows.add(entries.sublist(i, (i + columns).clamp(0, entries.length)));
        }

        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < rows[r].length; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(
                        child: _TodayPatientTile(
                          entry: rows[r][c],
                          showActions: showActions,
                          narrowTile: narrowTile,
                          onViewAppointment: onViewAppointment,
                          onAccept: onAccept,
                          onAcceptFamily: onAcceptFamily,
                          onDecline: onDecline,
                          onStart: onStart,
                          hasActionableStatus: _hasActionableStatus,
                        ),
                      ),
                    ],
                    if (rows[r].length < columns)
                      for (var c = rows[r].length; c < columns; c++) ...[
                        if (c > 0 || rows[r].isNotEmpty)
                          const SizedBox(width: gap),
                        const Expanded(child: SizedBox()),
                      ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TodayPatientTile extends StatelessWidget {
  const _TodayPatientTile({
    required this.entry,
    required this.showActions,
    required this.hasActionableStatus,
    this.narrowTile = true,
    this.onViewAppointment,
    this.onAccept,
    this.onAcceptFamily,
    this.onDecline,
    this.onStart,
  });

  final _QueueEntry entry;
  final bool showActions;
  final bool narrowTile;
  final bool Function(Appointment appt) hasActionableStatus;
  final void Function(Appointment appointment)? onViewAppointment;
  final void Function(Appointment appointment)? onAccept;
  final void Function(List<Appointment> members)? onAcceptFamily;
  final void Function(Appointment appointment)? onDecline;
  final void Function(Appointment appointment)? onStart;

  @override
  Widget build(BuildContext context) {
    if (entry.isFamily) {
      return _FamilyAppointmentCard(
        members: entry.members!,
        showActions: showActions,
        onView: onViewAppointment,
        onAcceptFamily: onAcceptFamily,
      );
    }

    final appointment = entry.appointment!;
    return _PatientAppointmentCard(
      appointment: appointment,
      showActions: showActions && hasActionableStatus(appointment),
      narrowTile: narrowTile,
      onView: onViewAppointment == null
          ? null
          : () => onViewAppointment!(appointment),
      onAccept: onAccept == null ? null : () => onAccept!(appointment),
      onDecline: onDecline == null ? null : () => onDecline!(appointment),
      onStart: onStart == null ? null : () => onStart!(appointment),
    );
  }
}

/// Upcoming appointments — flat grid sorted by nearest date; date shown on each card.
class DoctorUpcomingAppointmentsList extends StatelessWidget {
  const DoctorUpcomingAppointmentsList({
    super.key,
    required this.appointments,
    this.onViewAppointment,
  });

  final List<Appointment> appointments;
  final void Function(Appointment appointment)? onViewAppointment;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return const _EmptyQueueCard(message: 'No upcoming appointments');
    }

    final entries = _sortedUpcomingEntries(appointments);

    return _UpcomingEqualWidthRow(
      entries: entries,
      onViewAppointment: onViewAppointment,
    );
  }
}

/// Each booking gets equal horizontal space in a responsive side-by-side grid.
class _UpcomingEqualWidthRow extends StatelessWidget {
  const _UpcomingEqualWidthRow({
    required this.entries,
    this.onViewAppointment,
  });

  final List<_QueueEntry> entries;
  final void Function(Appointment appointment)? onViewAppointment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final count = entries.length;
        final columns = switch (count) {
          1 => 1,
          _ when maxWidth < 560 => 1,
          _ when maxWidth >= 1000 => count.clamp(2, 3),
          _ => 2,
        };
        const gap = 14.0;
        final rows = <List<_QueueEntry>>[];

        for (var i = 0; i < entries.length; i += columns) {
          rows.add(entries.sublist(i, (i + columns).clamp(0, entries.length)));
        }

        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < rows[r].length; c++) ...[
                      if (c > 0) const SizedBox(width: gap),
                      Expanded(
                        child: _UpcomingAppointmentTile(
                          entry: rows[r][c],
                          onViewAppointment: onViewAppointment,
                        ),
                      ),
                    ],
                    if (rows[r].length < columns)
                      for (var c = rows[r].length; c < columns; c++) ...[
                        if (c > 0 || rows[r].isNotEmpty)
                          const SizedBox(width: gap),
                        const Expanded(child: SizedBox()),
                      ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _UpcomingAppointmentTile extends StatefulWidget {
  const _UpcomingAppointmentTile({
    required this.entry,
    this.onViewAppointment,
  });

  final _QueueEntry entry;
  final void Function(Appointment appointment)? onViewAppointment;

  @override
  State<_UpcomingAppointmentTile> createState() =>
      _UpcomingAppointmentTileState();
}

class _UpcomingAppointmentTileState extends State<_UpcomingAppointmentTile> {
  bool _hovered = false;

  Appointment get _primary => widget.entry.isFamily
      ? widget.entry.members!.first
      : widget.entry.appointment!;

  Color get _accent {
    if (widget.entry.isFamily) {
      final pending = widget.entry.members!
          .any((m) => m.status == AppointmentStatus.pendingRequest);
      if (pending) return const Color(0xFFEA580C);
    }
    return AppointmentStatusStyle.color(_primary.status);
  }

  void _openPrimary() {
    final onView = widget.onViewAppointment;
    if (onView == null) return;
    onView(_primary);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final canOpen = widget.onViewAppointment != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: !widget.entry.isFamily && canOpen ? _openPrimary : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? accent.withValues(alpha: 0.35)
                    : AppColors.borderOf(context),
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: accent),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _UpcomingTileTopBar(
                            entry: widget.entry,
                            primary: _primary,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: widget.entry.isFamily
                                ? _UpcomingFamilyBody(
                                    members: widget.entry.members!,
                                    onView: widget.onViewAppointment,
                                  )
                                : _UpcomingSingleBody(
                                    appointment: widget.entry.appointment!),
                          ),
                          if (!widget.entry.isFamily && canOpen)
                            _UpcomingTileFooter(
                                hovered: _hovered, onTap: _openPrimary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingTypePill extends StatelessWidget {
  const _UpcomingTypePill({required this.type});

  final AppointmentType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppointmentStatusStyle.typeLabel(type),
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }
}

class _UpcomingTileTopBar extends StatelessWidget {
  const _UpcomingTileTopBar({
    required this.entry,
    required this.primary,
  });

  final _QueueEntry entry;
  final Appointment primary;

  @override
  Widget build(BuildContext context) {
    final appointmentDate = primary.appointmentDate;
    final dateLabel = _formatUpcomingAppointmentDate(appointmentDate);

    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 15,
                color: AppColors.doctorBlue.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Appointment · $dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.doctorBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                primary.timeSlot,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.3,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              _UpcomingTypePill(type: primary.type),
              const Spacer(),
              if (entry.isFamily)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 16,
                      color: AppColors.doctorBlue.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Family · ${entry.members!.length}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.doctorBlue,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingSingleBody extends StatelessWidget {
  const _UpcomingSingleBody({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final reason = appointment.reasonForVisit?.trim();
    final statusColor = AppointmentStatusStyle.color(appointment.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UpcomingAvatar(name: appointment.patientName, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          appointment.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyLarge,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(
                        label: AppointmentStatusStyle.label(appointment.status),
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${appointment.age} yrs · ${AppConstants.patientGenderLabel(appointment.gender)}',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _UpcomingFamilyBody extends StatelessWidget {
  const _UpcomingFamilyBody({
    required this.members,
    this.onView,
  });

  final List<Appointment> members;
  final void Function(Appointment appointment)? onView;

  @override
  Widget build(BuildContext context) {
    final booker = members.first.bookedByName?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (booker != null && booker.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Booked by $booker',
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppColors.borderOf(context)),
            ),
          _UpcomingFamilyMemberCard(
            member: members[i],
            onTap: onView == null ? null : () => onView!(members[i]),
          ),
        ],
      ],
    );
  }
}

class _UpcomingFamilyMemberCard extends StatefulWidget {
  const _UpcomingFamilyMemberCard({
    required this.member,
    this.onTap,
  });

  final Appointment member;
  final VoidCallback? onTap;

  @override
  State<_UpcomingFamilyMemberCard> createState() =>
      _UpcomingFamilyMemberCardState();
}

class _UpcomingFamilyMemberCardState extends State<_UpcomingFamilyMemberCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reason = widget.member.reasonForVisit?.trim();
    final statusColor = AppointmentStatusStyle.color(widget.member.status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UpcomingAvatar(name: widget.member.patientName, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              widget.member.patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyMedium,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusBadge(
                            label: AppointmentStatusStyle.label(
                                widget.member.status),
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _familyRelationLabel(widget.member),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context)),
                      ),
                      if (reason != null && reason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: _hovered
                          ? AppColors.doctorBlue
                          : AppColors.textSecondaryOf(context)
                              .withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingAvatar extends StatelessWidget {
  const _UpcomingAvatar({
    required this.name,
    required this.radius,
  });

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.1),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          fontSize: radius * 0.78,
          fontWeight: FontWeight.w700,
          color: AppColors.doctorBlue,
        ),
      ),
    );
  }
}

class _UpcomingTileFooter extends StatelessWidget {
  const _UpcomingTileFooter({
    required this.hovered,
    required this.onTap,
  });

  final bool hovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.doctorBlue,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View details',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color:
                      hovered ? const Color(0xFF1D4ED8) : AppColors.doctorBlue,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: hovered ? const Color(0xFF1D4ED8) : AppColors.doctorBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQueueCard extends StatelessWidget {
  const _EmptyQueueCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 36,
            color: AppColors.textSecondaryOf(context).withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateGroupHeader extends StatelessWidget {
  const _DateGroupHeader({
    required this.date,
    required this.count,
    this.emphasizeToday = false,
  });

  final DateTime date;
  final int count;
  final bool emphasizeToday;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday
        ? 'Today · ${DateFormat('EEE, d MMM').format(date)}'
        : DateFormat('EEE, d MMM yyyy').format(date);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
              color: emphasizeToday || isToday
                  ? AppColors.doctorBlue
                  : AppColors.textPrimaryOf(context),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.doctorBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              fontWeight: FontWeight.w700,
              color: AppColors.doctorBlue,
            ),
          ),
        ),
      ],
    );
  }
}

/// Age and gender on separate [Text] nodes so labels like Male/Female never break mid-word.
class _AgeGenderLabel extends StatelessWidget {
  const _AgeGenderLabel({
    required this.age,
    required this.gender,
  });

  final int age;
  final String gender;

  @override
  Widget build(BuildContext context) {
    final genderLabel = AppConstants.patientGenderLabel(gender);
    final metaStyle = GoogleFonts.inter(
      fontSize: AppTypography.labelMedium,
      color: AppColors.textSecondaryOf(context),
      height: 1.3,
    );

    return Wrap(
      spacing: 0,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$age yrs · ', style: metaStyle),
        Text(genderLabel, style: metaStyle),
      ],
    );
  }
}

class _PatientAppointmentCard extends StatelessWidget {
  const _PatientAppointmentCard({
    required this.appointment,
    required this.showActions,
    this.narrowTile = true,
    this.onView,
    this.onAccept,
    this.onDecline,
    this.onStart,
  });

  final Appointment appointment;
  final bool showActions;
  final bool narrowTile;
  final VoidCallback? onView;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onStart;

  static const double _avatarSize = 36;
  static const double _avatarGap = 10;
  static const double _metaIndent = _avatarSize + _avatarGap;

  @override
  Widget build(BuildContext context) {
    final reason = appointment.reasonForVisit?.trim();
    final compact = ResponsiveLayout.isCompact(context);
    final visitType = appointment.type == AppointmentType.newVisit
        ? 'New visit'
        : 'Follow-up';

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CompactAvatar(
                    name: appointment.patientName,
                    gender: appointment.gender,
                  ),
                  const SizedBox(width: _avatarGap),
                  Expanded(
                    child: Text(
                      appointment.patientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: _metaIndent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AgeGenderLabel(
                      age: appointment.age,
                      gender: appointment.gender,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          appointment.timeSlot,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            visitType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelSmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusBadge(
                    label: AppointmentStatusStyle.label(appointment.status),
                    color: AppointmentStatusStyle.color(appointment.status),
                  ),
                  if (appointment.slotShareReason != null &&
                      appointment.slotShareReason!.trim().isNotEmpty)
                    SharedSlotBadge(
                      slotShareReason: appointment.slotShareReason,
                      compact: true,
                    ),
                ],
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.35,
                  ),
                ),
              ],
              if (showActions && _primaryAction != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: compact ? double.infinity : null,
                  child: Align(
                    alignment:
                        compact ? Alignment.center : Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _primaryAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryActionColor,
                        minimumSize: Size(
                          compact ? double.infinity : 120,
                          narrowTile ? 38 : 36,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: narrowTile ? 8 : 16,
                          vertical: narrowTile ? 8 : 10,
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: narrowTile ? 11 : 13,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      child: Text(
                        _primaryActionLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ] else if (!showActions && onView != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'View details',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w600,
                      color: AppColors.doctorBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  VoidCallback? get _primaryAction {
    if (appointment.status == AppointmentStatus.pendingRequest &&
        onAccept != null) {
      return onAccept;
    }
    if ((appointment.status == AppointmentStatus.confirmed ||
            appointment.status == AppointmentStatus.waiting) &&
        onStart != null) {
      return onStart;
    }
    return onView;
  }

  String get _primaryActionLabel {
    if (appointment.status == AppointmentStatus.pendingRequest) return 'Accept';
    if (appointment.status == AppointmentStatus.confirmed ||
        appointment.status == AppointmentStatus.waiting) {
      return 'Start consultation';
    }
    return 'View';
  }

  Color get _primaryActionColor {
    if (appointment.status == AppointmentStatus.pendingRequest)
      return AppColors.doctorBlue;
    if (appointment.status == AppointmentStatus.confirmed ||
        appointment.status == AppointmentStatus.waiting) {
      return const Color(0xFF16A34A);
    }
    return AppColors.doctorBlue;
  }
}

class _FamilyAppointmentCard extends StatelessWidget {
  const _FamilyAppointmentCard({
    required this.members,
    required this.showActions,
    this.onView,
    this.onAcceptFamily,
  });

  final List<Appointment> members;
  final bool showActions;
  final void Function(Appointment appointment)? onView;
  final void Function(List<Appointment> members)? onAcceptFamily;

  Appointment get _primary => members.first;

  bool get _hasPending =>
      members.any((m) => m.status == AppointmentStatus.pendingRequest);

  int get _pendingCount =>
      members.where((m) => m.status == AppointmentStatus.pendingRequest).length;

  @override
  Widget build(BuildContext context) {
    final booker = _primary.bookedByName?.trim() ?? 'Patient';
    final compact = ResponsiveLayout.isCompact(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.doctorBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_outlined,
                    size: 18, color: AppColors.doctorBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Family booking · ${members.length}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Booked by $booker · ${_primary.timeSlot}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _FamilyMemberRow(
              member: members[i],
              onTap: onView == null ? null : () => onView!(members[i]),
            ),
          ],
          if (showActions && _hasPending && onAcceptFamily != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: compact ? double.infinity : null,
              child: Align(
                alignment: compact ? Alignment.center : Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => onAcceptFamily!(members),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.doctorBlue,
                    minimumSize: Size(compact ? double.infinity : 140, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600),
                  ),
                  child: Text('Accept all ($_pendingCount)'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyMemberRow extends StatelessWidget {
  const _FamilyMemberRow({
    required this.member,
    this.onTap,
  });

  final Appointment member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reason = member.reasonForVisit?.trim();

    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompactAvatar(
                  name: member.patientName, gender: member.gender, radius: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _familyRelationLabel(member),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(
                          label: AppointmentStatusStyle.label(member.status),
                          color: AppointmentStatusStyle.color(member.status),
                        ),
                        if (reason != null && reason.isNotEmpty)
                          Text(
                            reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color:
                      AppColors.textSecondaryOf(context).withValues(alpha: 0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAvatar extends StatelessWidget {
  const _CompactAvatar({
    required this.name,
    required this.gender,
    this.radius = 18,
  });

  final String name;
  final String gender;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = AppConstants.isFemalePatientGender(gender)
        ? const Color(0xFFDB2777)
        : AppColors.doctorBlue;

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
