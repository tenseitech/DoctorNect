import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/overflow_safe_layout.dart';
import '../../../../widgets/required_field_label.dart';
import '../models/booking_models.dart';
import '../../../../core/theme/app_typography.dart';

class AddFamilyMemberSheet extends StatefulWidget {
  const AddFamilyMemberSheet({super.key});

  @override
  State<AddFamilyMemberSheet> createState() => _AddFamilyMemberSheetState();
}

class _AddFamilyMemberSheetState extends State<AddFamilyMemberSheet> {
  static const _relationOptions = [
    'Spouse',
    'Husband',
    'Wife',
    'Son',
    'Daughter',
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Grandfather',
    'Grandmother',
    'Grandson',
    'Granddaughter',
    'Father-in-law',
    'Mother-in-law',
    'Son-in-law',
    'Daughter-in-law',
    'Brother-in-law',
    'Sister-in-law',
    'Uncle',
    'Aunt',
    'Nephew',
    'Niece',
    'Cousin',
    'Friend',
    'Other',
  ];

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _relationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _relationController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final relationStr = _relationController.text.trim();
    final relationLower = relationStr.toLowerCase();
    final isFemale = [
      'wife',
      'daughter',
      'mother',
      'sister',
      'grandmother',
      'aunt',
      'niece',
      'mother-in-law',
      'daughter-in-law',
      'sister-in-law',
      'granddaughter'
    ].contains(relationLower);
    final gender = isFemale ? 'Female' : 'Male';

    Navigator.pop(
      context,
      FamilyMember(
        id: 'f${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        age: age,
        relation: relationStr,
        gender: gender,
      ),
    );
  }

  Iterable<String> _relationSuggestions(String query) {
    if (query.trim().isEmpty) return _relationOptions;
    final lower = query.toLowerCase();
    return _relationOptions.where((r) => r.toLowerCase().contains(lower));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surfaceOf(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      content: scrollableDialogContent(
        context: context,
        child: SizedBox(
          width: 280,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add family member',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: RequiredFieldLabels.decorate(
                    const InputDecoration(),
                    'Full name',
                    isRequired: true,
                  ),
                  validator: FormValidators.fullName,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: RequiredFieldLabels.decorate(
                    const InputDecoration(),
                    'Age',
                    isRequired: true,
                  ),
                  validator: FormValidators.age,
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (value) => _relationSuggestions(value.text),
                  onSelected: (selection) =>
                      _relationController.text = selection,
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 180, maxWidth: 280),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(option,
                                    style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodyMedium)),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: RequiredFieldLabels.decorate(
                        const InputDecoration(
                          hintText: 'Select or type',
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        'Relation',
                        isRequired: true,
                      ),
                      validator: (v) =>
                          FormValidators.tagText(v, field: 'Relation'),
                      onChanged: (v) => _relationController.text = v,
                      onFieldSubmitted: (_) => onFieldSubmitted(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              minimumSize: const Size(0, 48),
            ),
            child: const Text('Add member'),
          ),
        ),
      ],
    );
  }
}
