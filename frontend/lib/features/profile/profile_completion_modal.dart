import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/profile_draft_store.dart';
import '../../core/auth/unified_auth_coordinator.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/firebase/firestore_paths.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/session/app_session.dart';
import '../../core/session/doctor_session.dart';
import '../../core/session/lab_session.dart';
import '../../core/session/medical_store_session.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/name_validator.dart';
import '../../core/auth/registration_credentials.dart';
import '../ambulance/data/ambulance_store.dart';
import '../auth/widgets/auth_brand_components.dart';
import '../doctor/profile/data/doctor_profile_store.dart';
import '../patient/profile/data/patient_profile_mock.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/qualification_selector.dart';
import '../../widgets/searchable_dropdown_form_field.dart';

/// Full-screen app-level overlay for completing or editing profile across ALL 6 roles.
///
/// Features:
/// - Responsive on desktop (centered dialog card) and mobile (full-screen sheet).
/// - Top bar with heading, subtext, and top-right close "X".
/// - X button closes and preserves partially entered draft data.
/// - Saves drafts to [ProfileDraftStore] (Firestore + SharedPreferences).
/// - Pre-fills with draft or existing profile data.
/// - Sets profileCompletionStatus to 'complete'.
class ProfileCompletionModal extends StatefulWidget {
  const ProfileCompletionModal({
    super.key,
    required this.role,
    this.isEditing = false,
  });

  final UserType role;
  final bool isEditing;

  static Future<bool?> show(
    BuildContext context, {
    required UserType role,
    bool isEditing = false,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Profile Modal',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, __) {
        return ProfileCompletionModal(role: role, isEditing: isEditing);
      },
    );
  }

  @override
  State<ProfileCompletionModal> createState() => _ProfileCompletionModalState();
}

