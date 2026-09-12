import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/legal/medibond_legal_content.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/logout_button.dart';
import '../../../../widgets/image_viewer_dialog.dart';
import '../../../../widgets/profile_photo_avatar.dart';
import '../../patient/profile/about/about_screen.dart';
import '../../patient/profile/widgets/profile_flat_section.dart';
import '../../patient/profile/widgets/profile_web_layout.dart';
import '../pharmacy/doctor_connected_stores_screen.dart';
import '../lab/doctor_connected_labs_screen.dart';
import 'data/doctor_photo_local_store.dart';
import 'data/doctor_profile_store.dart';
import 'models/doctor_profile_data.dart';
import 'sections/account_security_section.dart';
import 'sections/clinic_info_section.dart';
import 'sections/consultation_settings_section.dart';
import 'sections/doctor_add_ambulance_screen.dart';
import 'sections/edit_profile_section.dart';
import 'sections/personal_info_section.dart';
import 'sections/professional_details_section.dart';
import 'sections/data_hub_section.dart';
import 'sections/reviews_section.dart';
import 'widgets/doctor_profile_hero_section.dart';
import 'widgets/doctor_profile_menu_tile.dart';
import 'widgets/doctor_profile_web_layout.dart';
import '../../promoted_ads/screens/promoted_ads_management_screen.dart';

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DoctorProfileScreen()),
    );
  }

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  Uint8List? _localPhotoBytes;

  @override
  void initState() {
    super.initState();
    DoctorProfileStore.instance.addListener(_refresh);
    _loadLocalPhoto();
  }

  @override
  void dispose() {
    DoctorProfileStore.instance.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _loadLocalPhoto() async {
    final profile = DoctorProfileStore.instance.profile;
    if (profile.photoBytes != null && profile.photoBytes!.isNotEmpty) {
      if (mounted) setState(() => _localPhotoBytes = profile.photoBytes);
      return;
    }
    final doctorId = DoctorSession.loggedInDoctorId;
    final bytes = await DoctorPhotoLocalStore.load(doctorId);
    if (bytes != null && bytes.isNotEmpty) {
      DoctorProfileStore.instance.updatePhoto(bytes: bytes);
      if (mounted) setState(() => _localPhotoBytes = bytes);
    }
  }

  void _refresh() => setState(() {});

  Future<void> _pickPhoto() async {
    final profile = DoctorProfileStore.instance.profile;
    ImageProvider? currentImage;
    if (_localPhotoBytes != null && _localPhotoBytes!.isNotEmpty) {
      currentImage = MemoryImage(_localPhotoBytes!);
    } else if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
      currentImage = NetworkImage(profile.photoUrl!);
    }

    final picked = await pickProfilePhoto(
      context,
      hasExisting: currentImage != null,
      onView: () {
        if (currentImage != null) {
          showImageViewerDialog(context, currentImage, title: 'Profile Photo');
        }
      },
      onRemove: () async {
        final doctorId = DoctorSession.activeDoctorId;
        await DoctorProfileStore.instance.removePhoto(doctorId);
        if (mounted) {
          setState(() {
            _localPhotoBytes = null;
          });
          AppToast.info(context, 'Profile photo removed');
        }
      },
    );
    if (picked == null || !picked.hasImage || !mounted) return;
    setState(() {
      DoctorProfileStore.instance.updatePhoto(path: picked.path, bytes: picked.bytes);
      _localPhotoBytes = picked.bytes;
    });

    final bytes = picked.bytes;
    final doctorId = DoctorSession.loggedInDoctorId.isNotEmpty
        ? DoctorSession.loggedInDoctorId
        : (FirebaseAuth.instance.currentUser?.uid ?? '');
    if (bytes != null && bytes.isNotEmpty && doctorId.isNotEmpty) {
      await DoctorPhotoLocalStore.save(doctorId, bytes);
      await DoctorProfileStore.instance.uploadPhotoToServer(doctorId, bytes);
      if (mounted) {
        AppToast.info(context, 'Profile photo updated successfully!');
      }
    }
  }

  Future<void> _openSection(Widget screen) async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (updated == true) _refresh();
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildProfileAvatar({double radius = 38}) {
    final profile = DoctorProfileStore.instance.profile;
    final name = DoctorProfileStore.displayName.isNotEmpty
        ? DoctorProfileStore.displayName
        : DoctorSession.loggedInDoctorName;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'D';
    final localBytes = profile.photoBytes ??
        _localPhotoBytes ??
        DoctorPhotoLocalStore.readCached(DoctorSession.loggedInDoctorId);
    final hasLocalPhoto = localBytes != null && localBytes.isNotEmpty;
    final hasNetworkPhoto =
        !hasLocalPhoto && profile.photoUrl != null && profile.photoUrl!.trim().isNotEmpty;

    ImageProvider? avatarImage;
    if (hasLocalPhoto) {
      avatarImage = MemoryImage(localBytes);
    } else if (hasNetworkPhoto) {
      avatarImage = NetworkImage(profile.photoUrl!.trim());
    }

    final fontSize = radius * 0.74;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D9488), Color(0xFF0369A1)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.patientTeal.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.surfaceOf(context),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Text(
                    initial,
                    style: GoogleFonts.inter(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: AppColors.patientTeal,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(radius > 40 ? 6 : 5),
              decoration: BoxDecoration(
                color: AppColors.patientTeal,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceOf(context), width: 2),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: radius > 40 ? 16 : 14,
                color: AppColors.surfaceOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ProfileWebActionData> _profileWebActions() => [
        ProfileWebActionData(
          icon: Icons.person_outline,
          label: 'Personal Information',
          subtitle: 'Name, contact, languages',
          iconGradient: const [AppColors.doctorBlue, Color(0xFF0F4A82)],
          onTap: () => _openSection(const PersonalInfoSection()),
        ),
        ProfileWebActionData(
          icon: Icons.work_outline,
          label: 'Professional Details',
          subtitle: 'Specialization & certifications',
          iconGradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          onTap: () => _openSection(const ProfessionalDetailsSection()),
        ),
        ProfileWebActionData(
          icon: Icons.local_hospital_outlined,
          label: 'Clinic Information',
          subtitle: 'Address, photos, maps',
          iconGradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
          onTap: () => _openSection(const ClinicInfoSection()),
        ),
        ProfileWebActionData(
          icon: Icons.tune_rounded,
          label: 'Consultation Settings',
          subtitle: 'Duration & booking rules',
          iconGradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
          onTap: () => _openSection(const ConsultationSettingsSection()),
        ),
      ];

  void _openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AboutScreen(
          accentColor: AppColors.doctorBlue,
          audience: LegalAudience.doctor,
        ),
      ),
    );
  }

  List<ProfileWebActionData> _accountWebActions() => [
        ProfileWebActionData(
          icon: Icons.lock_outline,
          label: 'Account & Security',
          subtitle: 'Password & privacy',
          iconGradient: const [Color(0xFF475569), Color(0xFF334155)],
          onTap: () => _openSection(const AccountSecuritySection()),
        ),
        ProfileWebActionData(
          icon: Icons.info_outline,
          label: 'About',
          subtitle: 'App version & legal',
          iconGradient: const [Color(0xFF64748B), Color(0xFF475569)],
          onTap: _openAbout,
        ),
        ProfileWebActionData(
          icon: Icons.person_remove_outlined,
          label: 'Delete Account',
          subtitle: 'Permanently remove data',
          iconGradient: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
          onTap: () => _confirmDeleteAccount(context),
        ),
      ];

  List<ProfileWebActionData> _networkWebActions() => [
        ProfileWebActionData(
          icon: Icons.local_pharmacy_outlined,
          label: 'Connected Medical Stores',
          subtitle: 'Pharmacy network links',
          iconGradient: const [Color(0xFF059669), Color(0xFF047857)],
          onTap: () => _push(const DoctorConnectedStoresScreen()),
        ),
        ProfileWebActionData(
          icon: Icons.biotech_outlined,
          label: 'Connected Labs',
          subtitle: 'Diagnostic lab partners',
          iconGradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
          onTap: () => _push(const DoctorConnectedLabsScreen()),
        ),
        ProfileWebActionData(
          icon: Icons.emergency_outlined,
          label: 'Add Ambulance',
          subtitle: 'Register emergency drivers',
          iconGradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
          onTap: () => _openSection(const DoctorAddAmbulanceScreen()),
        ),
      ];

  List<ProfileWebActionData> _insightsWebActions() {
    final p = DoctorProfileStore.instance.profile;
    return [
      ProfileWebActionData(
        icon: Icons.star_outline,
        label: 'Reviews',
        subtitle: '${p.reviewCount} reviews · ${p.rating.toStringAsFixed(1)}★ avg',
        iconGradient: const [Color(0xFFCA8A04), Color(0xFFA16207)],
        onTap: () => _push(const ReviewsSection()),
      ),
      ProfileWebActionData(
        icon: Icons.insights_outlined,
        label: 'DataHub',
        subtitle: 'Patients & service reports',
        iconGradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
        onTap: () => _push(const DataHubSection()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = DoctorProfileStore.instance.profile;
    final useWebDashboard = !ResponsiveLayout.isCompact(context);

    if (useWebDashboard) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        body: DoctorProfileWebLayout(
          profile: p,
          displayName: DoctorProfileStore.displayNameWithPrefix,
          verificationStatus: DoctorProfileStore.instance.dashboardVerificationStatus,
          avatar: _buildProfileAvatar(radius: 52),
          onPickPhoto: _pickPhoto,
          onEdit: () => _openSection(const EditProfileSection()),
          profileActions: _profileWebActions(),
          accountActions: _accountWebActions(),
          networkActions: _networkWebActions(),
          insightsActions: _insightsWebActions(),
        ),
      );
    }

    return _buildMobileScaffold(p);
  }

  Widget _buildMobileScaffold(DoctorProfileData p) {
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMobileProfileHeader(context),
              Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DoctorProfileHeroSection(
                      profile: p,
                      displayName: DoctorProfileStore.displayNameWithPrefix,
                      verificationStatus: DoctorProfileStore.instance.dashboardVerificationStatus,
                      avatar: _buildProfileAvatar(),
                      onPickPhoto: _pickPhoto,
                      onEdit: () => _openSection(EditProfileSection()),
                    ),
                    Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
                    _buildProfileSection(shaded: true),
                    Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
                    _buildAccountSection(shaded: false),
                    Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
                    _buildAdvertisingSection(shaded: true),
                    _buildNetworkSection(shaded: false),
                    Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
                    _buildInsightsSection(shaded: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      child: Center(child: LogoutTextButton()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileProfileHeader(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BackButton(color: AppColors.textPrimaryOf(context)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your practice & account',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.3,
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

  Widget _buildProfileSection({required bool shaded}) {
    return ProfileFlatSection(
      shaded: shaded,
      title: 'My Profile',
      subtitle: 'Personal, professional & clinic details',
      child: Column(
        children: [
          DoctorProfileMenuTile(
            icon: Icons.person_outline,
            label: 'Personal Information',
            subtitle: 'Name, contact, languages',
            iconGradient: const [AppColors.doctorBlue, Color(0xFF0F4A82)],
            onTap: () => _openSection(const PersonalInfoSection()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.work_outline,
            label: 'Professional Details',
            subtitle: 'Specialization, experience, certifications',
            iconGradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            onTap: () => _openSection(const ProfessionalDetailsSection()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.local_hospital_outlined,
            label: 'Clinic Information',
            subtitle: 'Address, photos, maps',
            iconGradient: const [Color(0xFF0891B2), Color(0xFF0E7490)],
            onTap: () => _openSection(const ClinicInfoSection()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.tune_rounded,
            label: 'Consultation Settings',
            subtitle: 'Duration, booking rules',
            iconGradient: const [Color(0xFFEA580C), Color(0xFFC2410C)],
            onTap: () => _openSection(const ConsultationSettingsSection()),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection({required bool shaded}) {
    return ProfileFlatSection(
      shaded: shaded,
      title: 'Account',
      subtitle: 'Security & app info',
      child: Column(
        children: [
          DoctorProfileMenuTile(
            icon: Icons.lock_outline,
            label: 'Account & Security',
            subtitle: 'Password & privacy',
            iconGradient: const [Color(0xFF475569), Color(0xFF334155)],
            onTap: () => _openSection(const AccountSecuritySection()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.info_outline,
            label: 'About',
            subtitle: 'App version, legal & support',
            iconGradient: const [Color(0xFF64748B), Color(0xFF475569)],
            onTap: _openAbout,
          ),
          DoctorProfileMenuTile(
            icon: Icons.person_remove_outlined,
            label: 'Delete Account',
            subtitle: 'Permanently remove your account and data',
            iconGradient: const [Color(0xFFEF4444), Color(0xFFB91C1C)],
            onTap: () => _confirmDeleteAccount(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvertisingSection({required bool shaded}) {
    return StreamBuilder<BannerConfigModel>(
      stream: BannerConfigService.streamConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data;
        if (config != null && !config.enabled) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            ProfileFlatSection(
              shaded: shaded,
              title: 'Advertising & Promotion',
              subtitle: 'Paid banner ads on Patient Home screen',
              child: Column(
                children: [
                  DoctorProfileMenuTile(
                    icon: TablerIcons.speakerphone,
                    label: 'Promote Banner Ad (Paid Ads)',
                    subtitle: 'Create & manage paid promotional ads on Patient Home',
                    iconGradient: const [Color(0xFF0F766E), Color(0xFF0D9488)],
                    onTap: () {
                      PromotedAdsManagementScreen.open(
                        context,
                        providerType: 'doctor',
                        providerId: DoctorSession.loggedInDoctorId,
                        providerEmail: DoctorProfileStore.instance.profile.email,
                        providerContact: DoctorProfileStore.instance.profile.mobile,
                        isVerified: true,
                      );
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          ],
        );
      },
    );
  }

  Widget _buildNetworkSection({required bool shaded}) {
    return ProfileFlatSection(
      shaded: shaded,
      title: 'Network & Services',
      subtitle: 'Pharmacy, labs & ambulance',
      child: Column(
        children: [
          DoctorProfileMenuTile(
            icon: Icons.local_pharmacy_outlined,
            label: 'Connected Medical Stores',
            subtitle: 'Approve stores & manage pharmacy links',
            iconGradient: const [Color(0xFF059669), Color(0xFF047857)],
            onTap: () => _push(const DoctorConnectedStoresScreen()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.biotech_outlined,
            label: 'Connected Labs',
            subtitle: 'Connect diagnostic labs & send orders',
            iconGradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
            onTap: () => _push(const DoctorConnectedLabsScreen()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.emergency_outlined,
            label: 'Add Ambulance',
            subtitle: 'Register driver & send invite link',
            iconGradient: const [Color(0xFFDC2626), Color(0xFFB91C1C)],
            onTap: () => _openSection(const DoctorAddAmbulanceScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsSection({required bool shaded}) {
    final p = DoctorProfileStore.instance.profile;
    return ProfileFlatSection(
      shaded: shaded,
      title: 'Insights',
      subtitle: 'Reviews & practice analytics',
      child: Column(
        children: [
          DoctorProfileMenuTile(
            icon: Icons.star_outline,
            label: 'Reviews',
            subtitle: '${p.reviewCount} patient reviews · ${p.rating.toStringAsFixed(1)}★ avg',
            iconGradient: const [Color(0xFFCA8A04), Color(0xFFA16207)],
            onTap: () => _push(const ReviewsSection()),
          ),
          DoctorProfileMenuTile(
            icon: Icons.insights_outlined,
            label: 'DataHub',
            subtitle: 'Patients · Pharmacy · Lab · Ambulance reports',
            iconGradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
            onTap: () => _push(const DataHubSection()),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirestoreService.instance.user.deleteAccount(user: user);
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.info(context, 'Failed to delete account: $e');
        }
      }
    }
  }
}
