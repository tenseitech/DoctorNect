import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Configuration for customizing the calendar appearance.
///
/// All fields are optional — unset fields fall back to the widget's defaults.
class CalendarThemeConfig {
  const CalendarThemeConfig({
    this.accentColor,
    this.backgroundColor,
    this.borderColor,
    this.headerStyle,
    this.dayLabelStyle,
    this.dayNumberStyle,
    this.dayLabels,
  });

  /// Primary color used for selected day, navigation arrows, dots.
  final Color? accentColor;

  /// Background color of the calendar container.
  final Color? backgroundColor;

  /// Border color of the calendar container (null = default `AppColors.borderOf(context)`).
  final Color? borderColor;

  /// Text style override for the month/year header.
  final TextStyle? headerStyle;

  /// Text style override for the weekday labels row (S M T W T F S).
  final TextStyle? dayLabelStyle;

  /// Base text style for day numbers (weight/color are still adjusted for
  /// selected/today states).
  final TextStyle? dayNumberStyle;

  /// Custom weekday labels. Must have exactly 7 entries (Sun → Sat).
  final List<String>? dayLabels;
}

class DoctorAppointmentCalendar extends StatefulWidget {
  const DoctorAppointmentCalendar({
    super.key,
    required this.doctorId,
    required this.selectedDate,
    required this.onDateSelected,
    this.compact = false,
    this.themeConfig,
    this.isDayEnabled,
    this.showAppointmentDots = true,
  });

  final String doctorId;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool compact;

  /// When set, days that return false are shown disabled and cannot be selected.
  final bool Function(DateTime date)? isDayEnabled;

  /// When false, hides dots for days that already have appointments.
  final bool showAppointmentDots;

  /// Optional theme configuration for colors, fonts, and labels.
  final CalendarThemeConfig? themeConfig;

  static Future<void> showPopup(
    BuildContext context, {
    required String doctorId,
    required DateTime selectedDate,
    required ValueChanged<DateTime> onDateSelected,
    CalendarThemeConfig? themeConfig,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DoctorAppointmentCalendar(
            compact: true,
            doctorId: doctorId,
            selectedDate: selectedDate,
            themeConfig: themeConfig,
            onDateSelected: (date) {
              onDateSelected(date);
              Navigator.pop(dialogContext);
            },
          ),
        ),
      ),
    );
  }

  @override
  State<DoctorAppointmentCalendar> createState() => _DoctorAppointmentCalendarState();
}

class _DoctorAppointmentCalendarState extends State<DoctorAppointmentCalendar> {
  final _store = SharedAppointmentsStore.instance;

  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    var month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    final min = DateTime(DateTime.now().year, 1);
    if (month.isBefore(min)) month = min;
    _focusedMonth = month;
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Set<DateTime> get _datesWithAppointments =>
      _store.appointmentDatesForDoctorInMonth(
        widget.doctorId,
        _focusedMonth.year,
        _focusedMonth.month,
      );

  static int get _minPickerYear => DateTime.now().year;
  static int get _maxPickerYear => DateTime.now().year + 2;

  DateTime get _minFocusedMonth {
    final now = DateTime.now();
    return DateTime(now.year, 1);
  }

  bool get _canGoToPreviousMonth {
    final min = _minFocusedMonth;
    return _focusedMonth.year > min.year ||
        (_focusedMonth.year == min.year && _focusedMonth.month > min.month);
  }

  bool get _canGoToNextMonth {
    final max = DateTime(_maxPickerYear, 12);
    return _focusedMonth.year < max.year ||
        (_focusedMonth.year == max.year && _focusedMonth.month < max.month);
  }

  void _setFocusedMonth(DateTime month) {
    final min = _minFocusedMonth;
    final max = DateTime(_maxPickerYear, 12);
    var next = DateTime(month.year, month.month);
    if (next.isBefore(min)) next = min;
    if (next.isAfter(max)) next = max;
    setState(() => _focusedMonth = next);
  }