class _ProfileCompletionModalState extends State<ProfileCompletionModal> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers for role fields
  final _nameController = TextEditingController();
  final _specializationController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _regNumberController = TextEditingController();
  final _facilityNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _experienceController = TextEditingController();
  final _genderController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _vehicleNumberController = TextEditingController();

  final _customSpecializationController = TextEditingController();
  final _customExperienceController = TextEditingController();
  final _customGenderController = TextEditingController();
  bool _specializationIsOther = false;
  String? _selectedExperienceOption;
  String? _selectedGenderOption;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  String get _userId {
    if (FirebaseBootstrap.isReady) {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid != null && authUid.isNotEmpty) return authUid;
    }

    return switch (widget.role) {
      UserType.doctor => DoctorSession.loggedInDoctorId,
      UserType.patient => PatientSession.loggedInPatientId,
      UserType.medical ||
      UserType.medicalStore =>
        MedicalStoreSession.loggedInStoreId,
      UserType.lab => LabSession.loggedInLabId,
      UserType.ambulance => AmbulanceSession.loggedInAmbulanceId,
      UserType.superAdmin => AppSession.adminId,
    };
  }

  Color get _accentColor => switch (widget.role) {
        UserType.doctor => AppColors.doctorBlue,
        UserType.patient => AppColors.patientTeal,
        UserType.medical => const Color(0xFF0D9488),
        UserType.medicalStore => AppColors.pharmacyGreen,
        UserType.lab => AppColors.labPurple,
        UserType.ambulance => const Color(0xFFDC2626),
        UserType.superAdmin => AppColors.doctorBlue,
      };

  IconData get _roleIcon => switch (widget.role) {
        UserType.doctor => Icons.medical_services_rounded,
        UserType.patient => Icons.person_rounded,
        UserType.medical => Icons.health_and_safety_rounded,
        UserType.medicalStore => Icons.local_pharmacy_rounded,
        UserType.lab => Icons.biotech_rounded,
        UserType.ambulance => Icons.emergency_rounded,
        UserType.superAdmin => Icons.admin_panel_settings_rounded,
      };

  @override
  void initState() {
    super.initState();
    _loadProfileAndDraft();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _qualificationController.dispose();
    _regNumberController.dispose();
    _facilityNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _experienceController.dispose();
    _genderController.dispose();
    _bloodGroupController.dispose();
    _vehicleNumberController.dispose();
    _customSpecializationController.dispose();
    _customExperienceController.dispose();
    _customGenderController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileAndDraft() async {
    setState(() => _loading = true);

    final id = _userId;

    // 1. Pre-fill from current in-memory / session state
    _nameController.text = _currentSessionName();

    // 2. Pre-fill role specific stores
    if (widget.role == UserType.doctor) {
      final doc = DoctorProfileStore.instance.profile;
      if (_nameController.text.isEmpty) _nameController.text = doc.fullName;
      if (doc.specialization.isNotEmpty)
        _specializationController.text = doc.specialization;
      if (doc.registrationNumber.isNotEmpty)
        _regNumberController.text = doc.registrationNumber;
      if (doc.city.isNotEmpty) _cityController.text = doc.city;
      if (doc.addressLine1.isNotEmpty)
        _addressController.text = doc.addressLine1;
      if (doc.mobile.isNotEmpty) _phoneController.text = doc.mobile;
      if (doc.email.isNotEmpty &&
          !RegistrationCredentials.isSyntheticEmail(doc.email)) {
        _emailController.text = doc.email;
      }
    } else if (widget.role == UserType.patient) {
      final p = PatientProfileMock.profile;
      if (_nameController.text.isEmpty) _nameController.text = p.name;
      if (p.gender.isNotEmpty) _genderController.text = p.gender;
      if (p.bloodGroup.isNotEmpty) _bloodGroupController.text = p.bloodGroup;
      if (p.mobile.isNotEmpty) _phoneController.text = p.mobile;
      if (p.email.isNotEmpty &&
          !RegistrationCredentials.isSyntheticEmail(p.email)) {
        _emailController.text = p.email;
      }
    } else if (widget.role == UserType.ambulance) {
      final amb = AmbulanceStore.instance.findAmbulance(id);
      if (amb != null) {
        if (_facilityNameController.text.isEmpty)
          _facilityNameController.text = amb.serviceName;
        if (_nameController.text.isEmpty) {
          _nameController.text =
              amb.driverName.isNotEmpty ? amb.driverName : amb.ownerName;
        }
        if (amb.vehicleNumber.isNotEmpty)
          _vehicleNumberController.text = amb.vehicleNumber;
        if (amb.licenseNumber.isNotEmpty)
          _regNumberController.text = amb.licenseNumber;
        if (amb.city.isNotEmpty) _cityController.text = amb.city;
        if (amb.addressLine1.isNotEmpty)
          _addressController.text = amb.addressLine1;
        if (amb.phone.isNotEmpty) _phoneController.text = amb.phone;
      }
    }

    // 3. Overlay Firestore domain doc if ready
    if (FirebaseBootstrap.isReady && id.isNotEmpty) {
      try {
        final collection = _collectionForRole();
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(id)
            .get();
        final data = doc.data();
        if (data != null) {
          _applyDataToControllers(data);
        }
      } catch (_) {}
    }

    // 4. Overlay saved uncommitted draft on top
    final draft = await ProfileDraftStore.instance.getDraft(
      role: widget.role,
      userIdOrPhone: id,
    );
    if (draft != null && draft.isNotEmpty) {
      _applyDataToControllers(draft);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _currentSessionName() {
    return switch (widget.role) {
      UserType.doctor => DoctorSession.loggedInDoctorName,
      UserType.patient => PatientSession.loggedInPatientName,
      UserType.medical ||
      UserType.medicalStore =>
        MedicalStoreSession.loggedInStoreName,
      UserType.lab => LabSession.loggedInLabName,
      UserType.ambulance => AmbulanceSession.loggedInDriverName.isNotEmpty
          ? AmbulanceSession.loggedInDriverName
          : AmbulanceSession.loggedInServiceName,
      UserType.superAdmin => AppSession.adminName,
    };
  }

  String _collectionForRole() {
    return switch (widget.role) {
      UserType.doctor => FirestorePaths.doctors,
      UserType.patient => FirestorePaths.patients,
      UserType.medical || UserType.medicalStore => FirestorePaths.medicalStores,
      UserType.lab => FirestorePaths.labs,
      UserType.ambulance => FirestorePaths.ambulances,
      UserType.superAdmin => FirestorePaths.users,
    };
  }

  void _applyDataToControllers(Map<String, dynamic> data) {
    if (data['name'] is String && data['name'].toString().isNotEmpty) {
      _nameController.text = data['name'].toString();
    }
    if (data['displayName'] is String && _nameController.text.isEmpty) {
      _nameController.text = data['displayName'].toString();
    }
    if (data['storeName'] is String &&
        data['storeName'].toString().isNotEmpty) {
      _facilityNameController.text = data['storeName'].toString();
      if (_nameController.text.isEmpty) {
        _nameController.text =
            data['ownerName']?.toString() ?? data['storeName'].toString();
      }
    }
    if (data['labName'] is String && data['labName'].toString().isNotEmpty) {
      _facilityNameController.text = data['labName'].toString();
    }
    if (data['serviceName'] is String &&
        data['serviceName'].toString().isNotEmpty) {
      _facilityNameController.text = data['serviceName'].toString();
    }
    if (data['driverName'] is String &&
        data['driverName'].toString().isNotEmpty) {
      _nameController.text = data['driverName'].toString();
    }
    if (data['specialization'] is String) {
      _specializationController.text = data['specialization'].toString();
    }
    if (data['qualification'] is String) {
      _qualificationController.text = data['qualification'].toString();
    }
    if (data['registrationNumber'] is String) {
      _regNumberController.text = data['registrationNumber'].toString();
    }
    if (data['licenseNumber'] is String) {
      _regNumberController.text = data['licenseNumber'].toString();
    }
    if (data['clinicName'] is String) {
      _facilityNameController.text = data['clinicName'].toString();
    }
    if (data['address'] is String) {
      _addressController.text = data['address'].toString();
    } else if (data['clinicAddress'] is String) {
      _addressController.text = data['clinicAddress'].toString();
    }
    if (data['city'] is String) {
      _cityController.text = data['city'].toString();
    }
    if (data['phone'] is String) {
      _phoneController.text = data['phone'].toString();
    } else if (data['mobile'] is String) {
      _phoneController.text = data['mobile'].toString();
    }
    if (data['email'] is String) {
      _emailController.text = data['email'].toString();
    }
    if (data['experienceYears'] != null) {
      _experienceController.text = data['experienceYears'].toString();
    }
    if (data['gender'] is String) {
      _genderController.text = data['gender'].toString();
    }
    if (data['bloodGroup'] is String) {
      _bloodGroupController.text = data['bloodGroup'].toString();
    }
    if (data['vehicleNumber'] is String) {
      _vehicleNumberController.text = data['vehicleNumber'].toString();
    }
  }

  Map<String, dynamic> _collectFormData() {
    return {
      'name': _nameController.text.trim(),
      'displayName': _nameController.text.trim(),
      'specialization': _specializationController.text.trim(),
      'qualification': _qualificationController.text.trim(),
      'registrationNumber': _regNumberController.text.trim(),
      'licenseNumber': _regNumberController.text.trim(),
      'facilityName': _facilityNameController.text.trim(),
      'clinicName': _facilityNameController.text.trim(),
      'storeName': _facilityNameController.text.trim(),
      'labName': _facilityNameController.text.trim(),
      'serviceName': _facilityNameController.text.trim(),
      'driverName': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'clinicAddress': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
      'experienceYears': _experienceController.text.trim(),
      'gender': _genderController.text.trim(),
      'bloodGroup': _bloodGroupController.text.trim(),
      'vehicleNumber': _vehicleNumberController.text.trim(),
    };
  }

  /// Saves current draft and exits without clearing entered fields.
  Future<void> _saveDraftAndClose() async {
    final data = _collectFormData();
    await ProfileDraftStore.instance.saveDraft(
      role: widget.role,
      userIdOrPhone: _userId,
      data: data,
    );
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _submitProfile() async {
    final name = _nameController.text.trim();
    final nameError = NameValidator.validate(name);
    if (nameError != null) {
      setState(() => _errorMessage = nameError);
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final data = _collectFormData();
      final id = _userId;
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (FirebaseBootstrap.isReady) {
        final db = FirebaseFirestore.instance;
        final batch = db.batch();

        // 1. Update user document
        if (uid != null && uid.isNotEmpty) {
          final userRef = db.collection(FirestorePaths.users).doc(uid);
          batch.set(
            userRef,
            {
              'displayName': name,
              'name': name,
              'profileCompleted': true,
              'profileCompletionStatus': 'complete',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        // 2. Update role domain document
        final domainCollection = _collectionForRole();
        if (id.isNotEmpty) {
          final domainRef = db.collection(domainCollection).doc(id);
          batch.set(
            domainRef,
            {
              ...data,
              'profileCompleted': true,
              'profileCompletionStatus': 'complete',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit();
      }

      // 3. Clear draft now that profile is saved
      await ProfileDraftStore.instance.clearDraft(
        role: widget.role,
        userIdOrPhone: id,
      );

      // 4. Update in-memory session singletons
      switch (widget.role) {
        case UserType.doctor:
          DoctorSession.setDoctor(id: id, name: name);
          DoctorProfileStore.instance.updateProfile(
            fullName: name,
            specialization: _specializationController.text.trim(),
            registrationNumber: _regNumberController.text.trim(),
            city: _cityController.text.trim(),
            addressLine1: _addressController.text.trim(),
          );
        case UserType.patient:
          PatientSession.setPatient(id: id, name: name);
          PatientProfileMock.profile.name = name;
          if (_genderController.text.isNotEmpty) {
            PatientProfileMock.profile.gender = _genderController.text.trim();
          }
          if (_bloodGroupController.text.isNotEmpty) {
            PatientProfileMock.profile.bloodGroup =
                _bloodGroupController.text.trim();
          }
          PatientProfileMock.notifyProfileUpdated();
        case UserType.medical:
        case UserType.medicalStore:
          final storeLabel = _facilityNameController.text.trim().isNotEmpty
              ? _facilityNameController.text.trim()
              : name;
          MedicalStoreSession.setStore(id: id, name: storeLabel);
        case UserType.lab:
          final labLabel = _facilityNameController.text.trim().isNotEmpty
              ? _facilityNameController.text.trim()
              : name;
          LabSession.setLab(id: id, name: labLabel);
        case UserType.ambulance:
          final sName = _facilityNameController.text.trim().isNotEmpty
              ? _facilityNameController.text.trim()
              : name;
          await AmbulanceSession.setAmbulance(
            id: id,
            serviceName: sName,
            driverName: name,
          );
          final existingAmb = AmbulanceStore.instance.findAmbulance(id);
          if (existingAmb != null) {
            AmbulanceStore.instance.updateRegisteredAmbulance(
              existingAmb.copyWith(
                driverName: name,
                serviceName: sName,
                vehicleNumber: _vehicleNumberController.text.trim(),
                licenseNumber: _regNumberController.text.trim(),
                city: _cityController.text.trim(),
                addressLine1: _addressController.text.trim(),
              ),
            );
          }
        case UserType.superAdmin:
          AppSession.setSuperAdmin(id: id, name: name);
      }

      // 5. Notify ProfileCompletionService
      if (uid != null && uid.isNotEmpty) {
        await ProfileCompletionService.instance.markComplete(
          role: widget.role,
          uid: uid,
          profileId: id,
        );
      }

      if (!mounted) return;

      AppToast.success(
        context,
        widget.isEditing
            ? 'Profile updated successfully!'
            : 'Profile completed! All features unlocked.',
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
      AppToast.error(context, _errorMessage ?? 'Could not save profile.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.screenWidth(context) >= 800;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveDraftAndClose();
      },
      child: isDesktop ? _buildDesktopDialog() : _buildMobileScaffold(),
    );
  }

  Widget _buildDesktopDialog() {
    final isDark = AppColors.isDark(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 720,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.90,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? AppColors.borderOf(context)
                  : Colors.white.withValues(alpha: 0.90),
            ),
            boxShadow: AuthBrandTheme.desktopCardShadows(
              context,
              accent: _accentColor,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                _buildHeaderBar(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 36,
                            vertical: 24,
                          ),
                          child: _buildForm(),
                        ),
                ),
                _buildFooterBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold() {
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeaderBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildForm(),
                    ),
            ),
            _buildFooterBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    final roleLabel = UnifiedAuthCoordinator.roleLabel(widget.role);
    final title = widget.isEditing ? 'Edit Profile' : 'Complete Your Profile';
    final subtitle = widget.isEditing
        ? 'Update your $roleLabel details'
        : 'Fill in your professional details to unlock full access';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accentColor,
                  Color.lerp(_accentColor, Colors.white, 0.25)!
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_roleIcon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saveDraftAndClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close (Draft saved)',
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Common Full Name (Required)
          _buildField(
            controller: _nameController,
            label: widget.role == UserType.doctor
                ? 'Full Name (e.g. Dr. Rahul Sharma)'
                : 'Full Name',
            hint: 'Your real full name',
            icon: Icons.person_outline_rounded,
            required: true,
          ),
          const SizedBox(height: 16),

          // Role-specific fields
          if (widget.role == UserType.doctor) ...[
            _buildSpecializationField(),
            const SizedBox(height: 16),
            _buildDoctorQualificationField(),
            const SizedBox(height: 16),
            _buildField(
              controller: _regNumberController,
              label: 'Medical Council Reg. Number',
              hint: 'e.g. MMC-123456',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _facilityNameController,
              label: 'Clinic / Hospital Name',
              hint: 'e.g. City Health Clinic',
              icon: Icons.domain_outlined,
            ),
            const SizedBox(height: 16),
            _buildExperienceField(),
            const SizedBox(height: 16),
          ],

          if (widget.role == UserType.patient) ...[
            _buildPatientGenderField(),
            const SizedBox(height: 16),
            _buildPatientBloodGroupField(),
            const SizedBox(height: 16),
          ],

          if (widget.role == UserType.medical ||
              widget.role == UserType.medicalStore) ...[
            _buildField(
              controller: _facilityNameController,
              label: widget.role == UserType.medical
                  ? 'Medical Store / Business Name'
                  : 'Pharmacy Name',
              hint: 'e.g. Apollo Pharmacy, Lifeline Medicals',
              icon: Icons.storefront_outlined,
              required: true,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _regNumberController,
              label: 'Drug / Trade License Number',
              hint: 'e.g. DL-20B-123456',
              icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 16),
          ],

          if (widget.role == UserType.lab) ...[
            _buildField(
              controller: _facilityNameController,
              label: 'Diagnostic Lab Name',
              hint: 'e.g. Apex Diagnostics, City Path Labs',
              icon: Icons.biotech_outlined,
              required: true,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _regNumberController,
              label: 'Accreditation / License Number',
              hint: 'e.g. LAB-NABL-7890',
              icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 16),
          ],

          if (widget.role == UserType.ambulance) ...[
            _buildField(
              controller: _facilityNameController,
              label: 'Ambulance Service Name',
              hint: 'e.g. Rapid Care Ambulance Fleet',
              icon: Icons.emergency_outlined,
              required: true,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _vehicleNumberController,
              label: 'Vehicle Registration Number',
              hint: 'e.g. MH 12 AB 1234',
              icon: Icons.directions_car_outlined,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _regNumberController,
              label: 'Driver / Commercial License Number',
              hint: 'e.g. DL-MH-12345678',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
          ],

          // Common Address & Contact
          _buildField(
            controller: _addressController,
            label: 'Address',
            hint: 'Street, Area, Building',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 16),
          _buildField(
            controller: _cityController,
            label: 'City',
            hint: 'e.g. Mumbai, Pune, Delhi',
            icon: Icons.location_city_outlined,
          ),
          const SizedBox(height: 16),
          _buildField(
            controller: _emailController,
            label: 'Contact Email',
            hint: 'e.g. contact@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
    );
  }

  Widget _buildSpecializationField() {
    final specializations = [
      ...AppConstants.allSpecializations,
      'Other',
    ];
    final currentVal = _specializationController.text.trim();
    final isInList = specializations.contains(currentVal);
    final isOtherSelected =
        _specializationIsOther || (!isInList && currentVal.isNotEmpty);
    if (!isInList &&
        currentVal.isNotEmpty &&
        _customSpecializationController.text.isEmpty) {
      _customSpecializationController.text = currentVal;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchableDropdownFormField(
          title: 'Specialization',
          value: isOtherSelected ? 'Other' : (isInList ? currentVal : null),
          items: specializations,
          decoration: InputDecoration(
            labelText: 'Specialization *',
            hintText: 'Select your medical specialization',
            prefixIcon: Icon(
              Icons.medical_services_outlined,
              size: 20,
              color: _accentColor,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _accentColor, width: 2),
            ),
          ),
          onChanged: (val) {
            setState(() {
              if (val == 'Other') {
                _specializationIsOther = true;
                _specializationController.text =
                    _customSpecializationController.text.trim();
              } else {
                _specializationIsOther = false;
                _specializationController.text = val ?? '';
              }
            });
            _scheduleDraftSave();
          },
          validator: (val) {
            if (_specializationController.text.trim().isEmpty) {
              return 'Specialization is required';
            }
            return null;
          },
        ),
        if (isOtherSelected) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _customSpecializationController,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: AppColors.textPrimaryOf(context),
            ),
            decoration: InputDecoration(
              labelText: 'Specify Specialization *',
              hintText: 'Enter your specialization',
              prefixIcon:
                  Icon(Icons.edit_outlined, size: 20, color: _accentColor),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accentColor, width: 2),
              ),
            ),
            onChanged: (text) {
              _specializationController.text = text.trim();
              _scheduleDraftSave();
            },
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your specialization';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDoctorQualificationField() {
    return QualificationSelector(
      initialValue: _qualificationController.text.isNotEmpty
          ? _qualificationController.text
          : null,
      label: 'Highest Qualification',
      isRequired: true,
      accentColor: _accentColor,
      prefixIcon: Icon(Icons.school_outlined, size: 20, color: _accentColor),
      onChanged: (val) {
        _qualificationController.text = val ?? '';
        _scheduleDraftSave();
      },
    );
  }

  Widget _buildExperienceField() {
    const expList = [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '12',
      '15',
      '20',
      '25',
      '30+',
      'Other',
    ];
    final currentText = _experienceController.text.trim();
    String? matchedOption;
    if (expList.contains(currentText)) {
      matchedOption = currentText;
    } else if (currentText.isNotEmpty) {
      matchedOption = 'Other';
      if (_customExperienceController.text.isEmpty) {
        _customExperienceController.text = currentText;
      }
    } else if (_selectedExperienceOption != null) {
      matchedOption = _selectedExperienceOption;
    }

    final isOther = matchedOption == 'Other';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: matchedOption,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Years of Experience',
            hintText: 'Select years of experience',
            prefixIcon: Icon(
              Icons.work_history_outlined,
              size: 20,
              color: _accentColor,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _accentColor, width: 2),
            ),
          ),
          items: expList.map((e) {
            final label = switch (e) {
              '0' => '0 years (Fresher / Resident)',
              '1' => '1 year',
              'Other' => 'Other (Specify)',
              _ => '$e years',
            };
            return DropdownMenuItem<String>(
              value: e,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedExperienceOption = val;
              if (val == 'Other') {
                _experienceController.text =
                    _customExperienceController.text.trim();
              } else {
                _experienceController.text = val ?? '';
              }
            });
            _scheduleDraftSave();
          },
        ),
        if (isOther) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _customExperienceController,
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: AppColors.textPrimaryOf(context),
            ),
            decoration: InputDecoration(
              labelText: 'Specify Experience (Years)',
              hintText: 'e.g. 14',
              prefixIcon:
                  Icon(Icons.edit_outlined, size: 20, color: _accentColor),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accentColor, width: 2),
              ),
            ),
            onChanged: (val) {
              _experienceController.text = val.trim();
              _scheduleDraftSave();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPatientGenderField() {
    final genderList = AppConstants.genders;
    final currentText = _genderController.text.trim();
    String? matchedOption;
    if (genderList.contains(currentText)) {
      matchedOption = currentText;
    } else if (currentText.isNotEmpty) {
      matchedOption = 'Other';
      if (_customGenderController.text.isEmpty) {
        _customGenderController.text = currentText;
      }
    } else if (_selectedGenderOption != null) {
      matchedOption = _selectedGenderOption;
    }

    final isOther = matchedOption == 'Other';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: matchedOption,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Gender',
            hintText: 'Select gender',
            prefixIcon: Icon(Icons.wc_rounded, size: 20, color: _accentColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _accentColor, width: 2),
            ),
          ),
          items: genderList.map((g) {
            return DropdownMenuItem<String>(
              value: g,
              child: Text(
                g,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedGenderOption = val;
              if (val == 'Other' &&
                  _customGenderController.text.trim().isNotEmpty) {
                _genderController.text = _customGenderController.text.trim();
              } else {
                _genderController.text = val ?? '';
              }
            });
            _scheduleDraftSave();
          },
        ),
        if (isOther) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _customGenderController,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: AppColors.textPrimaryOf(context),
            ),
            decoration: InputDecoration(
              labelText: 'Specify Gender (Optional)',
              hintText: 'e.g. Non-binary, Prefer not to say',
              prefixIcon:
                  Icon(Icons.edit_outlined, size: 20, color: _accentColor),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _accentColor, width: 2),
              ),
            ),
            onChanged: (val) {
              final trimmed = val.trim();
              _genderController.text = trimmed.isNotEmpty ? trimmed : 'Other';
              _scheduleDraftSave();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPatientBloodGroupField() {
    final bloodGroups = [...AppConstants.bloodGroups, 'Other'];
    final currentText = _bloodGroupController.text.trim();
    String? matchedOption;
    if (bloodGroups.contains(currentText)) {
      matchedOption = currentText;
    } else if (currentText.isNotEmpty) {
      matchedOption = 'Other';
    }

    return DropdownButtonFormField<String>(
      initialValue: matchedOption,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Blood Group',
        hintText: 'Select blood group',
        prefixIcon:
            Icon(Icons.bloodtype_outlined, size: 20, color: _accentColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accentColor, width: 2),
        ),
      ),
      items: bloodGroups.map((bg) {
        return DropdownMenuItem<String>(
          value: bg,
          child: Text(
            bg,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        );
      }).toList(),
      onChanged: (val) {
        setState(() {
          _bloodGroupController.text = val ?? '';
        });
        _scheduleDraftSave();
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        color: AppColors.textPrimaryOf(context),
      ),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: _accentColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accentColor, width: 2),
        ),
      ),
      onChanged: (_) {
        // Auto-persist draft with debouncing
        _scheduleDraftSave();
      },
    );
  }

  Timer? _draftTimer;

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () {
      final data = _collectFormData();
      ProfileDraftStore.instance.saveDraft(
        role: widget.role,
        userIdOrPhone: _userId,
        data: data,
      );
    });
  }

  Widget _buildFooterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: _saveDraftAndClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save as Draft'),
          ),
          const SizedBox(width: 14),
          FilledButton(
            onPressed: _saving ? null : _submitProfile,
            style: FilledButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.isEditing ? 'Save Changes' : 'Save & Continue',
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
