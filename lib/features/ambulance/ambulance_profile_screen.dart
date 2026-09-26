import '../../core/firebase/firestore_service.dart';
import '../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/contact_change_otp_service.dart';
import '../../core/auth/contact_change_verification.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/legal/medibond_legal_content.dart';
import '../../core/auth/profile_completion_service.dart';
import '../../core/enums/user_type.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/phone_number_field.dart';
import '../patient/profile/about/about_screen.dart';
import '../auth/widgets/registration_address_section.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_models.dart';
import 'widgets/ambulance_availability_toggle.dart';
import 'widgets/ambulance_page_layout.dart';
import 'widgets/ambulance_service_form_fields.dart';
import '../promoted_ads/screens/promoted_ads_management_screen.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';
import '../../widgets/verification_submission_card.dart';
import '../../core/theme/app_typography.dart';

class AmbulanceProfileScreen extends StatefulWidget {
  const AmbulanceProfileScreen({
    super.key,
    required this.ambulanceId,
    this.embedded = false,
    this.onLogout,
  });

  final String ambulanceId;
  final bool embedded;
  final VoidCallback? onLogout;

  @override
  State<AmbulanceProfileScreen> createState() => _AmbulanceProfileScreenState();
}

class _AmbulanceProfileScreenState extends State<AmbulanceProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;

  RegisteredAmbulance? _ambulance;

  final _serviceNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();
  final _areasCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  final _address1Ctrl = TextEditingController();
  final _address2Ctrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  String? _country;
  String? _state;
  String? _city;

  AmbulanceType _ambulanceType = AmbulanceType.bls;
  bool _hasOxygen = false;
  bool _hasVentilator = false;
  bool _hasStretcher = true;
  bool _is24x7 = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadProfile());
    });
  }

  @override
  void dispose() {
    _serviceNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _driverNameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleCtrl.dispose();
    _areasCtrl.dispose();
    _licenseCtrl.dispose();
    _insuranceCtrl.dispose();
    _rateCtrl.dispose();
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final cached = AmbulanceStore.instance.findAmbulance(widget.ambulanceId);
      final fresh = await FirestoreService.instance.ambulance
          .fetchAmbulanceById(widget.ambulanceId);
      if (!mounted) return;
      _applyAmbulance(fresh ?? cached);
    } catch (_) {
      if (!mounted) return;
      _applyAmbulance(
          AmbulanceStore.instance.findAmbulance(widget.ambulanceId));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyAmbulance(RegisteredAmbulance? amb) {
    _ambulance = amb;
    if (amb == null) return;

    _serviceNameCtrl.text = amb.serviceName;
    _ownerNameCtrl.text = amb.ownerName;
    _driverNameCtrl.text = amb.driverName;
    final parsedPhone = FormValidators.parsePhone(amb.phone);
    _phoneDialCode = parsedPhone.dialCode;
    _phoneCtrl.text = parsedPhone.localNumber;
    _vehicleCtrl.text = amb.vehicleNumber;
    _areasCtrl.text = amb.serviceAreas.join(', ');
    _licenseCtrl.text = amb.licenseNumber;
    _insuranceCtrl.text = amb.insuranceNumber;
    _rateCtrl.text = amb.ratePerKm?.toString() ?? '';
    _ambulanceType = amb.ambulanceType;
    _hasOxygen = amb.hasOxygen;
    _hasVentilator = amb.hasVentilator;
    _hasStretcher = amb.hasStretcher;
    _is24x7 = amb.is24x7;

    _address1Ctrl.text = amb.addressLine1;
    _address2Ctrl.text = amb.addressLine2;
    _pincodeCtrl.text = amb.pincode;
    _country = amb.country.isNotEmpty ? amb.country : null;
    _state = amb.state.isNotEmpty ? amb.state : null;
    _city = amb.city.isNotEmpty ? amb.city : null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final current = _ambulance;
    if (current == null) return;

    if (_city == null ||
        _state == null ||
        _country == null ||
        _address1Ctrl.text.trim().isEmpty ||
        _pincodeCtrl.text.trim().isEmpty) {
      AppToast.info(context, 'Please fill all required address fields');
      return;
    }

    final newPhone =
        FormValidators.formatFullPhone(_phoneDialCode, _phoneCtrl.text.trim());
    if (!ContactChangeVerification.mobilesEqual(newPhone, current.phone)) {
      final phoneErr = FormValidators.phoneLocal(_phoneCtrl.text.trim(),
          dialCode: _phoneDialCode);
      if (phoneErr != null) {
        AppToast.info(context, phoneErr);
        return;
      }

      final verified = await ContactChangeVerification.verifyIfNeeded(
        context: context,
        channel: ContactVerificationChannel.mobile,
        destination: newPhone,
        purpose: 'verify your new driver mobile number',
        verifiedCanonical: null,
        accentColor: const Color(0xFFDC2626),
      );
      if (!mounted) return;
      if (!verified) {
        AppToast.info(
            context, 'Verify your new mobile number with OTP before saving.');
        return;
      }
    }

    setState(() => _saving = true);

    final areas = _areasCtrl.text
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final updated = current.copyWith(
      serviceName: _serviceNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      driverName: _driverNameCtrl.text.trim(),
      phone: FormValidators.formatFullPhone(
          _phoneDialCode, _phoneCtrl.text.trim()),
      vehicleNumber: FormValidators.normalizeVehicleNumber(_vehicleCtrl.text),
      ambulanceType: _ambulanceType,
      city: _city!,
      serviceAreas: areas,
      licenseNumber: _licenseCtrl.text.trim(),
      insuranceNumber: _insuranceCtrl.text.trim(),
      hasOxygen: _hasOxygen,
      hasVentilator: _hasVentilator,
      hasStretcher: _hasStretcher,
      is24x7: _is24x7,
      ratePerKm: double.tryParse(_rateCtrl.text.trim()),
      addressLine1: _address1Ctrl.text.trim(),
      addressLine2: _address2Ctrl.text.trim(),
      country: _country!,
      state: _state!,
      pincode: _pincodeCtrl.text.trim(),
    );

    final ok = await FirestoreService.instance.ambulance
        .updateAmbulanceProfile(updated);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _saving = false;
      if (ok) {
        _editing = false;
        _ambulance = updated;
      }
    });

    if (ok) {
      await AmbulanceSession.setAmbulance(
        id: updated.id,
        serviceName: updated.serviceName,
        driverName: updated.driverName,
      );
      unawaited(
        ProfileCompletionService.instance.evaluateAndMarkFromRoleDoc(
          role: UserType.ambulance,
          uid: '',
          profileId: updated.id,
        ),
      );
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Profile updated' : 'Could not save profile'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amb = _ambulance;
    final content = _loading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFFDC2626)))
        : amb == null
            ? Center(
                child: Text(
                  'Profile not found',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondaryOf(context)),
                ),
              )
            : Builder(
                builder: (context) {
                  final live = AmbulanceStore.instance
                          .findAmbulance(widget.ambulanceId) ??
                      amb;
                  return Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        if (widget.embedded) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Profile',
                                      style: GoogleFonts.inter(
                                          fontSize: AppTypography.headlineLarge,
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Service details, availability & account',
                                      style: GoogleFonts.inter(
                                          fontSize: AppTypography.bodySmall,
                                          color: AppColors.textSecondaryOf(
                                              context)),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_loading)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () {
                                          if (_editing) {
                                            _applyAmbulance(live);
                                          }
                                          setState(() => _editing = !_editing);
                                        },
                                  child: Text(
                                    _editing ? 'Cancel' : 'Edit',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          AmbulanceAvailabilityToggle(
                              ambulanceId: widget.ambulanceId),
                          const SizedBox(height: 16),
                        ],
                        _ProfileHeaderCard(ambulance: live),
                        const VerificationSubmissionCard(
                            role: UserType.ambulance),
                        const SizedBox(height: 16),
                        if (_editing) ...[
                          _buildEditForm(live),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _saving ? null : _saveProfile,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _saving
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.surfaceOf(context),
                                    ),
                                  )
                                : Text(
                                    'Save Profile',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ] else ...[
                          _ProfileSection(
                            title: 'Service',
                            children: [
                              _InfoRow('Service name', live.serviceName),
                              _InfoRow('Owner', live.ownerName),
                              _InfoRow('Username', live.username),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Driver & contact',
                            children: [
                              _InfoRow('Driver name', live.driverName),
                              _InfoRow('Phone', live.phone),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Vehicle',
                            children: [
                              _InfoRow('Vehicle number', live.vehicleNumber),
                              _InfoRow(
                                  'Ambulance type', live.ambulanceTypeLabel),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Location',
                            children: [
                              _InfoRow('City', live.city),
                              if (live.serviceAreas.isNotEmpty)
                                _InfoRow('Service areas',
                                    live.serviceAreas.join(', ')),
                              _InfoRow('Address',
                                  '${live.addressLine1}${live.addressLine2.isNotEmpty ? ', ${live.addressLine2}' : ''}\n${live.city}, ${live.state} - ${live.pincode}'),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Licensing',
                            children: [
                              _InfoRow('License', live.licenseNumber),
                              _InfoRow('Insurance', live.insuranceNumber),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Operations',
                            children: [
                              _InfoRow(
                                'Rate per km',
                                live.ratePerKm != null
                                    ? '₹${live.ratePerKm!.toStringAsFixed(0)}'
                                    : '—',
                              ),
                              _InfoRow(
                                'Equipment',
                                [
                                  if (live.hasOxygen) 'Oxygen',
                                  if (live.hasVentilator) 'Ventilator',
                                  if (live.hasStretcher) 'Stretcher',
                                  if (live.is24x7) '24×7',
                                ].join(' · ').ifEmpty('—'),
                              ),
                              _InfoRow('Status',
                                  live.available ? 'Online' : 'Offline'),
                            ],
                          ),
                          if (live.ratingCount > 0)
                            _ProfileSection(
                              title: 'Ratings',
                              children: [
                                _InfoRow(
                                  'Average rating',
                                  '${live.averageRating.toStringAsFixed(1)} / 5 (${live.ratingCount} reviews)',
                                ),
                              ],
                            ),
                          StreamBuilder<BannerConfigModel>(
                            stream: BannerConfigService.streamConfig(),
                            builder: (context, snapshot) {
                              final config = snapshot.data;
                              if (config != null && !config.enabled) {
                                return const SizedBox.shrink();
                              }

                              return _ProfileSection(
                                title: 'Advertising',
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.campaign_rounded,
                                        color: Color(0xFFDC2626)),
                                    title: Text(
                                      'Promote Banner Ad',
                                      style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: AppTypography.bodyMedium),
                                    ),
                                    subtitle: Text(
                                      'Advertise ambulance service on Patient Home',
                                      style: GoogleFonts.inter(
                                          fontSize: AppTypography.labelMedium,
                                          color: Colors.grey),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      const isVerified = true;
                                      PromotedAdsManagementScreen.open(
                                        context,
                                        providerType: 'ambulance',
                                        providerId: widget.ambulanceId,
                                        providerEmail: '',
                                        providerContact: live.phone,
                                        isVerified: isVerified,
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                          _AboutSection(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(
                                    accentColor: Color(0xFFDC2626),
                                    audience: LegalAudience.ambulance,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        if (widget.embedded && widget.onLogout != null) ...[
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: widget.onLogout,
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFDC2626)),
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              );

    if (widget.embedded) {
      return AmbulancePageLayout(child: content);
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        title: Text('My Profile',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        actions: [
          if (!_loading && amb != null)
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      if (_editing) {
                        _applyAmbulance(amb);
                      }
                      setState(() => _editing = !_editing);
                    },
              child: Text(
                _editing ? 'Cancel' : 'Edit',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(padding: const EdgeInsets.all(16), child: content),
        ),
      ),
    );
  }

  Widget _buildEditForm(RegisteredAmbulance amb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSection(
          title: 'Edit service',
          children: [
            _editField(_serviceNameCtrl, 'Service name',
                Icons.local_hospital_outlined),
            _editField(_ownerNameCtrl, 'Owner name', Icons.business_outlined),
          ],
        ),
        _ProfileSection(
          title: 'Edit driver',
          children: [
            _editField(_driverNameCtrl, 'Driver name', Icons.person_outline),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PhoneNumberField(
                controller: _phoneCtrl,
                initialDialCode: _phoneDialCode,
                onDialCodeChanged: (code) => _phoneDialCode = code,
                decoration: _inputDecoration('Phone', Icons.phone_outlined),
              ),
            ),
          ],
        ),
        _ProfileSection(
          title: 'Edit vehicle',
          children: [
            _editField(
              _vehicleCtrl,
              'Vehicle number',
              Icons.directions_car_outlined,
              inputFormatters: ambulanceVehicleNumberFormatters,
              capitalization: TextCapitalization.characters,
              validator: ambulanceVehicleNumberField,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<AmbulanceType>(
                initialValue: _ambulanceType,
                decoration: _inputDecoration(
                    'Ambulance type', Icons.medical_services_outlined),
                items: AmbulanceType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(_typeLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _ambulanceType = v);
                },
              ),
            ),
          ],
        ),
        _ProfileSection(
          title: 'Edit location',
          children: [
            RegistrationAddressSection(
              initialCountry: _country,
              initialState: _state,
              initialCity: _city,
              onCountryChanged: (v) => setState(() => _country = v),
              onStateChanged: (v) => setState(() => _state = v),
              onCityChanged: (v) => setState(() => _city = v),
              address1Controller: _address1Ctrl,
              address2Controller: _address2Ctrl,
              pinCodeController: _pincodeCtrl,
              accentColor: const Color(0xFFDC2626),
            ),
            const SizedBox(height: 12),
            _editField(
              _areasCtrl,
              'Service areas (comma separated)',
              Icons.map_outlined,
              maxLines: 2,
            ),
          ],
        ),
        _ProfileSection(
          title: 'Edit licensing',
          children: [
            _editField(
              _licenseCtrl,
              'License number',
              Icons.badge_outlined,
              validator: FormValidators.drivingLicense,
            ),
            _editField(
              _insuranceCtrl,
              'Insurance number',
              Icons.shield_outlined,
              validator: FormValidators.insuranceNumber,
            ),
          ],
        ),
        _ProfileSection(
          title: 'Edit operations',
          children: [
            _editField(
              _rateCtrl,
              'Rate per km (₹)',
              Icons.payments_outlined,
              keyboard: TextInputType.number,
            ),
            _EquipmentToggles(
              hasOxygen: _hasOxygen,
              hasVentilator: _hasVentilator,
              hasStretcher: _hasStretcher,
              is24x7: _is24x7,
              onOxygen: (v) => setState(() => _hasOxygen = v),
              onVentilator: (v) => setState(() => _hasVentilator = v),
              onStretcher: (v) => setState(() => _hasStretcher = v),
              on24x7: (v) => setState(() => _is24x7 = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Username: ${amb.username}',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.words,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        textCapitalization: capitalization,
        validator: validator ??
            (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        decoration: _inputDecoration(label, icon),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon:
          Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
      filled: true,
      fillColor: AppColors.surfaceOf(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
    );
  }

  String _typeLabel(AmbulanceType type) => switch (type) {
        AmbulanceType.bls => 'BLS (Basic)',
        AmbulanceType.als => 'ALS (Advanced)',
        AmbulanceType.icu => 'ICU',
        AmbulanceType.patientTransport => 'Patient Transport',
      };
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.ambulance});

  final RegisteredAmbulance ambulance;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFECACA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.local_hospital,
                  color: AppColors.surfaceOf(context), size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ambulance.serviceName,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ambulance.driverName,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  Text(
                    ambulance.vehicleNumber,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 12),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFFDC2626), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Rate the app, share link & legal',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textSecondaryOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 12),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentToggles extends StatelessWidget {
  const _EquipmentToggles({
    required this.hasOxygen,
    required this.hasVentilator,
    required this.hasStretcher,
    required this.is24x7,
    required this.onOxygen,
    required this.onVentilator,
    required this.onStretcher,
    required this.on24x7,
  });

  final bool hasOxygen;
  final bool hasVentilator;
  final bool hasStretcher;
  final bool is24x7;
  final ValueChanged<bool> onOxygen;
  final ValueChanged<bool> onVentilator;
  final ValueChanged<bool> onStretcher;
  final ValueChanged<bool> on24x7;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Oxygen',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
          value: hasOxygen,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onOxygen,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Ventilator',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
          value: hasVentilator,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onVentilator,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Stretcher',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
          value: hasStretcher,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onStretcher,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('24×7 service',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium)),
          value: is24x7,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: on24x7,
        ),
      ],
    );
  }
}

class DigitsOnlyFormatter extends TextInputFormatter {
  const DigitsOnlyFormatter({this.maxLength});

  final int? maxLength;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = maxLength != null && digits.length > maxLength!
        ? digits.substring(0, maxLength!)
        : digits;
    return TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }
}
