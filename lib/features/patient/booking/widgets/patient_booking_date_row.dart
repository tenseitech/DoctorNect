import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';

/// Compact one-row date picker: month/year control + horizontal day chips.
class PatientBookingDateRow extends StatefulWidget {
  const PatientBookingDateRow({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    required this.isDayEnabled,
    this.isHoliday,
    this.holidayMessage,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime date) isDayEnabled;
  final bool Function(DateTime date)? isHoliday;
  final String? Function(DateTime date)? holidayMessage;

  @override
  State<PatientBookingDateRow> createState() => _PatientBookingDateRowState();
}

class _PatientBookingDateRowState extends State<PatientBookingDateRow> {
  static const int _minPickerYear = 2020;
  static int get _maxPickerYear => DateTime.now().year + 2;

  late DateTime _focusedMonth;
  final _dayScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(PatientBookingDateRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameMonth(_focusedMonth, widget.selectedDate)) {
      _focusedMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    }
    if (!_sameDay(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _dayScrollController.dispose();
    super.dispose();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  List<DateTime> get _daysInFocusedMonth {
    final count = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    return List.generate(count, (i) {
      return DateTime(_focusedMonth.year, _focusedMonth.month, i + 1);
    }).where((d) => widget.isDayEnabled(d) || (widget.isHoliday?.call(d) ?? false)).toList();
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _scrollToSelected() {
    if (!_dayScrollController.hasClients) return;
    final days = _daysInFocusedMonth;
    final index = days.indexWhere((d) => _sameDay(d, widget.selectedDate));
    if (index < 0) return;
    const itemWidth = 52.0;
    const gap = 8.0;
    final offset = (index * (itemWidth + gap)).clamp(
      0.0,
      _dayScrollController.position.maxScrollExtent,
    );
    _dayScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onDayTap(DateTime date) {
    final message = widget.holidayMessage?.call(date);
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!widget.isDayEnabled(date)) return;
    widget.onDateSelected(date);
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
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
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
                        fontSize: 12,
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
                              child: Text('$y', style: GoogleFonts.inter(fontSize: 14)),
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
                        fontSize: 12,
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
                                color: isSelected ? AppColors.patientTeal : AppColors.cardBgOf(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? AppColors.patientTeal : AppColors.borderOf(context),
                                ),
                              ),
                              child: Text(
                                label,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
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
                    backgroundColor: AppColors.patientTeal,
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

    if (picked == null || !mounted) return;

    setState(() {
      _focusedMonth = DateTime(picked.year, picked.month);
    });

    final days = _daysInFocusedMonth;
    if (days.isNotEmpty && !days.any((d) => _sameDay(d, widget.selectedDate))) {
      final firstBookable = days.firstWhere(
        (d) => !(widget.isHoliday?.call(d) ?? false),
        orElse: () => days.first,
      );
      widget.onDateSelected(firstBookable);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysInFocusedMonth;
    final monthName = DateFormat('MMM').format(_focusedMonth);
    final yearName = DateFormat('yyyy').format(_focusedMonth);

    const rowHeight = 76.0;
    const chipHeight = 64.0;

    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: chipHeight,
            width: 138,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Row(
                children: [
                  _MonthNavButton(
                    icon: Icons.chevron_left,
                    onTap: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pickMonthYear,
                        borderRadius: BorderRadius.circular(6),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                monthName,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                yearName,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondaryOf(context),
                                  height: 1.1,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.patientTeal),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _MonthNavButton(
                    icon: Icons.chevron_right,
                    onTap: () => _shiftMonth(1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: days.isEmpty
                ? Center(
                    child: Text(
                      'No dates this month',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                    ),
                  )
                : SizedBox(
                    height: chipHeight,
                    child: ListView.separated(
                      controller: _dayScrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: days.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final d = days[i];
                        final selected = _sameDay(d, widget.selectedDate);
                        final isHoliday = widget.isHoliday?.call(d) ?? false;

                        final bgColor = selected
                            ? AppColors.patientTeal
                            : isHoliday
                                ? const Color(0xFFFFF7ED)
                                : AppColors.cardBgOf(context);
                        final borderColor = selected
                            ? AppColors.patientTeal
                            : isHoliday
                                ? const Color(0xFFFDBA74)
                                : AppColors.borderOf(context);
                        final dayColor = selected
                            ? AppColors.white
                            : isHoliday
                                ? const Color(0xFFC2410C)
                                : AppColors.textPrimaryOf(context);
                        final weekdayColor = selected
                            ? AppColors.white
                            : isHoliday
                                ? const Color(0xFFEA580C)
                                : AppColors.textSecondaryOf(context);

                        return GestureDetector(
                          onTap: () => _onDayTap(d),
                          child: Container(
                            width: 52,
                            height: chipHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE').format(d),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    height: 1,
                                    color: weekdayColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('d').format(d),
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    color: dayColor,
                                  ),
                                ),
                                if (isHoliday && !selected) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Off',
                                    style: GoogleFonts.inter(
                                      fontSize: 7,
                                      height: 1,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFEA580C),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: AppColors.patientTeal),
        ),
      ),
    );
  }
}