  Future<void> _pickMonthYear() async {
    var year = _focusedMonth.year;
    var month = _focusedMonth.month;

    final picked = await showDialog<({int year, int month})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final years = List.generate(
              _maxPickerYear - _minPickerYear + 1,
              (i) => _minPickerYear + i,
            );

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Select month & year',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: AppTypography.headlineSmall),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Year',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      key: ValueKey(year),
                      initialValue: year,
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.borderOf(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.borderOf(context)),
                        ),
                      ),
                      items: years
                          .map(
                            (y) => DropdownMenuItem(
                              value: y,
                              child: Text('$y', style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => year = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Month',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.4,
                      children: List.generate(12, (index) {
                        final m = index + 1;
                        final isSelected = m == month;
                        final label = DateFormat('MMM').format(DateTime(2024, m));

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setDialogState(() => month = m),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? _accent : AppColors.cardBgOf(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? _accent : AppColors.borderOf(context),
                                ),
                              ),
                              child: Text(
                                label,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, (year: year, month: month)),
                  child: Text('Apply', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      _setFocusedMonth(DateTime(picked.year, picked.month));
    }
  }

  // ── Theme helpers ──

  Color get _accent => widget.themeConfig?.accentColor ?? AppColors.doctorBlue;

  @override
  Widget build(BuildContext context) {
    final config = widget.themeConfig;
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday = monthStart.weekday % 7;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final selectedDate = widget.selectedDate;
    final compact = widget.compact;
    final padding = compact ? 12.0 : 14.0;
    final monthFontSize = compact ? 14.0 : 15.0;
    final dayFontSize = compact ? 12.0 : 13.0;
    final dayLabels = config?.dayLabels ?? const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: config?.backgroundColor ?? AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: compact ? null : Border.all(color: config?.borderColor ?? AppColors.borderOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _canGoToPreviousMonth
                    ? () => _setFocusedMonth(
                          DateTime(_focusedMonth.year, _focusedMonth.month - 1),
                        )
                    : null,
                icon: Icon(
                  Icons.chevron_left,
                  color: _canGoToPreviousMonth
                      ? _accent
                      : AppColors.textSecondaryOf(context).withValues(alpha: 0.35),
                ),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickMonthYear,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              DateFormat('MMMM yyyy').format(_focusedMonth),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: config?.headerStyle ??
                                  GoogleFonts.inter(
                                    fontSize: monthFontSize,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down, size: 22, color: _accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _canGoToNextMonth
                    ? () => _setFocusedMonth(
                          DateTime(_focusedMonth.year, _focusedMonth.month + 1),
                        )
                    : null,
                icon: Icon(
                  Icons.chevron_right,
                  color: _canGoToNextMonth
                      ? _accent
                      : AppColors.textSecondaryOf(context).withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: dayLabels.map((label) {
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: config?.dayLabelStyle ??
                        GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondaryOf(context),
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: compact ? 2 : 4,
              crossAxisSpacing: compact ? 2 : 4,
              childAspectRatio: compact ? 1.15 : 1.1,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox.shrink();

              final day = index - firstWeekday + 1;
              final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
              final isSelected = _isSameDay(date, selectedDate);
              final isToday = _isSameDay(date, todayDay);
              final enabled = widget.isDayEnabled?.call(date) ?? true;
              final hasAppointments = widget.showAppointmentDots &&
                  _datesWithAppointments.any((d) => _isSameDay(d, date));

              final baseDayStyle = config?.dayNumberStyle;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? () => widget.onDateSelected(date) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _accent
                          : isToday && enabled
                              ? _accent.withValues(alpha: 0.1)
                              : null,
                      borderRadius: BorderRadius.circular(8),
                      border: isToday && !isSelected && enabled
                          ? Border.all(color: _accent.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: (baseDayStyle ?? GoogleFonts.inter(fontSize: dayFontSize)).copyWith(
                            fontWeight: isSelected || (isToday && enabled)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: !enabled
                                ? AppColors.textSecondaryOf(context).withValues(alpha: 0.45)
                                : isSelected
                                    ? Colors.white
                                    : isToday
                                        ? _accent
                                        : baseDayStyle?.color ?? AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (hasAppointments) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.surfaceOf(context) : _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
