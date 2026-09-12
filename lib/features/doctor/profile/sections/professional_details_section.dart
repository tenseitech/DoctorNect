import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../widgets/labeled_add_button.dart';
import '../../../../widgets/qualification_selector.dart';
import '../../../../widgets/specialization_selector.dart';
import '../../../../widgets/required_field_label.dart';

import '../../../../core/constants/indian_states.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/session/doctor_session.dart'; // FIXED: doctor id for Firestore persist
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/profile_widgets.dart';
import '../widgets/section_save_bar.dart';

class ProfessionalDetailsSection extends StatefulWidget {
  const ProfessionalDetailsSection({super.key});

  @override
  State<ProfessionalDetailsSection> createState() => _ProfessionalDetailsSectionState();
}

class _ProfessionalDetailsSectionState extends State<ProfessionalDetailsSection> {
  final _formKey = GlobalKey<FormState>();

  late String _specialization = AppConstants.normalizeSpecialization(_p.specialization);
  late String _qualification = _p.qualification.trim();
  late final List<String> _superSpecs = _p.superSpecialization.trim().isEmpty
      ? []
      : _p.superSpecialization.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final _superSpecInput = TextEditingController();
  late final _councilNumber = TextEditingController(text: _p.councilNumber);
  late bool _councilEditable = _p.councilNumber.trim().isEmpty;
  late String? _stateCouncil = _p.stateCouncil.trim().isEmpty ? null : _p.stateCouncil.trim();
  late bool _stateCouncilEditable = _p.stateCouncil.trim().isEmpty;
  late final _awards = TextEditingController(text: _p.awards);
  late final List<String> _certs = List<String>.from(_p.certifications);
  late final List<String> _pubs = List<String>.from(_p.publications);
  late final bool _consultsAdultsOnly = _p.consultsAdultsOnly;
  final _certInput = TextEditingController();
  final _pubInput = TextEditingController();
  bool _dirty = false;

  DoctorProfileData get _p => DoctorProfileStore.instance.profile;

  static int get _currentYear => DateTime.now().year;

  int? _initialRegistrationYear() {
    if (_p.registrationYear > 0) return _p.registrationYear;
    if (_p.yearsExperience > 0) return _currentYear - _p.yearsExperience;
    return null;
  }

  int get _displayRegistrationYear => _initialRegistrationYear() ?? 0;

  int get _computedExperience {
    final year = _displayRegistrationYear;
    if (year <= 0) return _p.yearsExperience;
    return (_currentYear - year).clamp(0, 60);
  }

