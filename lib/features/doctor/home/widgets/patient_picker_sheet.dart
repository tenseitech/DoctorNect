import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/doctor_models.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../../../../core/theme/app_typography.dart';

class PatientPickerSheet extends StatefulWidget {
  const PatientPickerSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.appointments,
    this.showAppointmentDate = false,
    this.maxHeightFraction = defaultMaxHeightFraction,
    this.maxVisibleItems,
  });

  static const double defaultMaxHeightFraction = 0.72;

  static final Appointment _sizingPlaceholder = Appointment(
    id: '',
    tokenNumber: 0,
    patientName: ' ',
    age: 0,
    gender: 'Male',
    appointmentDate: DateTime(2026),
    timeSlot: ' ',
    status: AppointmentStatus.confirmed,
    type: AppointmentType.newVisit,
  );

  final String title;
  final String subtitle;
  final List<Appointment> appointments;
  final bool showAppointmentDate;
  final double maxHeightFraction;
  final int? maxVisibleItems;

  static Future<Appointment?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Appointment> appointments,
    bool showAppointmentDate = false,
    double maxHeightFraction = defaultMaxHeightFraction,
    int? maxVisibleItems,
  }) {
    return showModalBottomSheet<Appointment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PatientPickerSheet(
        title: title,
        subtitle: subtitle,
        appointments: appointments,
        showAppointmentDate: showAppointmentDate,
        maxHeightFraction: maxHeightFraction,
        maxVisibleItems: maxVisibleItems,
      ),
    );
  }

  @override
  State<PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<PatientPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Appointment> get _filtered {
    if (_query.trim().isEmpty) return widget.appointments;
    final q = _query.trim().toLowerCase();
    return widget.appointments
        .where((a) => a.patientName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxVisible = widget.maxVisibleItems;
    final capByVisibleCount =
        maxVisible != null && maxVisible > 0 && filtered.length > maxVisible;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight * widget.maxHeightFraction,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search patient by name…',
                    hintStyle: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    prefixIconColor: AppColors.textSecondaryOf(context),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: AppColors.textSecondaryOf(context),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.doctorBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_off_outlined,
                            size: 36,
                            color: AppColors.textSecondaryOf(context)
                                .withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _query.isEmpty
                                ? 'No patients to choose from'
                                : 'No patients found for "$_query"',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: capByVisibleCount
                        ? Stack(
                            children: [
                              ExcludeSemantics(
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: 0,
                                    child: SingleChildScrollView(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (var i = 0;
                                              i < maxVisible;
                                              i++) ...[
                                            if (i > 0)
                                              const SizedBox(height: 8),
                                            _PatientRow(
                                              appointment: PatientPickerSheet
                                                  ._sizingPlaceholder,
                                              showAppointmentDate:
                                                  widget.showAppointmentDate,
                                              onTap: () {},
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final a = filtered[index];
                                    return _PatientRow(
                                      appointment: a,
                                      showAppointmentDate:
                                          widget.showAppointmentDate,
                                      onTap: () => Navigator.pop(context, a),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final a = filtered[index];
                              return _PatientRow(
                                appointment: a,
                                showAppointmentDate: widget.showAppointmentDate,
                                onTap: () => Navigator.pop(context, a),
                              );
                            },
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

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.appointment,
    required this.onTap,
    this.showAppointmentDate = false,
  });

  final Appointment appointment;
  final VoidCallback onTap;
  final bool showAppointmentDate;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('dd MMM yyyy').format(appointment.appointmentDate);
    final details = showAppointmentDate
        ? '$dateLabel · ${appointment.timeSlot}'
        : '${appointment.age} yrs · ${AppConstants.patientGenderLabel(appointment.gender)} · ${appointment.timeSlot}';

    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              PatientAvatar(
                name: appointment.patientName,
                gender: appointment.gender,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
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
