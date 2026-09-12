import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import 'patient_profile_form_styles.dart';

class TagInputField extends StatefulWidget {
  const TagInputField({
    super.key,
    required this.label,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final List<String> tags;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends State<TagInputField> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validateTag(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final req = FormValidators.tagText(trimmed, field: widget.label);
    if (req != null) return req;
    if (widget.tags.length >= 20) return 'Maximum 20 tags allowed';
    if (widget.tags.any((t) => t.toLowerCase() == trimmed.toLowerCase())) {
      return 'Already added';
    }
    return null;
  }

  void _add() {
    final error = _validateTag(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    setState(() => _errorText = null);
    widget.onAdd(trimmed);
    _controller.clear();
  }

  static String _sectionTitle(String label) {
    final lower = label.toLowerCase();
    if (lower == 'allergy') return 'Allergies';
    if (lower == 'condition') return 'Conditions';
    return '${label[0].toUpperCase()}${label.substring(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PatientProfileFormStyles.sectionLabel(_sectionTitle(widget.label)),
        const SizedBox(height: 8),
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags.map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.patientTeal),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 14, color: AppColors.patientTeal),
                    const SizedBox(width: 4),
                    Text(
                      t,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.patientTeal,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => widget.onRemove(t),
                      child: Icon(Icons.close, size: 14, color: AppColors.patientTeal),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        if (widget.tags.isNotEmpty) const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: PatientProfileFormStyles.fieldDecoration(context, 
                  labelText: 'Add ${widget.label}',
                  hintText: 'Type and press +',
                ).copyWith(errorText: _errorText),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
