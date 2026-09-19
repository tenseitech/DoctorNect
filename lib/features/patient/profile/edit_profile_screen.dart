import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/auth/contact_change_otp_service.dart';
import '../../../core/auth/contact_change_verification.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/country_phone_codes.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/firebase/firestore_service.dart';
import '../../../core/media/gallery_image_picker.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/session/app_session.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/image_viewer_dialog.dart';
import '../../../widgets/phone_number_field.dart';
import '../../auth/widgets/registration_address_section.dart';
import 'data/patient_photo_local_store.dart';
import 'data/patient_profile_mock.dart';
import 'models/patient_profile_models.dart';
import 'utils/patient_bmi_utils.dart';
import 'widgets/patient_profile_form_styles.dart';
import 'widgets/profile_edit_widgets.dart';
import '../../../core/theme/app_typography.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile, required this.onSaved});

  final PatientProfile profile;
  final VoidCallback onSaved;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileFocus = FocusNode();
  final _emailFocus = FocusNode();
  late final _nameController = TextEditingController(text: widget.profile.name);
  late final _mobileParsed = FormValidators.parsePhone(widget.profile.mobile);
  late final _mobileController = TextEditingController(text: _mobileParsed.localNumber);
  late String _mobileDialCode = _mobileParsed.dialCode;
  late final _emailController = TextEditingController(text: widget.profile.email);
  late final _ageController = TextEditingController(
    text: widget.profile.age > 0 ? '${widget.profile.age}' : '',
  );
  late final _heightController = TextEditingController(
    text: widget.profile.height > 0 ? widget.profile.height.toString() : '',
  );
  late final _weightController = TextEditingController(
    text: widget.profile.weight > 0 ? widget.profile.weight.toString() : '',
  );

  late final _address1Controller = TextEditingController(text: PatientProfileMock.profileAddress.addressLine1);
  late final _address2Controller = TextEditingController(text: PatientProfileMock.profileAddress.addressLine2);
  late final _pincodeController = TextEditingController(text: PatientProfileMock.profileAddress.pincode);
  
  String? _country;
  String? _state;
  String? _city;

  String? _selectedGender;
  String? _selectedBloodGroup;
  String? _genderError;
  String? _bloodGroupError;
  bool _editingMobile = false;
  String? _verifiedMobileTarget;

  String _bmiResult = '--';
  double? _bmiValue;
  String? _photoUrl;
  Uint8List? _localPhotoBytes;

  String _effectivePatientId() {
    if (PatientSession.loggedInPatientId.isNotEmpty) {
      return PatientSession.loggedInPatientId;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid.isNotEmpty) {
      return user.uid;
    }
    return AppSession.patientId;
  }

  void _calculateBmi({bool notify = true}) {
    final heightCm = double.tryParse(_heightController.text) ?? 0.0;
    final weightKg = double.tryParse(_weightController.text) ?? 0.0;
    final bmi = PatientBmiUtils.calculate(heightCm: heightCm, weightKg: weightKg);

    if (bmi != null) {
      _bmiValue = bmi;
      _bmiResult = bmi.toStringAsFixed(1);
    } else {
      _bmiValue = null;
      _bmiResult = '--';
    }
    if (notify) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.profile.photoUrl ?? PatientProfileMock.profile.photoUrl;
    _loadLocalPhoto();
    final gender = widget.profile.gender.trim();
    if (AppConstants.genders.contains(gender)) {
      _selectedGender = gender;
    }
    final blood = widget.profile.bloodGroup.trim();
    if (ProfileEditWidgets.bloodGroups.contains(blood)) {
      _selectedBloodGroup = blood;
    }
    _country = PatientProfileMock.profileAddress.country.isNotEmpty ? PatientProfileMock.profileAddress.country : null;
    _state = PatientProfileMock.profileAddress.state.isNotEmpty ? PatientProfileMock.profileAddress.state : null;
    _city = PatientProfileMock.profileAddress.city.isNotEmpty ? PatientProfileMock.profileAddress.city : null;

    _calculateBmi(notify: false);
    _mobileFocus.addListener(_onMobileFocusChange);
  }

  Future<void> _loadLocalPhoto() async {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty) return;
    final bytes = await PatientPhotoLocalStore.load(patientId);
    if (!mounted || bytes == null) return;
    setState(() => _localPhotoBytes = bytes);
  }

  Future<void> _pickPhoto() async {
    final photoUrl = _photoUrl ?? widget.profile.photoUrl ?? PatientProfileMock.profile.photoUrl;
    final localBytes = _localPhotoBytes ?? PatientPhotoLocalStore.readCached(_effectivePatientId());
    final hasLocalPhoto = localBytes != null && localBytes.isNotEmpty;
    final hasNetworkPhoto = !hasLocalPhoto && photoUrl != null && photoUrl.isNotEmpty;

    ImageProvider? currentImage;
    if (hasLocalPhoto) {
      currentImage = MemoryImage(localBytes);
    } else if (hasNetworkPhoto) {
      currentImage = NetworkImage(photoUrl);
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentImage != null)
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View Photo'),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (currentImage != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'view') {
      if (currentImage != null) {
        showImageViewerDialog(context, currentImage, title: 'Profile Photo');
      }
      return;
    }

    if (source == 'remove') {
      final patientId = _effectivePatientId();
      if (patientId.isNotEmpty) {
        await PatientPhotoLocalStore.clear(patientId);
        if (FirebaseBootstrap.isReady) {
          try {
            await FirestoreService.instance.patientProfile.savePatientDocument(
              patientId,
              {
                'hasLocalPhoto': false,
                'photoStorage': null,
                'photoUrl': FieldValue.delete(),
                'photoURL': FieldValue.delete(),
              },
            );
          } catch (_) {}
          try {
            await FirebaseFirestore.instance.collection(FirestorePaths.users).doc(patientId).set({
              'photoUrl': FieldValue.delete(),
              'photoURL': FieldValue.delete(),
            }, SetOptions(merge: true));
          } catch (_) {}
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await user.updatePhotoURL(null);
              await user.reload();
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _localPhotoBytes = null;
        _photoUrl = null;
        widget.profile.photoUrl = null;
        PatientProfileMock.profile.photoUrl = null;
      });
      PatientProfileMock.notifyProfileUpdated();
      return;
    }

    final picked = source == 'camera'
        ? await GalleryImagePicker.pickFromCamera()
        : await GalleryImagePicker.pickSingle();
    if (picked == null || !mounted) return;

    final platformFile = PlatformFile(
      name: picked.name,
      size: picked.bytes.length,
      path: picked.path,
      bytes: picked.bytes,
    );

    await _uploadProfilePhoto(platformFile);
  }

  Future<void> _uploadProfilePhoto(PlatformFile file) async {
    final patientId = _effectivePatientId();
    if (patientId.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Please log in to set a profile photo');
      return;
    }

    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to read photo');
      return;
    }

    if (bytes.length > PatientPhotoLocalStore.maxFileBytes) {
      if (!mounted) return;
      AppToast.info(context, 'Photo must be 5 MB or smaller');
      return;
    }

    // 1. Save locally immediately
    await PatientPhotoLocalStore.save(patientId, bytes);
    if (mounted) {
      setState(() {
        _localPhotoBytes = bytes;
      });
    }

    try {
      // 2. Upload to Firebase Storage
      String? remoteUrl;
      if (FirebaseBootstrap.isReady) {
        try {
          remoteUrl = await PatientPhotoLocalStore.uploadToFirebaseStorage(patientId, bytes);
        } catch (e) {
          if (kDebugMode) debugPrint('[EditProfile] Storage upload warning: $e');
        }
      }

      final finalUrl = remoteUrl ?? 'data:image/jpeg;base64,${base64Encode(bytes)}';

      // 3. Save to Firestore in patients & users collections
      if (FirebaseBootstrap.isReady) {
        try {
          await FirestoreService.instance.patientProfile.savePatientDocument(
            patientId,
            {
              'hasLocalPhoto': true,
              'photoStorage': remoteUrl != null ? 'firebase' : 'base64',
              'photoUrl': remoteUrl ?? finalUrl,
              'photoURL': remoteUrl ?? finalUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        } catch (_) {}

        try {
          await FirebaseFirestore.instance.collection(FirestorePaths.users).doc(patientId).set({
            'photoUrl': remoteUrl ?? finalUrl,
            'photoURL': remoteUrl ?? finalUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && remoteUrl != null) {
            await user.updatePhotoURL(remoteUrl);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _localPhotoBytes = bytes;
        _photoUrl = remoteUrl ?? finalUrl;
        widget.profile.photoUrl = remoteUrl ?? finalUrl;
        PatientProfileMock.profile.photoUrl = remoteUrl ?? finalUrl;
      });
      PatientProfileMock.notifyProfileUpdated();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to save photo: $e');
    }
  }

  String _currentFormattedMobile() => ContactChangeVerification.canonicalMobile(
        _mobileDialCode,
        _mobileController.text.trim(),
      );

  void _onMobileInputChanged() {
    final current = _currentFormattedMobile();
    final saved = ContactChangeVerification.canonicalMobileFromStored(widget.profile.mobile);
    if (current == saved) {
      _verifiedMobileTarget = null;
    } else if (_verifiedMobileTarget != current) {
      _verifiedMobileTarget = null;
    }
    setState(() {});
  }

  void _onMobileFocusChange() {
    if (!_mobileFocus.hasFocus && _editingMobile && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mobileFocus.hasFocus || !_editingMobile) return;
        unawaited(_handleMobileEditComplete());
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _pincodeController.dispose();
    _mobileFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  int get _mobileMaxLength =>
      _mobileDialCode == CountryPhoneCodes.defaultDialCode ? 10 : 15;

  void _requestMobileChange() => _beginMobileEdit();

  Future<bool> _verifyNewContactOtp({
    required ContactVerificationChannel channel,
    required String destination,
    required String purpose,
  }) {
    return ContactChangeVerification.verifyIfNeeded(
      context: context,
      channel: channel,
      destination: destination,
      purpose: purpose,
      verifiedCanonical: null,
      accentColor: AppColors.patientTeal,
    );
  }

  Future<void> _handleMobileEditComplete() async {
    final nextMobile = _currentFormattedMobile();
    final saved = ContactChangeVerification.canonicalMobileFromStored(widget.profile.mobile);

    if (nextMobile == saved) {
      setState(() {
        _editingMobile = false;
        _verifiedMobileTarget = null;
      });
      return;
    }

    final localErr = FormValidators.phoneLocal(
      _mobileController.text.trim(),
      dialCode: _mobileDialCode,
    );
    if (localErr != null) {
      AppToast.info(context, localErr);
      return;
    }

    if (_verifiedMobileTarget == nextMobile) {
      setState(() => _editingMobile = false);
      return;
    }

    final verified = await _verifyNewContactOtp(
      channel: ContactVerificationChannel.mobile,
      destination: nextMobile,
      purpose: 'verify your new mobile number',
    );
    if (!mounted) return;

    if (verified) {
      setState(() {
        _verifiedMobileTarget = nextMobile;
        _editingMobile = false;
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingMobile) _mobileFocus.requestFocus();
    });
  }

  void _beginMobileEdit() {
    setState(() {
      _editingMobile = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mobileFocus.requestFocus();
      final text = _mobileController.text;
      _mobileController.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    });
  }

  void _finishContactEditing() {
    setState(() {
      _editingMobile = false;
    });
    _mobileFocus.unfocus();
  }

  Future<void> _onSavePressed() async {
    FocusScope.of(context).unfocus();
    if (_editingMobile) {
      await _handleMobileEditComplete();
      if (!mounted) return;
    }

    setState(() {
      _genderError = (_selectedGender == null || _selectedGender!.isEmpty)
          ? 'Please select a gender'
          : null;
      _bloodGroupError = (_selectedBloodGroup == null || _selectedBloodGroup!.isEmpty)
          ? 'Please select a blood group'
          : null;
    });

    final formState = _formKey.currentState;
    if (formState == null) return;

    final nextMobile = _currentFormattedMobile();
    final mobileChanged =
        !ContactChangeVerification.mobilesEqual(nextMobile, widget.profile.mobile);

    if (mobileChanged && _verifiedMobileTarget != nextMobile) {
      final localErr = FormValidators.phoneLocal(
        _mobileController.text.trim(),
        dialCode: _mobileDialCode,
      );
      if (localErr != null) {
        AppToast.info(context, localErr);
        return;
      }

      final verified = await _verifyNewContactOtp(
        channel: ContactVerificationChannel.mobile,
        destination: nextMobile,
        purpose: 'verify your new mobile number',
      );
      if (!mounted) return;
      if (!verified) {
        AppToast.info(context, 'Verify your new mobile number with OTP before saving.');
        return;
      }
      setState(() => _verifiedMobileTarget = nextMobile);
    }

    if (formState.validate() && _genderError == null && _bloodGroupError == null) {
      _finishContactEditing();
      await _persistProfile();
    }
  }

  Future<void> _persistProfile() async {
    final parsedAge = int.tryParse(_ageController.text.trim());
    if (parsedAge == null) return;

    widget.profile.name = _nameController.text.trim();
    widget.profile.age = parsedAge;
    widget.profile.gender = _selectedGender!;
    widget.profile.bloodGroup = _selectedBloodGroup!;
    widget.profile.height = double.tryParse(_heightController.text.trim()) ?? 0.0;
    widget.profile.weight = double.tryParse(_weightController.text.trim()) ?? 0.0;
    widget.profile.mobile = _currentFormattedMobile();

    PatientProfileMock.profileAddress = PatientProfileMock.profileAddress.copyWith(
      country: _country,
      state: _state,
      city: _city,
      addressLine1: _address1Controller.text.trim(),
      addressLine2: _address2Controller.text.trim(),
      pincode: _pincodeController.text.trim(),
    );

    try {
      await PatientProfileMock.persistCurrentProfile();
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to save profile. Please try again.');
      return;
    }

    widget.onSaved();
    if (!mounted) return;
    Navigator.pop(context);
  }

  String get _displayName {
    final name = _nameController.text.trim();
    return name.isNotEmpty ? name : widget.profile.name;
  }

  @override
  Widget build(BuildContext context) {
    final initial = _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'P';
    final photoUrl = _photoUrl ?? widget.profile.photoUrl ?? PatientProfileMock.profile.photoUrl;
    final localBytes = _localPhotoBytes ?? PatientPhotoLocalStore.readCached(_effectivePatientId());
    final hasLocalPhoto = localBytes != null && localBytes.isNotEmpty;
    final hasNetworkPhoto = !hasLocalPhoto && photoUrl != null && photoUrl.isNotEmpty;

    ImageProvider? avatarImage;
    if (hasLocalPhoto) {
      avatarImage = MemoryImage(localBytes);
    } else if (hasNetworkPhoto) {
      avatarImage = NetworkImage(photoUrl);
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Personal Information', context: context),
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
                        initial: initial,
                        name: _displayName,
                        subtitle: 'Update your health and contact details',
                        onPhotoTap: _pickPhoto,
                        avatarImage: avatarImage,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Basic details',
                      subtitle: 'Name and gender are locked for identity',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProfileEditWidgets.lockedNote(
                            message: 'Full name, gender, and blood group cannot be changed here. Contact support if incorrect.',
                          ),
                          const SizedBox(height: 14),
                          ProfileEditWidgets.lockedField(
                            label: 'Full name',
                            value: _displayName,
                          ),
                          const SizedBox(height: 12),
                          ProfileEditWidgets.genderChips(
                            selected: _selectedGender,
                            onSelected: null,
                            errorText: _genderError,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: PatientProfileFormStyles.fieldDecoration(context, 
                              labelText: 'Age',
                              isRequired: true,
                            ),
                            validator: FormValidators.age,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.favorite_outline_rounded,
                      title: 'Health metrics',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProfileEditWidgets.bloodGroupChips(
                            selected: _selectedBloodGroup,
                            onSelected: null,
                            errorText: _bloodGroupError,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _heightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                  ],
                                  decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Height (cm)'),
                                  onChanged: (_) => _calculateBmi(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _weightController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                  ],
                                  decoration: PatientProfileFormStyles.fieldDecoration(context, labelText: 'Weight (kg)'),
                                  onChanged: (_) => _calculateBmi(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ProfileEditWidgets.bmiCard(
                            bmiResult: _bmiResult,
                            bmiValue: _bmiValue,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.contact_phone_outlined,
                      title: 'Contact',
                      subtitle: 'Used for appointments and lab updates',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PhoneNumberField(
                            controller: _mobileController,
                            focusNode: _mobileFocus,
                            readOnly: !_editingMobile,
                            onTap: _editingMobile ? null : _requestMobileChange,
                            initialPhone: widget.profile.mobile,
                            initialDialCode: _mobileDialCode,
                            onDialCodeChanged: (code) {
                              _mobileDialCode = code;
                              if (_editingMobile) _onMobileInputChanged();
                            },
                            decoration: ProfileEditWidgets.contactDecoration(
                            context: context,
                              labelText: 'Mobile number',
                              editing: _editingMobile,
                              suffixIcon: _editingMobile
                                  ? null
                                  : ProfileEditWidgets.changeAction(onPressed: _requestMobileChange),
                              counterText: _editingMobile
                                  ? '${_mobileController.text.length}/$_mobileMaxLength'
                                  : null,
                            ),
                            onChanged: _onMobileInputChanged,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailController,
                            focusNode: _emailFocus,
                            readOnly: true,
                            showCursor: false,
                            enableInteractiveSelection: false,
                            keyboardType: TextInputType.emailAddress,
                            decoration: ProfileEditWidgets.contactDecoration(
                              context: context,
                              labelText: 'Email address (immutable)',
                              editing: false,
                              suffixIcon: null,
                            ),
                          ),
                          if (!_editingMobile)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'Tap Change to update your registered mobile number via SMS OTP.',
                                style: TextStyle(
                                  fontSize: AppTypography.labelMedium,
                                  color: AppColors.textSecondaryOf(context).withValues(alpha: 0.9),
                                  height: 1.35,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ProfileEditWidgets.sectionCard(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      subtitle: 'Your primary address for services',
                      child: RegistrationAddressSection(
                        initialCountry: _country,
                        initialState: _state,
                        initialCity: _city,
                        onCountryChanged: (v) => setState(() => _country = v),
                        onStateChanged: (v) => setState(() => _state = v),
                        onCityChanged: (v) => setState(() => _city = v),
                        address1Controller: _address1Controller,
                        address2Controller: _address2Controller,
                        pinCodeController: _pincodeController,
                        accentColor: AppColors.patientTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PatientProfileFormStyles.bottomSaveButton(
              onPressed: _onSavePressed,
              label: 'Save Changes',
            ),
          ],
        ),
      ),
    );
  }
}
