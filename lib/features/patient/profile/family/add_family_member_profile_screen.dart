import '../../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/media/gallery_image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../data/patient_profile_mock.dart';
import '../models/patient_profile_models.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../widgets/profile_edit_widgets.dart';
import '../widgets/tag_input_field.dart';

class AddFamilyMemberProfileScreen extends StatefulWidget {
  const AddFamilyMemberProfileScreen({super.key, this.existingMember});

  final FamilyProfileMember? existingMember;

  @override
  State<AddFamilyMemberProfileScreen> createState() => _AddFamilyMemberProfileScreenState();
}

class _AddFamilyMemberProfileScreenState extends State<AddFamilyMemberProfileScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  FamilyRelation _relation = FamilyRelation.spouse;
  DateTime? _dob;
  String _gender = 'Male';
  String _bloodGroup = 'O+';
  bool _insurance = false;
  final List<String> _allergies = [];
  final List<String> _conditions = [];
  String? _photoName;

  bool get _isEditing => widget.existingMember != null;

  int get _age {
    if (_dob == null) return 0;
    final now = DateTime.now();
    var age = now.year - _dob!.year;
    if (now.month < _dob!.month || (now.month == _dob!.month && now.day < _dob!.day)) age--;
    return age;
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingMember != null) {
      final m = widget.existingMember!;
      _nameController.text = m.name;
      _relation = m.relation;
      _dob = m.dateOfBirth;
      _gender = m.gender;
      _bloodGroup = m.bloodGroup;
      _insurance = m.insuranceCovered;
      _allergies.addAll(m.allergies);
      _conditions.addAll(m.conditions);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickPhoto() async {
    final picked = await GalleryImagePicker.pickSingle();
    if (picked != null) setState(() => _photoName = picked.name);
  }

  bool _saving = false;
  bool _removing = false;

  Future<void> _removeMember() async {
    final member = widget.existingMember;
    if (member == null || _removing) return;

    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Remove family member?',
      message: 'Remove ${member.name} from your family profiles?',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _removing = true);
    try {
      await PatientProfileMock.removeFamilyMember(member.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not remove family member. Try again.');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _dob == null) {
      AppToast.info(context, 'Please select date of birth');
      return;
    }
    if (_age < 0 || _age > 120) {
      AppToast.info(context, 'Age must be between 0 and 120');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final isEditing = widget.existingMember != null;
    final memberId = isEditing ? widget.existingMember!.id : 'fm${DateTime.now().millisecondsSinceEpoch}';

    final member = FamilyProfileMember(
      id: memberId,
      name: _isEditing ? widget.existingMember!.name : _nameController.text.trim(),
      relation: _relation,
      age: _age,
      gender: _isEditing ? widget.existingMember!.gender : _gender,
      bloodGroup: _isEditing ? widget.existingMember!.bloodGroup : _bloodGroup,
      allergies: List.from(_allergies),
      conditions: List.from(_conditions),
      insuranceCovered: _insurance,
      dateOfBirth: _dob,
      photoInitial: _nameController.text.trim().isNotEmpty ? _nameController.text.trim()[0] : 'F',
    );

    try {
      if (isEditing) {
        await PatientProfileMock.updateFamilyMember(member);
      } else {
        await PatientProfileMock.addFamilyMember(member);
      }
      if (!mounted) return;
      Navigator.pop(context, member);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not save family member. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _relationLabel(FamilyRelation relation) => switch (relation) {
        FamilyRelation.spouse => 'Spouse',
        FamilyRelation.child => 'Child',
        FamilyRelation.parent => 'Parent',
        FamilyRelation.sibling => 'Sibling',
        FamilyRelation.friend => 'Friend',
        FamilyRelation.other => 'Other',
      };

  String get _heroName {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name;
    if (_isEditing) return widget.existingMember!.name;
    return 'New member';
  }

  String get _heroInitial {
    final name = _heroName;
    return name.isNotEmpty ? name[0].toUpperCase() : 'F';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar(
        _isEditing ? 'Edit Family Member' : 'Add Family Member',
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: PatientProfileFormStyles.constrainedScrollBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ProfileEditWidgets.heroHeader(
                        initial: _photoName != null ? '✓' : _heroInitial,
                        name: _heroName,
                        subtitle: _isEditing
                            ? '${_relationLabel(_relation)} · $_age yrs'
                            : 'Add a family member for bookings',
                        onPhotoTap: _pickPhoto,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.badge_outlined,
                      title: 'Personal details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isEditing) ...[
                            ProfileEditWidgets.lockedNote(
                              message: 'Name, gender, and blood group are locked after adding a member.',
                            ),
                            const SizedBox(height: 14),
                            ProfileEditWidgets.lockedField(
                              label: 'Full name',
                              value: widget.existingMember!.name,
                            ),
                          ] else
                            TextFormField(
                              controller: _nameController,
                              onChanged: (_) => setState(() {}),
                              decoration: PatientProfileFormStyles.fieldDecoration(context, 
                                labelText: 'Full name',
                                isRequired: true,
                              ),
                              validator: FormValidators.fullName,
                            ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<FamilyRelation>(
                            initialValue: _relation,
                            isExpanded: true,
                            decoration: PatientProfileFormStyles.fieldDecoration(context, 
                              labelText: 'Relation',
                              isRequired: true,
                            ),
                            items: FamilyRelation.values
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(_relationLabel(r)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _relation = v!),
                          ),
                          const SizedBox(height: 12),
                          PatientProfileFormStyles.dobPickerRow(
          context: context,
                            label: 'Date of birth',
                            valueText: _dob == null
                                ? 'Select date'
                                : '${_dob!.day}/${_dob!.month}/${_dob!.year} · Age $_age',
                            onTap: _pickDob,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.favorite_outline_rounded,
                      title: 'Health info',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isEditing)
                            ProfileEditWidgets.lockedField(
                              label: 'Gender',
                              value: widget.existingMember!.gender,
                            )
                          else
                            ProfileEditWidgets.genderChips(
                              selected: _gender,
                              onSelected: (g) => setState(() => _gender = g),
                            ),
                          const SizedBox(height: 14),
                          if (_isEditing)
                            ProfileEditWidgets.lockedField(
                              label: 'Blood group',
                              value: widget.existingMember!.bloodGroup,
                            )
                          else
                            ProfileEditWidgets.bloodGroupChips(
                              selected: _bloodGroup,
                              onSelected: (g) => setState(() => _bloodGroup = g),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.medical_information_outlined,
                      title: 'Medical notes',
                      subtitle: 'Helps doctors during appointments',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TagInputField(
                            label: 'allergy',
                            tags: _allergies,
                            onAdd: (t) => setState(() => _allergies.add(t)),
                            onRemove: (t) => setState(() => _allergies.remove(t)),
                          ),
                          const SizedBox(height: 16),
                          TagInputField(
                            label: 'condition',
                            tags: _conditions,
                            onAdd: (t) => setState(() => _conditions.add(t)),
                            onRemove: (t) => setState(() => _conditions.remove(t)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Insurance',
                      child: ProfileEditWidgets.insuranceToggle(
                        value: _insurance,
                        onChanged: (v) => setState(() => _insurance = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isEditing)
              PatientProfileFormStyles.bottomDestructiveButton(
                label: 'Remove member',
                onPressed: (_saving || _removing) ? null : _removeMember,
              ),
            PatientProfileFormStyles.bottomSaveButton(
              onPressed: _save,
              label: _isEditing ? 'Save Changes' : 'Add Member',
              enabled: !_saving && !_removing,
            ),
          ],
        ),
      ),
    );
  }
}