  List<String> get _stateOptions {
    final current = _stateCouncil?.trim();
    if (current != null && current.isNotEmpty && !IndianStates.all.contains(current)) {
      return [current, ...IndianStates.all];
    }
    return IndianStates.all;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _p.specialization = _specialization;
    _p.qualification = _qualification.trim();
    _p.superSpecialization = _superSpecs.join(', ');
    final councilWasEditable = _councilEditable;
    _p.councilNumber = _councilNumber.text.trim();
    _p.stateCouncil = _stateCouncil!.trim();
    _p.awards = _awards.text.trim();
    _p.certifications = List<String>.from(_certs);
    _p.publications = List<String>.from(_pubs);
    _p.consultsAdultsOnly = _consultsAdultsOnly;

    // FIXED: await Firestore write; only show success / pop on confirmed save.
    try {
      await DoctorProfileStore.instance.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      AppToast.info(context, 'Could not save changes. Please check your connection and try again.');
      return;
    }
    if (councilWasEditable && _councilNumber.text.trim().isNotEmpty) {
      _councilEditable = false; // FIXED: lock council number only after a confirmed save
    }
    if (_stateCouncil != null && _stateCouncil!.trim().isNotEmpty) {
      _stateCouncilEditable = false; // Lock state council after confirmed save
    }
    if (!mounted) return; // FIXED: mounted check after await
    setState(() => _dirty = false);
    showProfileSavedToast(context);
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _superSpecInput.dispose();
    _councilNumber.dispose();
    _awards.dispose();
    _certInput.dispose();
    _pubInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Professional Details')),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                SpecializationSelector(
                  initialValue: _specialization,
                  onChanged: (v) {
                    _specialization = v ?? '';
                    _markDirty();
                  },
                  isRequired: true,
                  accentColor: AppColors.doctorBlue,
                ),
                const SizedBox(height: 12),
                QualificationSelector(
                  initialValue: _qualification,
                  onChanged: (v) {
                    _qualification = v ?? '';
                    _markDirty();
                  },
                  isRequired: true,
                  accentColor: AppColors.doctorBlue,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Autocomplete<String>(
                        optionsBuilder: (TextEditingValue tv) {
                          if (tv.text.isEmpty) return AppConstants.specializations;
                          return AppConstants.specializations.where(
                            (s) => s.toLowerCase().contains(tv.text.toLowerCase()),
                          );
                        },
                        onSelected: (String selection) {
                          _superSpecInput.text = selection;
                          _markDirty();
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          controller.addListener(() {
                            if (controller.text != _superSpecInput.text) {
                              _superSpecInput.text = controller.text;
                            }
                          });
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(labelText: 'Super-specialization'),
                          );
                        },
                      ),
                    ),
                    LabeledAddButton(
                      label: '+ Add',
                      onPressed: () {
                        final val = _superSpecInput.text.trim();
                        if (val.isEmpty) return;
                        if (_superSpecs.contains(val)) return;
                        setState(() {
                          _superSpecs.add(val);
                          _superSpecInput.clear();
                        });
                        _markDirty();
                      },
                    ),
                  ],
                ),
                ..._superSpecs.map((s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFDC2626)),
                        onPressed: () {
                          setState(() => _superSpecs.remove(s));
                          _markDirty();
                        },
                      ),
                    )),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _councilNumber,
                  readOnly: !_councilEditable,
                  decoration: RequiredFieldLabels.decorate(
                    InputDecoration(
                      filled: !_councilEditable,
                      fillColor: _councilEditable ? null : AppColors.cardBgOf(context),
                      suffixIcon: !_councilEditable
                          ? Tooltip(
                              message: 'Confidential credential — registration number cannot be modified',
                              child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondaryOf(context)),
                            )
                          : null,
                      helperText: 'Confidential detail — set once during registration / setup',
                    ),
                    'Medical council reg. number',
                    isRequired: true,
                  ),
                  onChanged: (_) => _markDirty(),
                  validator: FormValidators.councilNumber,
                ),
                SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  initialValue: _displayRegistrationYear > 0
                      ? '$_displayRegistrationYear'
                      : 'Not set',
                  decoration: RequiredFieldLabels.decorate(
                    InputDecoration(
                      filled: true,
                      fillColor: AppColors.cardBgOf(context),
                      suffixIcon: Tooltip(
                        message: 'Registration year can only be updated by DoctorNect support',
                        child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondaryOf(context)),
                      ),
                      helperText: 'Contact support if this needs to be corrected',
                    ),
                    'Registration year',
                    isRequired: false,
                  ),
                ),
                SizedBox(height: 12),
                TextFormField(
                  readOnly: true,
                  initialValue: _displayRegistrationYear <= 0 && _p.yearsExperience <= 0
                      ? '—'
                      : '$_computedExperience year${_computedExperience == 1 ? '' : 's'}',
                  decoration: InputDecoration(
                    labelText: 'Years of experience',
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                    suffixIcon: Tooltip(
                      message: 'Calculated from registration year',
                      child: Icon(Icons.info_outline, size: 18, color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _stateCouncil != null && _stateOptions.contains(_stateCouncil)
                      ? _stateCouncil
                      : null,
                  decoration: RequiredFieldLabels.decorate(
                    InputDecoration(
                      filled: !_stateCouncilEditable,
                      fillColor: _stateCouncilEditable ? null : AppColors.cardBgOf(context),
                      suffixIcon: !_stateCouncilEditable
                          ? Tooltip(
                              message: 'Confidential credential — state medical council cannot be modified',
                              child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondaryOf(context)),
                            )
                          : null,
                      helperText: 'Confidential detail — state medical council is unchanged once set',
                    ),
                    'State medical council',
                    isRequired: true,
                  ),
                  isExpanded: true,
                  hint: const Text('Select state'),
                  items: _stateOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  validator: (v) => FormValidators.dropdown(v, field: 'state medical council'),
                  onChanged: _stateCouncilEditable
                      ? (v) {
                          setState(() => _stateCouncil = v);
                          _markDirty();
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                Text('Additional certifications', style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _certInput,
                        decoration: const InputDecoration(hintText: 'Add certification'),
                      ),
                    ),
                    LabeledAddButton(
                      label: '+ Add',
                      onPressed: () {
                        if (_certInput.text.trim().isEmpty) return;
                        setState(() {
                          _certs.add(_certInput.text.trim());
                          _certInput.clear();
                        });
                        _markDirty();
                      },
                    ),
                  ],
                ),
                ..._certs.map((c) => ListTile(
                      title: Text(c),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFDC2626)),
                        onPressed: () {
                          setState(() => _certs.remove(c));
                          _markDirty();
                        },
                      ),
                    )),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _awards,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Awards & recognitions', alignLabelWithHint: true),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),
                Text('Publications', style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pubInput,
                        decoration: const InputDecoration(hintText: 'Add link'),
                      ),
                    ),
                    LabeledAddButton(
                      label: '+ Add',
                      onPressed: () {
                        if (_pubInput.text.trim().isEmpty) return;
                        setState(() {
                          _pubs.add(_pubInput.text.trim());
                          _pubInput.clear();
                        });
                        _markDirty();
                      },
                    ),
                  ],
                ),
                ..._pubs.map((p) => ListTile(
                      title: Text(p, style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFDC2626)),
                        onPressed: () {
                          setState(() => _pubs.remove(p));
                          _markDirty();
                        },
                      ),
                    )),
                        ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SectionSaveBar(visible: _dirty, onSave: _save),
        ],
      ),
    );
  }
}
