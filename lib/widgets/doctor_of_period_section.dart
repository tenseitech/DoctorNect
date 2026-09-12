import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/features/doctor/profile/data/doctor_profile_store.dart';
import 'package:medibond/features/patient/booking/booking_flow_screen.dart';
import 'package:medibond/features/patient/data/featured_doctors_service.dart';
import 'package:medibond/features/patient/doctor_profile/patient_doctor_profile_screen.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'package:medibond/widgets/profile_photo_image_io.dart'
    if (dart.library.html) 'package:medibond/widgets/profile_photo_image_stub.dart';

enum DoctorOfPeriodAudience { patient, doctor }

class DoctorOfPeriodSection extends StatefulWidget {
  const DoctorOfPeriodSection({
    super.key,
    this.audience = DoctorOfPeriodAudience.patient,
  });

  final DoctorOfPeriodAudience audience;

  @override
  State<DoctorOfPeriodSection> createState() => _DoctorOfPeriodSectionState();
}

class _DoctorOfPeriodSectionState extends State<DoctorOfPeriodSection> {
  static const _periods = [
    FeaturedDoctorPeriod.day,
    FeaturedDoctorPeriod.week,
    FeaturedDoctorPeriod.month,
    FeaturedDoctorPeriod.year,
  ];

  static const _kVirtualBase = 10000; // start mid-way so left swipe works too
  final PageController _pageController = PageController(initialPage: _kVirtualBase);
  int _currentPage = _kVirtualBase;
  Timer? _autoTimer;
  int _entryCount = 4; // updated each build

  bool get _isPatient => widget.audience == DoctorOfPeriodAudience.patient;

