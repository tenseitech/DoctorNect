import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/invite/ambulance_invite_service.dart';
import '../../../../core/constants/country_phone_codes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/phone_number_field.dart';
import '../../../../widgets/required_field_label.dart';
import '../../../ambulance/models/ambulance_models.dart';
import '../../../ambulance/widgets/ambulance_invite_link_sheet.dart';
import '../../../ambulance/widgets/ambulance_service_form_fields.dart';
import '../../../../core/theme/app_typography.dart';

/// Doctor fills ambulance service details and generates a driver invite link.
class DoctorAddAmbulanceScreen extends StatefulWidget {
  const DoctorAddAmbulanceScreen({super.key});

  @override
  State<DoctorAddAmbulanceScreen> createState() =>
      _DoctorAddAmbulanceScreenState();
}

class _DoctorAddAmbulanceScreenState extends State<DoctorAddAmbulanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serviceNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _vehicleNumberCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _serviceAreasCtrl = TextEditingController();
  final _baseAddressCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  AmbulanceType _ambulanceType = AmbulanceType.bls;
  bool _hasOxygen = false;
  bool _hasVentilator = false;
  bool _hasStretcher = true;
  bool _is24x7 = false;
  bool _submitting = false;
  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;

  @override
  void dispose() {
    _serviceNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _driverNameCtrl.dispose();
    _phoneCtrl.dispose();
    _vehicleNumberCtrl.dispose();
    _cityCtrl.dispose();
    _serviceAreasCtrl.dispose();
    _baseAddressCtrl.dispose();
    _licenseCtrl.dispose();
    _insuranceCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _createInvite() async {
    if (!_formKey.currentState!.validate()) return;

    if (!FirebaseBootstrap.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Firebase is not connected. Check internet and try again.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    final draft = buildAmbulanceDraftFromControllers(
      serviceNameCtrl: _serviceNameCtrl,
      ownerNameCtrl: _ownerNameCtrl,
      driverNameCtrl: _driverNameCtrl,
      phoneCtrl: _phoneCtrl,
      vehicleNumberCtrl: _vehicleNumberCtrl,
      ambulanceType: _ambulanceType,
      cityCtrl: _cityCtrl,
      serviceAreasCtrl: _serviceAreasCtrl,
      baseAddressCtrl: _baseAddressCtrl,
      licenseCtrl: _licenseCtrl,
      insuranceCtrl: _insuranceCtrl,
      hasOxygen: _hasOxygen,
      hasVentilator: _hasVentilator,
      hasStretcher: _hasStretcher,
      is24x7: _is24x7,
      rateCtrl: _rateCtrl,
      formattedPhone: FormValidators.formatFullPhone(
        _phoneDialCode,
        _phoneCtrl.text.trim(),
      ),
    );

    final result = await AmbulanceInviteService.createInvite(draft: draft);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create invite. Please try again.'),
        ),
      );
      return;
    }

    await AmbulanceInviteLinkSheet.show(
      context,
      serviceName: draft.serviceName,
      driverName: draft.driverName,
      link: result.link,
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        title: Text(
          'Add Ambulance',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      'Fill the ambulance service details. An invite link will be created for the driver to download the app, set a PIN, and login.',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Service Information', icon: Icons.business),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _serviceNameCtrl,
                    label: 'Service / Company Name',
                    icon: Icons.local_hospital,
                    validator: ambulanceRequiredField,
                  ),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _ownerNameCtrl,
                    label: 'Owner / Manager Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Driver Details', icon: Icons.badge_outlined),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _driverNameCtrl,
                    label: 'Driver Name',
                    icon: Icons.person,
                    validator: ambulanceRequiredField,
                  ),
                  const SizedBox(height: 10),
                  PhoneNumberField(
                    controller: _phoneCtrl,
                    initialDialCode: _phoneDialCode,
                    onDialCodeChanged: (code) => _phoneDialCode = code,
                    labelText: 'Driver Phone',
                    validator: (v) =>
                        FormValidators.phoneLocal(v, dialCode: _phoneDialCode),
                    decoration: RequiredFieldLabels.decorate(
                      InputDecoration(
                        prefixIcon: Icon(Icons.phone_outlined,
                            size: 20, color: AppColors.textSecondaryOf(context)),
                        filled: true,
                        fillColor: AppColors.surfaceOf(context),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(12))),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide(color: AppColors.borderOf(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide:
                              BorderSide(color: Color(0xFFDC2626), width: 1.5),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      'Driver Phone',
                      isRequired: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Vehicle Information',
                      icon: Icons.local_shipping_outlined),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _vehicleNumberCtrl,
                    label: 'Vehicle Number',
                    icon: Icons.directions_car,
                    hint: 'e.g. MH-12-AB-4521',
                    validator: ambulanceVehicleNumberField,
                    formatters: ambulanceVehicleNumberFormatters,
                    capitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 10),
                  AmbulanceTypeField(
                    value: _ambulanceType,
                    onChanged: (v) => setState(() => _ambulanceType = v),
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Service Area', icon: Icons.location_on_outlined),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _cityCtrl,
                    label: 'City',
                    icon: Icons.location_city,
                    validator: ambulanceRequiredField,
                  ),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _serviceAreasCtrl,
                    label: 'Service Areas (comma-separated)',
                    icon: Icons.map_outlined,
                    hint: 'e.g. Dharampeth, Sitabuldi, Sadar',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _baseAddressCtrl,
                    label: 'Base / Parking Address',
                    icon: Icons.home_outlined,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Licensing & Insurance',
                      icon: Icons.verified_outlined),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _licenseCtrl,
                    label: 'License / Permit Number',
                    icon: Icons.description_outlined,
                    validator: FormValidators.drivingLicense,
                  ),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _insuranceCtrl,
                    label: 'Insurance Number',
                    icon: Icons.security_outlined,
                    validator: FormValidators.insuranceNumber,
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Equipment & Features',
                      icon: Icons.medical_services_outlined),
                  const SizedBox(height: 8),
                  AmbulanceFormToggleRow(
                    label: 'Has Oxygen Supply',
                    value: _hasOxygen,
                    onChanged: (v) => setState(() => _hasOxygen = v),
                  ),
                  AmbulanceFormToggleRow(
                    label: 'Has Ventilator',
                    value: _hasVentilator,
                    onChanged: (v) => setState(() => _hasVentilator = v),
                  ),
                  AmbulanceFormToggleRow(
                    label: 'Has Stretcher',
                    value: _hasStretcher,
                    onChanged: (v) => setState(() => _hasStretcher = v),
                  ),
                  AmbulanceFormToggleRow(
                    label: 'Available 24×7',
                    value: _is24x7,
                    onChanged: (v) => setState(() => _is24x7 = v),
                  ),
                  const SizedBox(height: 20),
                  const AmbulanceFormSectionTitle(
                      title: 'Pricing', icon: Icons.currency_rupee),
                  const SizedBox(height: 10),
                  AmbulanceFormField(
                    controller: _rateCtrl,
                    label: 'Rate per KM (₹)',
                    icon: Icons.currency_rupee,
                    keyboard: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                    ],
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _submitting ? null : _createInvite,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      minimumSize: Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: AppColors.surfaceOf(context)),
                          )
                        : Text(
                            'Create Invite Link',
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
