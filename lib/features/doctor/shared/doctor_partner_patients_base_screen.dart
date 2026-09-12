import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';

/// Unified base screen for Doctor viewing patient prescriptions (Pharmacy) or lab test orders (Diagnostic Lab).
class DoctorPartnerPatientsBaseView<T> extends StatefulWidget {
  const DoctorPartnerPatientsBaseView({
    super.key,
    required this.partnerTitle,
    required this.sectionTitle,
    required this.accentColor,
    required this.listenable,
    required this.allItems,
    required this.itemDate,
    required this.searchPredicate,
    required this.isCompleted,
    required this.completedStatusLabel,
    required this.pendingStatusLabel,
    required this.emptyAllMessage,
    required this.tableHeaders,
    required this.columnWidths,
    required this.rowBuilder,
  });

  final String partnerTitle;
  final String sectionTitle;
  final Color accentColor;
  final Listenable listenable;
  final List<T> Function() allItems;
  final DateTime Function(T item) itemDate;
  final bool Function(T item, String query) searchPredicate;
  final bool Function(T item) isCompleted;
  final String completedStatusLabel;
  final String pendingStatusLabel;
  final String emptyAllMessage;
  final List<String> tableHeaders;
  final Map<int, TableColumnWidth> columnWidths;
  final List<Widget> Function(BuildContext context, T item, DateFormat dateFormat) rowBuilder;

  @override
  State<DoctorPartnerPatientsBaseView<T>> createState() => _DoctorPartnerPatientsBaseViewState<T>();
}

class _DoctorPartnerPatientsBaseViewState<T> extends State<DoctorPartnerPatientsBaseView<T>> {
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');
  late DateTime _selectedDate;
  bool _showAllDates = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<T> _filterByDate(List<T> items) {
    if (_showAllDates) return items;
    return items.where((d) => _isSameDay(widget.itemDate(d), _selectedDate)).toList();
  }

  List<T> _filterBySearch(List<T> items) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) => widget.searchPredicate(item, q)).toList();
  }

  List<T> _applyFilters(List<T> items) {
    return _filterBySearch(_filterByDate(items));
  }

  void _setSelectedDate(DateTime date) {
    setState(() {
      _showAllDates = false;
      _selectedDate = DateTime(date.year, date.month, date.day);
    });
  }

  void _goToToday() {
    setState(() {
      _showAllDates = false;
      final now = DateTime.now();
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _shiftDate(int days) {
    final next = _selectedDate.add(Duration(days: days));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (next.isAfter(today)) return;
    _setSelectedDate(next);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _setSelectedDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderOf(context);
    final cardColor = AppColors.cardBgOf(context);

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        title: Text(widget.partnerTitle, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surfaceOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: borderColor),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.listenable,
        builder: (context, _) {
          final all = widget.allItems();
          final forDate = _filterByDate(all);
          final filtered = _applyFilters(all);
          final completedCount = forDate.where(widget.isCompleted).length;
          final pendingCount = forDate.length - completedCount;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.sectionTitle,
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _showAllDates
                                  ? 'All records • $completedCount ${widget.completedStatusLabel} • $pendingCount ${widget.pendingStatusLabel} • ${forDate.length} total'
                                  : _isToday
                                      ? 'Today • $completedCount ${widget.completedStatusLabel} • $pendingCount ${widget.pendingStatusLabel} • ${forDate.length} total'
                                      : '${_dateFormat.format(_selectedDate)} • $completedCount ${widget.completedStatusLabel} • $pendingCount ${widget.pendingStatusLabel} • ${forDate.length} total',
                              style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                      ),
                      // Filter toggle: All vs By Date
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => setState(() => _showAllDates = true),
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _showAllDates ? widget.accentColor.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                ),
                                child: Text(
                                  'All (${all.length})',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: _showAllDates ? FontWeight.w700 : FontWeight.w500,
                                    color: _showAllDates ? widget.accentColor : AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ),
                            Container(width: 1, height: 20, color: borderColor),
                            InkWell(
                              onTap: () => setState(() => _showAllDates = false),
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: !_showAllDates ? widget.accentColor.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                ),
                                child: Text(
                                  'By Date',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: !_showAllDates ? FontWeight.w700 : FontWeight.w500,
                                    color: !_showAllDates ? widget.accentColor : AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!_showAllDates) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _shiftDate(-1),
                          icon: const Icon(Icons.chevron_left, size: 22),
                          tooltip: 'Previous day',
                          style: IconButton.styleFrom(
                            backgroundColor: cardColor,
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondaryOf(context)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _isToday ? 'Today • ${_dateFormat.format(_selectedDate)}' : _dateFormat.format(_selectedDate),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.arrow_drop_down, color: AppColors.textSecondaryOf(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isToday ? null : () => _shiftDate(1),
                          icon: const Icon(Icons.chevron_right, size: 22),
                          tooltip: 'Next day',
                          style: IconButton.styleFrom(
                            backgroundColor: cardColor,
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (!_isToday) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _goToToday,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.doctorBlue,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            child: Text('Today', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Search patient name...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.accentColor, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          all.isEmpty
                              ? widget.emptyAllMessage
                              : !_showAllDates && forDate.isEmpty
                                  ? 'No records on ${_dateFormat.format(_selectedDate)}. Switch to "All" or pick another date.'
                                  : 'No records match your search.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Table(
                          border: TableBorder.all(color: borderColor.withValues(alpha: 0.5), width: 0.5),
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          columnWidths: widget.columnWidths,
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: cardColor),
                              children: [
                                for (final h in widget.tableHeaders)
                                  DocPartnerTableHeaderCell(h),
                              ],
                            ),
                            for (var i = 0; i < filtered.length; i++)
                              TableRow(
                                decoration: BoxDecoration(
                                  color: i.isEven ? AppColors.surfaceOf(context) : cardColor.withValues(alpha: 0.35),
                                ),
                                children: widget.rowBuilder(context, filtered[i], _dateFormat),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class DocPartnerTableHeaderCell extends StatelessWidget {
  const DocPartnerTableHeaderCell(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }
}

class DocPartnerTableBodyCell extends StatelessWidget {
  const DocPartnerTableBodyCell(this.text, {super.key, this.bold = false, this.color});

  final String text;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          height: 1.35,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}