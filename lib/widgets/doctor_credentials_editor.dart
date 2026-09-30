import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import 'qualification_selector.dart';
import 'specialization_selector.dart';

class _CredentialItem {
  _CredentialItem({required this.id, required this.value});
  final String id;
  String value;
}

/// Reusable editor for doctor degrees / qualifications.
///
/// Supports repeatable entries (1 to 5), "+ Add another degree" button,
/// remove (x) button on extra entries, duplicate validation, and inline errors.
class DoctorDegreesEditor extends StatefulWidget {
  const DoctorDegreesEditor({
    super.key,
    required this.initialDegrees,
    required this.onChanged,
    this.accentColor = AppColors.doctorBlue,
    this.registrationStyle = false,
  });

  final List<String> initialDegrees;
  final ValueChanged<List<String>> onChanged;
  final Color accentColor;
  final bool registrationStyle;

  @override
  State<DoctorDegreesEditor> createState() => _DoctorDegreesEditorState();
}

class _DoctorDegreesEditorState extends State<DoctorDegreesEditor> {
  static int _idCounter = 0;
  late final List<_CredentialItem> _items;

  @override
  void initState() {
    super.initState();
    final nonNullInitial = widget.initialDegrees
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();

    if (nonNullInitial.isEmpty) {
      _items = [_CredentialItem(id: 'deg_${++_idCounter}', value: '')];
    } else {
      _items = nonNullInitial
          .take(5)
          .map((d) => _CredentialItem(id: 'deg_${++_idCounter}', value: d))
          .toList();
    }
  }

  void _notifyParent() {
    final values = _items
        .map((item) => item.value.trim())
        .where((val) => val.isNotEmpty)
        .toList();
    widget.onChanged(values);
  }

  void _addEntry() {
    if (_items.length >= 5) return;
    setState(() {
      _items.add(_CredentialItem(id: 'deg_${++_idCounter}', value: ''));
    });
    _notifyParent();
  }

  void _removeEntry(int index) {
    if (_items.length <= 1 || index <= 0 || index >= _items.length) return;
    setState(() {
      _items.removeAt(index);
    });
    _notifyParent();
  }

  String? _validateDegree(int index, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return index == 0
          ? 'At least 1 degree is required'
          : 'Degree is required';
    }
    // Check duplicates (case-insensitive, trimmed)
    for (int i = 0; i < _items.length; i++) {
      if (i != index &&
          _items[i].value.trim().toLowerCase() == trimmed.toLowerCase()) {
        return 'Duplicate degree not allowed';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            key: ValueKey(_items[i].id),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QualificationSelector(
                  initialValue:
                      _items[i].value.isEmpty ? null : _items[i].value,
                  onChanged: (val) {
                    _items[i].value = val ?? '';
                    _notifyParent();
                  },
                  isRequired: true,
                  accentColor: widget.accentColor,
                  label: i == 0
                      ? 'Degree / qualification *'
                      : 'Additional degree *',
                  registrationStyle: widget.registrationStyle,
                  validator: (v) => _validateDegree(i, v),
                ),
              ),
              if (i > 0) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    tooltip: 'Remove degree',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.04),
                    ),
                    onPressed: () => _removeEntry(i),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (_items.length < 5) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addEntry,
              icon:
                  Icon(Icons.add_rounded, size: 18, color: widget.accentColor),
              label: Text(
                '+ Add another degree',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Reusable editor for doctor specializations.
///
/// Supports repeatable entries (1 to 5), "+ Add another specialization" button,
/// remove (x) button on extra entries, duplicate validation, and inline errors.
class DoctorSpecializationsEditor extends StatefulWidget {
  const DoctorSpecializationsEditor({
    super.key,
    required this.initialSpecializations,
    required this.onChanged,
    this.accentColor = AppColors.doctorBlue,
  });

  final List<String> initialSpecializations;
  final ValueChanged<List<String>> onChanged;
  final Color accentColor;

  @override
  State<DoctorSpecializationsEditor> createState() =>
      _DoctorSpecializationsEditorState();
}

class _DoctorSpecializationsEditorState
    extends State<DoctorSpecializationsEditor> {
  static int _idCounter = 0;
  late final List<_CredentialItem> _items;

  @override
  void initState() {
    super.initState();
    final nonNullInitial = widget.initialSpecializations
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (nonNullInitial.isEmpty) {
      _items = [_CredentialItem(id: 'spec_${++_idCounter}', value: '')];
    } else {
      _items = nonNullInitial
          .take(5)
          .map((s) => _CredentialItem(id: 'spec_${++_idCounter}', value: s))
          .toList();
    }
  }

  void _notifyParent() {
    final values = _items
        .map((item) => item.value.trim())
        .where((val) => val.isNotEmpty)
        .toList();
    widget.onChanged(values);
  }

  void _addEntry() {
    if (_items.length >= 5) return;
    setState(() {
      _items.add(_CredentialItem(id: 'spec_${++_idCounter}', value: ''));
    });
    _notifyParent();
  }

  void _removeEntry(int index) {
    if (_items.length <= 1 || index <= 0 || index >= _items.length) return;
    setState(() {
      _items.removeAt(index);
    });
    _notifyParent();
  }

  String? _validateSpecialization(int index, String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return index == 0
          ? 'At least 1 specialization is required'
          : 'Specialization is required';
    }
    // Check duplicates (case-insensitive, trimmed)
    for (int i = 0; i < _items.length; i++) {
      if (i != index &&
          _items[i].value.trim().toLowerCase() == trimmed.toLowerCase()) {
        return 'Duplicate specialization not allowed';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            key: ValueKey(_items[i].id),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SpecializationSelector(
                  initialValue:
                      _items[i].value.isEmpty ? null : _items[i].value,
                  onChanged: (val) {
                    _items[i].value = val ?? '';
                    _notifyParent();
                  },
                  isRequired: true,
                  accentColor: widget.accentColor,
                  label: i == 0
                      ? 'Specialization *'
                      : 'Additional specialization *',
                  validator: (v) => _validateSpecialization(i, v),
                ),
              ),
              if (i > 0) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    tooltip: 'Remove specialization',
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(8),
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.04),
                    ),
                    onPressed: () => _removeEntry(i),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (_items.length < 5) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addEntry,
              icon:
                  Icon(Icons.add_rounded, size: 18, color: widget.accentColor),
              label: Text(
                '+ Add another specialization',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Combined reusable widget for both repeatable Degrees and Specializations.
class DoctorCredentialsEditor extends StatelessWidget {
  const DoctorCredentialsEditor({
    super.key,
    required this.initialDegrees,
    required this.initialSpecializations,
    required this.onDegreesChanged,
    required this.onSpecializationsChanged,
    this.accentColor = AppColors.doctorBlue,
    this.registrationStyle = false,
  });

  final List<String> initialDegrees;
  final List<String> initialSpecializations;
  final ValueChanged<List<String>> onDegreesChanged;
  final ValueChanged<List<String>> onSpecializationsChanged;
  final Color accentColor;
  final bool registrationStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DoctorDegreesEditor(
          initialDegrees: initialDegrees,
          onChanged: onDegreesChanged,
          accentColor: accentColor,
          registrationStyle: registrationStyle,
        ),
        const SizedBox(height: 14),
        DoctorSpecializationsEditor(
          initialSpecializations: initialSpecializations,
          onChanged: onSpecializationsChanged,
          accentColor: accentColor,
        ),
      ],
    );
  }
}
