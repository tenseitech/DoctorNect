import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/media/gallery_image_picker.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/constants/world_locations.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../../../../widgets/required_field_label.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/section_save_bar.dart';
import '../../../../core/theme/app_typography.dart';

class ClinicInfoSection extends StatefulWidget {
  const ClinicInfoSection({super.key});

  @override
  State<ClinicInfoSection> createState() => _ClinicInfoSectionState();
}

class _ClinicInfoSectionState extends State<ClinicInfoSection> {
  static const _presetClinicTypes = [
    'Private Clinic',
    'Hospital',
    'Polyclinic',
    'Nursing Home',
    'Eye Clinic',
    'Dental Clinic',
    'Skin & Cosmetic Clinic',
    'Maternity / Gynae Clinic',
    'Paediatric Clinic',
    'Orthopaedic Clinic',
    'Diagnostic Centre',
    'Day Care Centre',
    'Charitable / NGO Clinic',
    'Government Dispensary',
    'Teleclinic / Online Only',
  ];

  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: _p.clinicName);
  late bool _manualTypeMode = _initialManualTypeMode();
  late String _selectedType = _initialSelectedType();
  late final _customType = TextEditingController(text: _initialCustomType());
  late final _line1 = TextEditingController(text: _p.addressLine1);
  late final _line2 = TextEditingController(text: _p.addressLine2);
  late String? _country = _initialCountry();
  late String? _state = _initialState();
  late String? _city = _initialCity();
  late final _pincode = TextEditingController(text: _p.pincode);
  late final _landmark = TextEditingController(text: _p.landmark);
  late final _maps = TextEditingController(text: _p.mapsLink);
  late final List<String> _photos = List<String>.from(_p.clinicPhotoNames);
  bool _dirty = false;
  bool _fetchingLocation = false;

  DoctorProfileData get _p => DoctorProfileStore.instance.profile;

  Future<void> _fetchCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      final result = await LocationService.getCurrentLocation(
        context: context,
        showToast: false,
      );

      if (result != null && mounted) {
        setState(() {
          if (result.addressLine1 != null && result.addressLine1!.isNotEmpty) {
            _line1.text = result.addressLine1!;
          }
          if (result.country != null && result.country!.isNotEmpty) {
            _country = result.country;
          }
          if (result.state != null && result.state!.isNotEmpty) {
            _state = result.state;
          }
          if (result.city != null && result.city!.isNotEmpty) {
            _city = result.city;
          }
          if (result.pincode != null && result.pincode!.isNotEmpty) {
            _pincode.text = result.pincode!;
          }
          _maps.text = result.mapsUrl ??
              'https://www.google.com/maps/search/?api=1&query=${result.latitude},${result.longitude}';
          _dirty = true;
        });
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  bool _initialManualTypeMode() {
    final saved = _p.clinicType.trim();
    if (saved.isEmpty) return false;
    return !_presetClinicTypes.contains(saved);
  }

  String _initialSelectedType() {
    final saved = _p.clinicType.trim();
    if (_presetClinicTypes.contains(saved)) return saved;
    return _presetClinicTypes.first;
  }

  String _initialCustomType() {
    final saved = _p.clinicType.trim();
    if (saved.isEmpty || _presetClinicTypes.contains(saved)) return '';
    return saved;
  }

  String? _initialCountry() {
    final saved = _p.country.trim();
    if (saved.isEmpty) return Countries.defaultCountry;
    return saved;
  }

  String? _initialState() {
    final saved = _p.state.trim();
    if (saved.isEmpty) return null;
    final country = _initialCountry();
    if (country == null || !WorldLocations.hasData(country)) return null;
    return saved;
  }

  String? _initialCity() {
    final saved = _p.city.trim();
    if (saved.isEmpty) return null;
    return saved;
  }

  bool get _hasLocationData =>
      _country != null && WorldLocations.hasData(_country!);

  List<String> get _countryOptions {
    final current = _country?.trim();
    if (current != null &&
        current.isNotEmpty &&
        !Countries.all.contains(current)) {
      return [current, ...Countries.all];
    }
    return Countries.all;
  }

  List<String> get _stateOptions {
    if (_country == null) return const [];
    return WorldLocations.statesWithLegacy(_country!, _state);
  }

  List<String> get _cityOptions {
    if (_country == null || _state == null || _state!.trim().isEmpty)
      return const [];
    return WorldLocations.citiesWithLegacy(_country!, _state!, _city);
  }

  String? _validatePostal(String? value) {
    final label =
        WorldLocations.postalCodeLabel(_country ?? Countries.defaultCountry);
    final err = FormValidators.required(value, field: label);
    if (err != null) return err;
    if ((_country ?? Countries.defaultCountry) == Countries.defaultCountry) {
      return FormValidators.pincodeIndia(value);
    }
    return null;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 5) return;
    final picked = await GalleryImagePicker.pickSingle();
    if (picked != null) {
      setState(() => _photos.add(picked.name));
      _markDirty();
    }
  }

  Future<void> _deletePhoto(String photo) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete photo?',
      message: 'Remove this clinic photo?',
    );
    if (!confirmed || !mounted) return;
    setState(() => _photos.remove(photo));
    _markDirty();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _p.clinicName = _name.text.trim();
    _p.clinicType = _manualTypeMode ? _customType.text.trim() : _selectedType;
    _p.addressLine1 = _line1.text.trim();
    _p.addressLine2 = _line2.text.trim();
    _p.country = _country?.trim() ?? Countries.defaultCountry;
    _p.state = _state?.trim() ?? '';
    _p.city = _city?.trim() ?? '';
    _p.pincode = _pincode.text.trim();
    _p.landmark = _landmark.text.trim();
    _p.mapsLink = _maps.text.trim();
    _p.clinicPhotoNames = List<String>.from(_photos);

    // FIXED: await Firestore write; only show success / pop on confirmed save.
    try {
      await DoctorProfileStore.instance.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      AppToast.info(context,
          'Could not save changes. Please check your connection and try again.');
      return;
    }
    if (!mounted) return; // FIXED: mounted check after await
    setState(() => _dirty = false);
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _name.dispose();
    _customType.dispose();
    _line1.dispose();
    _line2.dispose();
    _pincode.dispose();
    _landmark.dispose();
    _maps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postalLabel =
        WorldLocations.postalCodeLabel(_country ?? Countries.defaultCountry);

    return Scaffold(
      appBar: AppBar(title: const Text('Clinic Information')),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: _name,
                              decoration: RequiredFieldLabels.decorate(
                                const InputDecoration(),
                                'Clinic name',
                                isRequired: true,
                              ),
                              validator: (v) => FormValidators.required(v,
                                  field: 'Clinic name'),
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Clinic type',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _ClinicTypeModeChip(
                                  label: 'Select from list',
                                  selected: !_manualTypeMode,
                                  onTap: () {
                                    if (_manualTypeMode) {
                                      setState(() => _manualTypeMode = false);
                                      _markDirty();
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                _ClinicTypeModeChip(
                                  label: 'Enter manually',
                                  selected: _manualTypeMode,
                                  onTap: () {
                                    if (!_manualTypeMode) {
                                      setState(() => _manualTypeMode = true);
                                      _markDirty();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_manualTypeMode)
                              TextFormField(
                                controller: _customType,
                                decoration: RequiredFieldLabels.decorate(
                                  const InputDecoration(
                                    hintText: 'e.g. Sports Medicine Clinic',
                                    prefixIcon:
                                        Icon(Icons.edit_outlined, size: 18),
                                  ),
                                  'Enter clinic type',
                                  isRequired: true,
                                ),
                                validator: (v) => FormValidators.required(v,
                                    field: 'Clinic type'),
                                onChanged: (_) => _markDirty(),
                              )
                            else
                              DropdownButtonFormField<String>(
                                initialValue:
                                    _presetClinicTypes.contains(_selectedType)
                                        ? _selectedType
                                        : _presetClinicTypes.first,
                                isExpanded: true,
                                decoration: RequiredFieldLabels.decorate(
                                  const InputDecoration(),
                                  'Clinic type',
                                  isRequired: true,
                                ),
                                items: _presetClinicTypes
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t,
                                              overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                validator: (v) => FormValidators.dropdown(v,
                                    field: 'Clinic type'),
                                onChanged: (v) {
                                  setState(() => _selectedType = v!);
                                  _markDirty();
                                },
                              ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Clinic address',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                TextButton.icon(
                                  onPressed: _fetchingLocation
                                      ? null
                                      : _fetchCurrentLocation,
                                  icon: _fetchingLocation
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.doctorBlue),
                                        )
                                      : const Icon(Icons.my_location,
                                          size: 16,
                                          color: AppColors.doctorBlue),
                                  label: Text(
                                    _fetchingLocation
                                        ? 'Detecting...'
                                        : 'Use current location',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.doctorBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _line1,
                              decoration: RequiredFieldLabels.decorate(
                                const InputDecoration(),
                                'Address line 1',
                                isRequired: true,
                              ),
                              validator: (v) => FormValidators.required(v,
                                  field: 'Address line 1'),
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _line2,
                              decoration: const InputDecoration(
                                  labelText: 'Address line 2 (optional)'),
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _country != null &&
                                      _countryOptions.contains(_country)
                                  ? _country
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Country (optional)'),
                              hint: const Text('Select country'),
                              items: _countryOptions
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  _country = v;
                                  _state = null;
                                  _city = null;
                                });
                                _markDirty();
                              },
                            ),
                            const SizedBox(height: 12),
                            if (_hasLocationData) ...[
                              DropdownButtonFormField<String>(
                                key: ValueKey('state-$_country'),
                                initialValue: _state != null &&
                                        _stateOptions.contains(_state)
                                    ? _state
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'State / Province (optional)'),
                                hint: const Text('Select state / province'),
                                items: _stateOptions
                                    .map((s) => DropdownMenuItem(
                                        value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) {
                                  setState(() {
                                    _state = v;
                                    _city = null;
                                  });
                                  _markDirty();
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey('city-$_country-$_state'),
                                initialValue: _city != null &&
                                        _cityOptions.contains(_city)
                                    ? _city
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'City (optional)'),
                                hint: Text(_state == null
                                    ? 'Select state first'
                                    : 'Select city'),
                                items: _cityOptions
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: _state == null
                                    ? null
                                    : (v) {
                                        setState(() => _city = v);
                                        _markDirty();
                                      },
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _pincode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(
                                  (_country ?? Countries.defaultCountry) ==
                                          Countries.defaultCountry
                                      ? 6
                                      : 10,
                                ),
                              ],
                              decoration: RequiredFieldLabels.decorate(
                                const InputDecoration(),
                                postalLabel,
                                isRequired: true,
                              ),
                              validator: _validatePostal,
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _landmark,
                              decoration: const InputDecoration(
                                  labelText: 'Landmark (optional)'),
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _maps,
                              decoration: const InputDecoration(
                                  labelText: 'Google Maps link (optional)'),
                              onChanged: (_) => _markDirty(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                    'Clinic photos (${_photos.length}/5) — optional',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                FilledButton.icon(
                                  onPressed:
                                      _photos.length < 5 ? _addPhoto : null,
                                  icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 18),
                                  label: const Text('Add'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.doctorBlue,
                                    foregroundColor: AppColors.white,
                                  ),
                                ),
                              ],
                            ),
                            ..._photos.map((p) => ListTile(
                                  leading: const Icon(Icons.image_outlined,
                                      color: AppColors.doctorBlue),
                                  title: Text(p,
                                      style: const TextStyle(
                                          fontSize: AppTypography.bodySmall)),
                                  trailing: LabeledRemoveButton(
                                    label: 'Delete',
                                    onPressed: () => _deletePhoto(p),
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

class _ClinicTypeModeChip extends StatelessWidget {
  const _ClinicTypeModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.doctorBlue;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w500,
            color:
                selected ? AppColors.surfaceOf(context) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
