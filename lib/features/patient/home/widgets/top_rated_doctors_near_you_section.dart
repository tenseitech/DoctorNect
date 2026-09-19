import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/profile_photo_image_io.dart'
    if (dart.library.html) '../../../../widgets/profile_photo_image_stub.dart';
import '../../booking/booking_flow_screen.dart';
import '../../data/registered_doctors_store.dart';
import '../../doctor_profile/patient_doctor_profile_screen.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../profile/data/patient_profile_mock.dart';
import '../../../../core/theme/app_typography.dart';

/// Promotional banner section on the Patient Home Screen showcasing
/// top-rated verified doctors near the patient's location.
class TopRatedDoctorsNearYouSection extends StatefulWidget {
  const TopRatedDoctorsNearYouSection({super.key});

  @override
  State<TopRatedDoctorsNearYouSection> createState() =>
      _TopRatedDoctorsNearYouSectionState();
}

class _TopRatedDoctorsNearYouSectionState
    extends State<TopRatedDoctorsNearYouSection> {
  static const _kVirtualBase = 10000;
  final PageController _pageController =
      PageController(initialPage: _kVirtualBase);

  int _currentPage = _kVirtualBase;
  Timer? _autoTimer;
  bool _isHovered = false;
  int _doctorCount = 0;

  @override
  void initState() {
    super.initState();
    RegisteredDoctorsStore.instance.addListener(_onStoreChanged);
    PatientProfileMock.listenable.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoSwipe());
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    RegisteredDoctorsStore.instance.removeListener(_onStoreChanged);
    PatientProfileMock.listenable.removeListener(_onStoreChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSwipe() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients || _isHovered) return;
      if (_doctorCount < 2) return;
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoSwipe() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _step(int delta) {
    if (_doctorCount < 2 || !_pageController.hasClients) return;
    _pageController.animateToPage(
      _currentPage + delta,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  List<DoctorListing> _getTopRatedNearbyDoctors() {
    final allVerified = RegisteredDoctorsStore.instance.verifiedDoctors;
    if (allVerified.isEmpty) return const [];

    final address = PatientProfileMock.profileAddress;
    final patientCity = (address.city.isNotEmpty
            ? address.city
            : PatientProfileMock.profileCity)
        .trim()
        .toLowerCase();
    final patientState = address.state.trim().toLowerCase();
    final patientArea = '${address.addressLine1} ${address.addressLine2} ${address.landmark}'.trim().toLowerCase();

    List<DoctorListing> nearby;
    if (patientCity.isNotEmpty) {
      nearby = allVerified.where((d) {
        final dCity = d.city.trim().toLowerCase();
        final dArea = d.area.trim().toLowerCase();
        final dAddress = d.addressLine1.trim().toLowerCase();
        final dState = d.state.trim().toLowerCase();

        return dCity.contains(patientCity) ||
            patientCity.contains(dCity) ||
            dArea.contains(patientCity) ||
            (patientArea.isNotEmpty &&
                (dArea.contains(patientArea) ||
                    dAddress.contains(patientArea))) ||
            (patientState.isNotEmpty && dState.contains(patientState));
      }).toList();
    } else {
      // Fallback: if patient location is unconfigured, show top rated platform doctors
      nearby = List.from(allVerified);
    }

    if (nearby.isEmpty) return const [];

    // Ranking logic:
    // 1. Rating descending
    // 2. Break ties using reviewCount descending
    nearby.sort((a, b) {
      final ratingCmp = b.rating.compareTo(a.rating);
      if (ratingCmp != 0) return ratingCmp;
      return b.reviewCount.compareTo(a.reviewCount);
    });

    return nearby.take(8).toList();
  }

  void _openProfile(DoctorListing doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDoctorProfileScreen(doctorId: doctor.id),
      ),
    );
  }

  void _bookDoctor(DoctorListing doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(doctorId: doctor.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _getTopRatedNearbyDoctors();
    _doctorCount = doctors.length;

    if (doctors.isEmpty) {
      return const SizedBox.shrink();
    }

    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final cardHeight = isWide ? 190.0 : 176.0;

    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        _pauseAutoSwipe();
      },
      onExit: (_) {
        _isHovered = false;
        _startAutoSwipe();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.stars_rounded,
                  size: 20,
                  color: Color(0xFF0D9488),
                ),
                const SizedBox(width: 6),
                Text(
                  'Top Rated Doctors Near You',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${doctors.length} Verified',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, i) {
                    final doctor = doctors[i % doctors.length];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _TopRatedDoctorCard(
                        doctor: doctor,
                        isWide: isWide,
                        onTapProfile: () => _openProfile(doctor),
                        onTapBook: () => _bookDoctor(doctor),
                      ),
                    );
                  },
                ),
                if (isWide && doctors.length > 1) ...[
                  Positioned(
                    left: 8,
                    child: _NavButton(
                      icon: Icons.chevron_left,
                      onTap: () => _step(-1),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: _NavButton(
                      icon: Icons.chevron_right,
                      onTap: () => _step(1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (doctors.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(doctors.length, (i) {
                final active = i == _currentPage % doctors.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.patientTeal : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopRatedDoctorCard extends StatelessWidget {
  const _TopRatedDoctorCard({
    required this.doctor,
    required this.isWide,
    required this.onTapProfile,
    required this.onTapBook,
  });

  final DoctorListing doctor;
  final bool isWide;
  final VoidCallback onTapProfile;
  final VoidCallback onTapBook;

  static const _gradients = [
    [Color(0xFF0F766E), Color(0xFF0D9488)],
    [Color(0xFF1E3A8A), Color(0xFF2563EB)],
    [Color(0xFF4C1D95), Color(0xFF7C3AED)],
    [Color(0xFF115E59), Color(0xFF14B8A6)],
  ];

  List<Color> get _gradientColors {
    final index = doctor.id.hashCode.abs() % _gradients.length;
    return _gradients[index];
  }

  String get _displayName {
    final clean = doctor.name.trim();
    if (clean.toLowerCase().startsWith('dr.')) return clean;
    return 'Dr. $clean';
  }

  String get _locationText {
    final parts = <String>[];
    if (doctor.clinicName.trim().isNotEmpty) {
      parts.add(doctor.clinicName.trim());
    }
    final cityOrArea = doctor.area.trim().isNotEmpty
        ? doctor.area.trim()
        : doctor.city.trim();
    if (cityOrArea.isNotEmpty) {
      parts.add(cityOrArea);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final photo = _resolveDoctorPhoto(doctor);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradientColors,
          ),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: [
            BoxShadow(
              color: _gradientColors.first.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTapProfile,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DoctorPhotoAvatar(
                  displayName: doctor.name,
                  photoPath: photo.path,
                  photoUrl: photo.url,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.surfaceOf(context).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 11,
                                  color: AppColors.surfaceOf(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'TOP RATED NEAR YOU',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.surfaceOf(context),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (doctor.distanceKm > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${doctor.distanceKm.toStringAsFixed(1)} km away',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surfaceOf(context),
                        ),
                      ),
                      Text(
                        '${doctor.specialization}${doctor.experienceYears > 0 ? " · ${doctor.experienceYears} yrs exp" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.surfaceOf(context).withValues(alpha: 0.92),
                        ),
                      ),
                      if (_locationText.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: AppColors.surfaceOf(context).withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                _locationText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelSmall,
                                  color: AppColors.surfaceOf(context).withValues(alpha: 0.88),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (doctor.reviewCount > 0) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFFDE047),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${doctor.rating.toStringAsFixed(1)} · ${doctor.reviewCount} ${doctor.reviewCount == 1 ? "review" : "reviews"}',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.surfaceOf(context).withValues(alpha: 0.95),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: onTapBook,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.surfaceOf(context),
                        foregroundColor: _gradientColors.first,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Book',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: onTapProfile,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Profile',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.surfaceOf(context).withValues(alpha: 0.95),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: AppColors.surfaceOf(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoctorPhotoData {
  const _DoctorPhotoData({this.path, this.url});

  final String? path;
  final String? url;
}

_DoctorPhotoData _resolveDoctorPhoto(DoctorListing doctor) {
  if (doctor.photoUrl != null && doctor.photoUrl!.trim().isNotEmpty) {
    return _DoctorPhotoData(url: doctor.photoUrl);
  }
  if (doctor.photoPath != null && doctor.photoPath!.trim().isNotEmpty) {
    return _DoctorPhotoData(path: doctor.photoPath);
  }
  return const _DoctorPhotoData();
}

class _DoctorPhotoAvatar extends StatelessWidget {
  const _DoctorPhotoAvatar({
    required this.displayName,
    this.photoPath,
    this.photoUrl,
  });

  final String displayName;
  final String? photoPath;
  final String? photoUrl;

  ImageProvider? get _provider {
    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      return NetworkImage(photoUrl!.trim());
    }
    return profilePhotoFileProvider(photoPath);
  }

  @override
  Widget build(BuildContext context) {
    final image = _provider;
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : 'D';

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.surfaceOf(context).withValues(alpha: 0.4),
          width: 2,
        ),
        color: AppColors.surfaceOf(context).withValues(alpha: 0.18),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(image: image, fit: BoxFit.cover)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_rounded,
                  size: 28,
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
                ),
                Text(
                  initial,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.surfaceOf(context),
                  ),
                ),
              ],
            ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 20, color: AppColors.textPrimaryOf(context)),
        ),
      ),
    );
  }
}
