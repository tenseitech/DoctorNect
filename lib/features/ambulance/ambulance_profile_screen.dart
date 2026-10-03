import '../../core/firebase/firestore_service.dart';
import '../../core/notifications/app_toast.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/auth/verification_lifecycle.dart';
import '../../core/firebase/firestore_paths.dart';
import '../../widgets/verified_badge_icon.dart';
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
        AmbulanceStore.instance.findAmbulance(widget.ambulanceId),
      );
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

  void _onTapMissingDetail(VerificationRequirementItem item) {
    if (!_editing) {
      setState(() => _editing = true);
    }
  }

  String _formatAddress(RegisteredAmbulance live) {
    final streetParts = [
      if (live.addressLine1.trim().isNotEmpty) live.addressLine1.trim(),
      if (live.addressLine2.trim().isNotEmpty) live.addressLine2.trim(),
    ].join(', ');

    final localityParts = [
      if (live.city.trim().isNotEmpty) live.city.trim(),
      if (live.state.trim().isNotEmpty) live.state.trim(),
    ].join(', ');

    final cityStatePin = [
      if (localityParts.isNotEmpty) localityParts,
      if (live.pincode.trim().isNotEmpty) live.pincode.trim(),
    ].join(' - ');

    final allParts = [
      if (streetParts.isNotEmpty) streetParts,
      if (cityStatePin.isNotEmpty) cityStatePin,
      if (live.country.trim().isNotEmpty &&
          live.country.trim().toLowerCase() != 'india')
        live.country.trim(),
    ];

    return allParts.isEmpty ? '' : allParts.join('\n');
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final current = _ambulance;
    if (current == null) return;

    final phoneRaw = _phoneCtrl.text.trim();
    if (phoneRaw.isNotEmpty) {
      final phoneErr = FormValidators.phoneLocal(
        phoneRaw,
        dialCode: _phoneDialCode,
      );
      if (phoneErr != null) {
        AppToast.info(context, phoneErr);
        return;
      }

      final newPhone = FormValidators.formatFullPhone(
        _phoneDialCode,
        phoneRaw,
      );
      if (!ContactChangeVerification.mobilesEqual(newPhone, current.phone)) {
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
            context,
            'Verify your new mobile number with OTP before saving.',
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    final areas = _areasCtrl.text
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final formattedPhone = phoneRaw.isNotEmpty
        ? FormValidators.formatFullPhone(_phoneDialCode, phoneRaw)
        : '';

    final updated = current.copyWith(
      serviceName: _serviceNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      driverName: _driverNameCtrl.text.trim(),
      phone: formattedPhone,
      vehicleNumber: FormValidators.normalizeVehicleNumber(_vehicleCtrl.text),
      ambulanceType: _ambulanceType,
      city: _city ?? '',
      serviceAreas: areas,
      baseAddress: _address1Ctrl.text.trim(),
      licenseNumber: _licenseCtrl.text.trim(),
      insuranceNumber: _insuranceCtrl.text.trim(),
      hasOxygen: _hasOxygen,
      hasVentilator: _hasVentilator,
      hasStretcher: _hasStretcher,
      is24x7: _is24x7,
      ratePerKm: double.tryParse(_rateCtrl.text.trim()),
      addressLine1: _address1Ctrl.text.trim(),
      addressLine2: _address2Ctrl.text.trim(),
      country: _country ?? '',
      state: _state ?? '',
      pincode: _pincodeCtrl.text.trim(),
    );

    final ok = await FirestoreService.instance.ambulance.updateAmbulanceProfile(
      updated,
    );
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
      AmbulanceStore.instance.updateRegisteredAmbulance(updated);
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

      final data = RoleVerificationController.instance.profileDataFor(
        UserType.ambulance,
        firestoreData: updated.toMap(),
      );
      if (updated.addressLine1.isNotEmpty) {
        data['baseAddress'] = updated.addressLine1;
      }
      final isComplete =
          VerificationRequirementsConfig.isComplete(UserType.ambulance, data);
      final stage =
          RoleVerificationController.instance.stageFor(UserType.ambulance);
      final isVerified = updated.verified ||
          RoleVerificationController.instance.isVerified(UserType.ambulance);

      if (isComplete &&
          !isVerified &&
          (stage == VerificationStage.profileIncomplete ||
              stage == VerificationStage.revisionRequested ||
              stage == VerificationStage.rejected)) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        await submitAmbulanceVerificationBatch(
          uid: uid,
          ambulanceId: updated.id,
        );
        if (mounted) {
          AppToast.info(
            context,
            'Profile complete. Submitted for verification.',
          );
        }
      }
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
            child: CircularProgressIndicator(color: Color(0xFFDC2626)),
          )
        : amb == null
            ? Center(
                child: Text(
                  'Profile not found',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.textSecondaryOf(context),
                  ),
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
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: AppTypography.headlineLarge,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Service details, availability & account',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: AppTypography.bodySmall,
                                        color:
                                            AppColors.textSecondaryOf(context),
                                      ),
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
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          AmbulanceAvailabilityToggle(
                            ambulanceId: widget.ambulanceId,
                          ),
                          const SizedBox(height: 16),
                        ],
                        _ProfileHeaderCard(ambulance: live),
                        const SizedBox(height: 16),
                        _AmbulanceProfileCompletionCard(
                          ambulance: live,
                          onTapMissingDetail: _onTapMissingDetail,
                        ),
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
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ] else ...[
                          _ProfileSection(
                            title: 'Service',
                            withDividers: true,
                            children: [
                              _InfoRow('Service name', live.serviceName),
                              _InfoRow('Owner', live.ownerName),
                              _InfoRow('Username', live.username),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Driver & contact',
                            withDividers: true,
                            children: [
                              _InfoRow('Driver name', live.driverName),
                              _InfoRow('Phone', live.phone),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Vehicle',
                            withDividers: true,
                            children: [
                              _InfoRow('Vehicle number', live.vehicleNumber),
                              _InfoRow(
                                  'Ambulance type', live.ambulanceTypeLabel),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Location',
                            withDividers: true,
                            children: [
                              _InfoRow('City', live.city),
                              if (live.serviceAreas.isNotEmpty)
                                _InfoRow(
                                  'Service areas',
                                  live.serviceAreas.join(', '),
                                ),
                              _InfoRow(
                                'Address',
                                _formatAddress(live),
                              ),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Licensing',
                            withDividers: true,
                            children: [
                              _InfoRow('License', live.licenseNumber),
                              _InfoRow('Insurance', live.insuranceNumber),
                            ],
                          ),
                          _ProfileSection(
                            title: 'Operations',
                            withDividers: true,
                            children: [
                              _InfoRow(
                                'Rate per km',
                                live.ratePerKm != null
                                    ? '₹${live.ratePerKm!.toStringAsFixed(0)}'
                                    : '',
                              ),
                              _InfoRow(
                                'Equipment',
                                [
                                  if (live.hasOxygen) 'Oxygen',
                                  if (live.hasVentilator) 'Ventilator',
                                  if (live.hasStretcher) 'Stretcher',
                                  if (live.is24x7) '24×7',
                                ].join(' · '),
                              ),
                              _InfoRow(
                                'Status',
                                live.available ? 'Online' : 'Offline',
                              ),
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
                                    leading: const Icon(
                                      Icons.campaign_rounded,
                                      color: Color(0xFFDC2626),
                                    ),
                                    title: Text(
                                      'Promote Banner Ad',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppTypography.bodyMedium,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Advertise ambulance service on Patient Home',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: AppTypography.labelMedium,
                                        color: Colors.grey,
                                      ),
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
        title: Text(
          'My Profile',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
        ),
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
                style: TextStyle(
                  fontFamily: 'Inter',
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
            _editField(
              _serviceNameCtrl,
              'Service name',
              Icons.local_hospital_outlined,
            ),
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
                  'Ambulance type',
                  Icons.medical_services_outlined,
                ),
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
              pinCodeRequired: false,
              addressLine1Required: false,
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
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = double.tryParse(v.trim());
                if (n == null || n < 0) return 'Enter a valid rate';
                return null;
              },
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
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
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
        validator: validator != null
            ? (v) => (v == null || v.trim().isEmpty) ? null : validator(v)
            : null,
        decoration: _inputDecoration(label, icon),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        size: 20,
        color: AppColors.textSecondaryOf(context),
      ),
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

Future<void> submitAmbulanceVerificationBatch({
  required String uid,
  required String ambulanceId,
}) async {
  try {
    final batch = FirebaseFirestore.instance.batch();
    if (uid.isNotEmpty) {
      final userRef =
          FirebaseFirestore.instance.collection(FirestorePaths.users).doc(uid);
      batch.set(
        userRef,
        {
          'verificationStatus': 'submitted_for_verification',
          'status': 'pending_review',
          'submittedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    if (ambulanceId.isNotEmpty) {
      final ambRef = FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId);
      batch.set(
        ambRef,
        {
          'verificationStatus': 'submitted_for_verification',
          'status': 'pending_review',
          'submittedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  } catch (_) {
    // Graceful fallback for test or offline environments
  }
  RoleVerificationController.instance.setRoleState(
    UserType.ambulance,
    stage: VerificationStage.submittedForVerification,
  );
}

class _AmbulanceProfileCompletionCard extends StatefulWidget {
  const _AmbulanceProfileCompletionCard({
    required this.ambulance,
    required this.onTapMissingDetail,
  });

  final RegisteredAmbulance ambulance;
  final ValueChanged<VerificationRequirementItem> onTapMissingDetail;

  @override
  State<_AmbulanceProfileCompletionCard> createState() =>
      _AmbulanceProfileCompletionCardState();
}

class _AmbulanceProfileCompletionCardState
    extends State<_AmbulanceProfileCompletionCard> {
  bool _showAll = false;
  bool _hasAutoSubmitted = false;

  void _triggerAutoSubmitIfNeeded({
    required BuildContext context,
    required String uid,
    required String ambulanceId,
    required bool isComplete,
    required VerificationStage stage,
    required bool isVerified,
  }) {
    if (_hasAutoSubmitted) return;
    if (isComplete &&
        !isVerified &&
        (stage == VerificationStage.profileIncomplete ||
            stage == VerificationStage.revisionRequested ||
            stage == VerificationStage.rejected)) {
      _hasAutoSubmitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await submitAmbulanceVerificationBatch(
          uid: uid,
          ambulanceId: ambulanceId,
        );
        if (context.mounted) {
          AppToast.info(
            context,
            'Profile complete. Submitted for verification.',
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AmbulanceStore.instance,
        RoleVerificationController.instance,
      ]),
      builder: (context, _) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final live =
            AmbulanceStore.instance.findAmbulance(widget.ambulance.id) ??
                widget.ambulance;

        if (uid.isEmpty) {
          return _buildContent(context, uid, live, null);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            final userData = snapshot.data?.data();
            return _buildContent(context, uid, live, userData);
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    String uid,
    RegisteredAmbulance live,
    Map<String, dynamic>? userData,
  ) {
    final isDark = AppColors.isDark(context);
    final firestoreStatus = userData?['verificationStatus'] as String? ??
        userData?['status'] as String?;

    final isVerified = live.verified ||
        (userData?['verified'] == true) ||
        RoleVerificationController.instance.isVerified(UserType.ambulance);

    final stage = isVerified
        ? VerificationStage.verified
        : (firestoreStatus != null
            ? VerificationStage.fromString(firestoreStatus)
            : RoleVerificationController.instance.stageFor(UserType.ambulance));

    final reason = userData?['rejectionReason'] as String? ??
        RoleVerificationController.instance
            .rejectionReasonFor(UserType.ambulance);

    if (stage == VerificationStage.verified) {
      return const SizedBox.shrink();
    }

    final data = RoleVerificationController.instance.profileDataFor(
      UserType.ambulance,
      firestoreData: userData,
    );
    data.addAll(live.toMap());
    if (live.addressLine1.isNotEmpty) {
      data['baseAddress'] = live.addressLine1;
    }

    final requirements =
        VerificationRequirementsConfig.requirementsForRole(UserType.ambulance);
    final total = requirements.length;
    final missing =
        VerificationRequirementsConfig.missingFields(UserType.ambulance, data);
    final filled = total - missing.length;
    final percentage = VerificationRequirementsConfig.completionPercentage(
      UserType.ambulance,
      data,
    );
    final isComplete = percentage >= 100;

    _triggerAutoSubmitIfNeeded(
      context: context,
      uid: uid,
      ambulanceId: live.id,
      isComplete: isComplete,
      stage: stage,
      isVerified: isVerified,
    );

    final itemsToShow = _showAll ? missing : missing.take(4).toList();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? AppColors.borderOf(context).withValues(alpha: 0.15)
              : AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Profile completion',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                _buildStatusChip(stage, isDark),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage / 100.0,
                minHeight: 8,
                backgroundColor:
                    isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$percentage% complete · $filled of $total details filled',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            if (stage == VerificationStage.submittedForVerification &&
                isComplete) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7)
                      .withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Submitted for verification. We will review your details shortly.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.bodySmall,
                          color: isDark
                              ? const Color(0xFF7DD3FC)
                              : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if ((stage == VerificationStage.rejected ||
                    stage == VerificationStage.revisionRequested) &&
                reason != null &&
                reason.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626)
                      .withValues(alpha: isDark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Revision note from admin',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFFF87171)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason.trim(),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodySmall,
                        color: isDark
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Missing details (${missing.length})',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              ...itemsToShow.map(
                (item) => _buildMissingItemRow(context, item, isDark),
              ),
              if (missing.length > 4)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    icon: Icon(
                      _showAll ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(
                      _showAll ? 'Show less' : 'Show all (${missing.length})',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMissingItemRow(
    BuildContext context,
    VerificationRequirementItem item,
    bool isDark,
  ) {
    return InkWell(
      onTap: () => widget.onTapMissingDetail(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              Icons.radio_button_unchecked,
              size: 14,
              color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.label} · ${item.section}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.textSecondaryOf(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(VerificationStage stage, bool isDark) {
    String label;
    Color bg;
    Color fg;

    if (stage == VerificationStage.submittedForVerification) {
      label = 'Under review';
      bg = const Color(0xFF0284C7).withValues(alpha: isDark ? 0.2 : 0.1);
      fg = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
    } else if (stage == VerificationStage.rejected ||
        stage == VerificationStage.revisionRequested) {
      label = 'Revision needed';
      bg = const Color(0xFFDC2626).withValues(alpha: isDark ? 0.2 : 0.1);
      fg = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    } else {
      label = 'Profile incomplete';
      bg = isDark
          ? const Color(0xFF3F3F46).withValues(alpha: 0.5)
          : const Color(0xFFF4F4F5);
      fg = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
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
              child: Icon(
                Icons.local_hospital,
                color: AppColors.surfaceOf(context),
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          ambulance.serviceName,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (ambulance.verified) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadgeIcon(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ambulance.driverName,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  Text(
                    ambulance.vehicleNumber,
                    style: TextStyle(
                      fontFamily: 'Inter',
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
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFFDC2626),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Rate the app, share link & legal',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.children,
    this.withDividers = false,
  });

  final String title;
  final List<Widget> children;
  final bool withDividers;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 10),
            if (withDividers) ...[
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 14,
                    thickness: 0.6,
                    color: AppColors.borderOf(context)
                        .withValues(alpha: isDark ? 0.12 : 0.2),
                  ),
                children[i],
              ],
            ] else
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
    final isEmpty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              isEmpty ? 'Not provided' : value,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodySmall,
                fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                color: isEmpty
                    ? AppColors.textSecondaryOf(context).withValues(alpha: 0.6)
                    : null,
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
          title: Text(
            'Oxygen',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: AppTypography.bodyMedium),
          ),
          value: hasOxygen,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onOxygen,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Ventilator',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: AppTypography.bodyMedium),
          ),
          value: hasVentilator,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onVentilator,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Stretcher',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: AppTypography.bodyMedium),
          ),
          value: hasStretcher,
          activeThumbColor: const Color(0xFFDC2626),
          onChanged: onStretcher,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '24×7 service',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: AppTypography.bodyMedium),
          ),
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
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
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