  @override
  void initState() {
    super.initState();
    // Start timer after first frame so PageController is attached
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoSwipe());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSwipe() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_entryCount < 2) return;
      _pageController.animateToPage(
        _currentPage + 1, // always go right — infinite scroll handles wrap
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _openProfile(DoctorListing doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDoctorProfileScreen(doctorId: doctor.id),
      ),
    );
  }

  static List<FeaturedDoctorEntry> _demoEntries() {
    final demos = [
      _makeDemoDoctor('Dr. Aryan Mehta', 'Cardiologist', 'Heart Care Clinic', 'Mumbai', FeaturedDoctorPeriod.day),
      _makeDemoDoctor('Dr. Priya Sharma', 'Dermatologist', 'Skin & Glow Clinic', 'Delhi', FeaturedDoctorPeriod.week),
      _makeDemoDoctor('Dr. Rohit Verma', 'Orthopedic', 'Bone & Joint Centre', 'Pune', FeaturedDoctorPeriod.month),
      _makeDemoDoctor('Dr. Sneha Rao', 'Gynecologist', 'Wellness Hospital', 'Bangalore', FeaturedDoctorPeriod.year),
    ];
    return demos;
  }

  static FeaturedDoctorEntry _makeDemoDoctor(
      String name, String spec, String clinic, String city, FeaturedDoctorPeriod period) {
    return FeaturedDoctorEntry(
      period: period,
      doctor: DoctorListing(
        id: 'demo_${period.index}',
        name: name,
        specialization: spec,
        qualification: 'MBBS, MD',
        experienceYears: 8,
        rating: 4.8,
        reviewCount: 120,
        clinicName: clinic,
        area: city,
        distanceKm: 2.5,
        availability: DoctorAvailability.today,
        nextSlot: '10:00 AM',
        verified: true,
        gender: 'Male',
        languages: const ['English', 'Hindi'],
        addressLine1: city,
        state: 'India',
      ),
      consultationCount: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Collect only periods that have a featured doctor; fall back to demo entries
    var entries = _periods
        .map((p) => FeaturedDoctorsService.featuredFor(p))
        .where((e) => e != null)
        .cast<FeaturedDoctorEntry>()
        .toList();

    if (entries.isEmpty) entries = _demoEntries();
    _entryCount = entries.length;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Featured Doctors',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: isCompact ? 188 : 172,
          child: PageView.builder(
            controller: _pageController,
            itemCount: null, // infinite
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final entry = entries[i % entries.length];
              final doctor = entry.doctor;
              final photo = _resolvePhoto(doctor);
              final address = _resolveAddress(doctor);
              final state = _resolveState(doctor);
              final clinic = doctor.clinicName.trim();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: entry.accent,
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  child: InkWell(
                    onTap: () => _openProfile(doctor),
                    borderRadius:
                        BorderRadius.circular(AppConstants.cardRadius),
                    child: Padding(
                      padding: EdgeInsets.all(isCompact ? 12 : 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _FeaturedDoctorPhoto(
                            displayName: doctor.name,
                            photoPath: photo.path,
                            photoBytes: photo.bytes,
                            photoUrl: photo.url,
                            size: isCompact ? 58 : 72,
                          ),
                          SizedBox(width: isCompact ? 10 : 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.title.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Dr. ${doctor.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: isCompact ? 15 : 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  doctor.specialization,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                                if (clinic.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  _InfoRow(
                                      icon: Icons.local_hospital_outlined,
                                      text: clinic),
                                ],
                                if (address.isNotEmpty)
                                  _InfoRow(
                                      icon: Icons.location_on_outlined,
                                      text: address),
                                if (state.isNotEmpty)
                                  _InfoRow(
                                      icon: Icons.map_outlined, text: state),
                                const SizedBox(height: 2),
                                Row(children: [
                                  const Icon(Icons.star,
                                      size: 13,
                                      color: Color(0xFFFDE047)),
                                  Flexible(
                                    child: Text(
                                      ' ${doctor.rating} · ${entry.subtitle}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isPatient) ...[
                                IconButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BookingFlowScreen(
                                          doctorId: doctor.id),
                                    ),
                                  ),
                                  icon: const Icon(Icons.calendar_month,
                                      color: Colors.white, size: 18),
                                  tooltip: 'Book',
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppColors.white.withValues(alpha: 0.22),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 8 : 10,
                                  vertical: isCompact ? 5 : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isCompact ? 'Profile' : 'View profile',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(Icons.arrow_forward_rounded,
                                        size: 12, color: Colors.white),
                                  ],
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
            },
          ),
        ),
        // Dot indicators
        if (entries.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(entries.length, (i) {
              final active = i == _currentPage % entries.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? (_isPatient
                          ? AppColors.patientTeal
                          : AppColors.doctorBlue)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  _FeaturedPhotoData _resolvePhoto(DoctorListing doctor) {
    if (doctor.id == DoctorSession.loggedInDoctorId) {
      final profile = DoctorProfileStore.instance.profile;
      if (profile.photoBytes != null && profile.photoBytes!.isNotEmpty) {
        return _FeaturedPhotoData(bytes: profile.photoBytes);
      }
      if (profile.photoPath != null && profile.photoPath!.trim().isNotEmpty) {
        return _FeaturedPhotoData(path: profile.photoPath);
      }
    }
    if (doctor.photoUrl != null && doctor.photoUrl!.trim().isNotEmpty) {
      return _FeaturedPhotoData(url: doctor.photoUrl);
    }
    if (doctor.photoPath != null && doctor.photoPath!.trim().isNotEmpty) {
      return _FeaturedPhotoData(path: doctor.photoPath);
    }
    return const _FeaturedPhotoData();
  }

  String _resolveAddress(DoctorListing doctor) {
    if (doctor.addressLine1.trim().isNotEmpty) return doctor.addressLine1.trim();
    if (doctor.id == DoctorSession.loggedInDoctorId) {
      final profile = DoctorProfileStore.instance.profile;
      if (profile.addressLine1.trim().isNotEmpty) return profile.addressLine1.trim();
      if (profile.landmark.trim().isNotEmpty) return profile.landmark.trim();
    }
    if (doctor.area.trim().isNotEmpty) return doctor.area.trim();
    return '';
  }

  String _resolveState(DoctorListing doctor) {
    if (doctor.state.trim().isNotEmpty) return doctor.state.trim();
    if (doctor.id == DoctorSession.loggedInDoctorId) {
      final profile = DoctorProfileStore.instance.profile;
      if (profile.state.trim().isNotEmpty) return profile.state.trim();
      if (profile.stateCouncil.trim().isNotEmpty) return profile.stateCouncil.trim();
    }
    return '';
  }
}

class _FeaturedPhotoData {
  const _FeaturedPhotoData({this.path, this.bytes, this.url});

  final String? path;
  final Uint8List? bytes;
  final String? url;
}

class _FeaturedDoctorPhoto extends StatelessWidget {
  const _FeaturedDoctorPhoto({
    required this.displayName,
    this.photoPath,
    this.photoBytes,
    this.photoUrl,
    this.size = 72,
  });

  final String displayName;
  final String? photoPath;
  final Uint8List? photoBytes;
  final String? photoUrl;
  final double size;

  ImageProvider? get _provider {
    if (photoBytes != null && photoBytes!.isNotEmpty) {
      return MemoryImage(photoBytes!);
    }
    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      return NetworkImage(photoUrl!.trim());
    }
    return profilePhotoFileProvider(photoPath);
  }

  @override
  Widget build(BuildContext context) {
    final image = _provider;
    final initial = displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : 'D';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
        color: Colors.white.withValues(alpha: 0.15),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(image: image, fit: BoxFit.cover)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 28,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                Text(
                  initial,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      ],
    );
  }
}
