import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/patient/data/registered_doctors_store.dart';
import '../../../features/patient/doctor_profile/models/doctor_profile_detail.dart';
import '../../data/doctor_patient_stats_service.dart';
import '../../session/doctor_session.dart';
import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';
import '../models/doctor_availability.dart';
import 'doctor_availability_repository.dart';
import 'review_repository.dart';

class DoctorProfileDetailRepository {
  DoctorProfileDetailRepository._();

  static final DoctorProfileDetailRepository instance =
      DoctorProfileDetailRepository._();

  Future<DoctorProfileDetail?> fetch(String doctorId) async {
    final listing = RegisteredDoctorsStore.instance.findById(doctorId);

    Map<String, dynamic>? data;
    if (FirebaseBootstrap.isReady) {
      try {
        final snap = await FirestoreReadHelper.getDocument(
          reference: FirebaseFirestore.instance
              .collection(FirestorePaths.doctors)
              .doc(doctorId),
          preferCache: true,
        );
        if (snap.exists) data = snap.data();
      } catch (_) {}
    }

    if (data == null && listing == null) return null;

    final name = data?['name'] as String? ?? listing?.name ?? 'Doctor';
    final specialization = data?['specialization'] as String? ??
        listing?.specialization ??
        'General Physician';
    final qualification =
        data?['qualification'] as String? ?? listing?.qualification ?? 'MBBS';
    final experienceYears = (data?['experienceYears'] as num?)?.toInt() ??
        listing?.experienceYears ??
        1;
    final rating =
        (data?['rating'] as num?)?.toDouble() ?? listing?.rating ?? 0;
    final reviewCount =
        (data?['reviewCount'] as num?)?.toInt() ?? listing?.reviewCount ?? 0;
    final verified = data?['verified'] as bool? ?? listing?.verified ?? false;
    final languages = (data?['languages'] as List<dynamic>? ??
            listing?.languages ??
            const ['English'])
        .cast<String>();
    final photoUrl = data?['photoUrl'] as String? ??
        data?['photoURL'] as String? ??
        listing?.photoUrl;
    String mobile = data?['mobile'] as String? ?? '';
    if (mobile.isEmpty && data != null && data['ownerUid'] != null) {
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection(FirestorePaths.users)
            .doc(data['ownerUid'] as String)
            .get(const GetOptions(source: Source.cache));
        final userData = userSnap.data();
        if (userData != null && userData['mobile'] != null) {
          final m = userData['mobile'];
          if (m is String) {
            mobile = m;
          } else if (m is Map && m['number'] is String) {
            mobile = m['number'] as String;
          }
        }
        if (mobile.isEmpty) {
          final s2 = await FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(data['ownerUid'] as String)
              .get(const GetOptions(source: Source.server));
          final d2 = s2.data();
          if (d2 != null && d2['mobile'] != null) {
            final m = d2['mobile'];
            if (m is String) {
              mobile = m;
            } else if (m is Map && m['number'] is String) {
              mobile = m['number'] as String;
            }
          }
        }
      } catch (_) {}
    }
    final clinicName =
        data?['clinicName'] as String? ?? listing?.clinicName ?? '$name Clinic';
    final city = data?['city'] as String? ?? listing?.area ?? '';

    String finalAbout;
    final isDoctorViewing = DoctorSession.loggedInDoctorId.isNotEmpty;
    if (isDoctorViewing) {
      final stats =
          DoctorPatientStatsService.statsForDoctor(doctorId, DateTime(2000));
      final defaultAbout = stats.patientsTreated > 0
          ? 'Dr. $name is a highly regarded $specialization who has treated ${stats.patientsTreated} patients on DoctorNect. With $experienceYears+ years of clinical experience, they are dedicated to providing excellent medical care.'
          : 'Dr. $name is a dedicated $specialization with $experienceYears+ years of clinical experience, committed to delivering high-quality healthcare.';
      finalAbout = data?['about'] as String? ?? defaultAbout;
    } else {
      finalAbout = data?['about'] as String? ??
          'Dr. $name is a registered $specialization with $experienceYears+ years of experience.';
    }

    final about = finalAbout;
    final addressLine = data?['addressLine1'] as String?;
    final pincode = data?['pincode'] as String? ?? '';
    final address = addressLine != null && addressLine.isNotEmpty
        ? '$addressLine, $city $pincode'.trim()
        : '$clinicName, $city'.trim();

    DoctorAvailability? availability;
    try {
      availability =
          await DoctorAvailabilityRepository.instance.fetch(doctorId);
    } catch (_) {}

    var reviews = const <PatientDoctorReview>[];
    try {
      reviews = await ReviewRepository.instance.fetchForDoctor(doctorId);
    } catch (_) {}
    final computedRating = reviews.isEmpty
        ? rating
        : reviews.fold<double>(0, (total, review) => total + review.rating) /
            reviews.length;
    final computedReviewCount = reviews.isEmpty ? reviewCount : reviews.length;

    final superSpecialization = data?['superSpecialization'] as String? ?? '';
    final stateCouncil = data?['stateCouncil'] as String? ?? '';
    final councilNumber = data?['councilNumber'] as String? ?? '';
    final certifications = _stringList(data?['certifications']);

    return DoctorProfileDetail(
      id: doctorId,
      name: name,
      specialization: specialization,
      qualification: qualification,
      experienceYears: experienceYears,
      rating: computedRating,
      reviewCount: computedReviewCount,
      verified: verified,
      languages: languages,
      phone: mobile.isNotEmpty ? '+91 $mobile' : 'Contact via clinic',
      about: about,
      specialities: [
        specialization,
        ...superSpecialization
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != specialization),
      ],
      services: const ['Consultation', 'Follow-up', 'Prescription'],
      timings: _timingsFromAvailability(availability),
      education: _educationFromData(data, qualification, certifications),
      pastWorkplaces:
          _pastWorkplacesFromData(data, clinicName: clinicName, city: city),
      awards: _stringList(data?['awards']),
      publications: _stringList(data?['publications']),
      memberships: _membershipsFromData(
        data,
        stateCouncil: stateCouncil,
        councilNumber: councilNumber,
      ),
      reviews: reviews,
      address: address,
      landmark: data?['landmark'] as String? ?? '',
      mapsUrl: data?['mapsLink'] as String? ??
          'https://maps.google.com/?q=${Uri.encodeComponent('$clinicName $city')}',
      nearbyLandmarks: const [],
      clinicName: clinicName,
      area: city,
      photoUrl: photoUrl,
    );
  }

  List<ClinicTiming> _timingsFromAvailability(
      DoctorAvailability? availability) {
    if (availability == null) {
      return const [
        ClinicTiming(day: 'Schedule', hours: 'Check availability when booking')
      ];
    }

    final days = availability.workingDays.join(', ');
    final morning = '${availability.morningStart} – ${availability.morningEnd}';
    final evening = availability.eveningEnabled
        ? '${availability.eveningStart} – ${availability.eveningEnd}'
        : 'Closed';

    return [
      ClinicTiming(day: days, hours: 'Morning: $morning'),
      if (availability.eveningEnabled)
        ClinicTiming(day: days, hours: 'Evening: $evening'),
    ];
  }

  List<EducationEntry> _educationFromData(
    Map<String, dynamic>? data,
    String qualification,
    List<String> certifications,
  ) {
    final raw = data?['education'] as List<dynamic>?;
    if (raw != null && raw.isNotEmpty) {
      return raw.map((item) {
        final map = item as Map<String, dynamic>;
        return EducationEntry(
          degree: map['degree'] as String? ?? qualification,
          college: map['college'] as String? ?? '',
          year: (map['year'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }

    final entries = <EducationEntry>[];
    if (qualification.isNotEmpty) {
      entries.add(EducationEntry(degree: qualification, college: '', year: 0));
    }
    for (final cert in certifications) {
      entries
          .add(EducationEntry(degree: cert, college: 'Certification', year: 0));
    }
    return entries;
  }

  List<String> _pastWorkplacesFromData(
    Map<String, dynamic>? data, {
    required String clinicName,
    required String city,
  }) {
    final saved = _stringList(data?['pastWorkplaces']);
    if (saved.isNotEmpty) return saved;

    final workplace = city.isNotEmpty ? '$clinicName, $city' : clinicName;
    if (workplace.trim().isNotEmpty) return [workplace.trim()];
    return const [];
  }

  List<String> _membershipsFromData(
    Map<String, dynamic>? data, {
    required String stateCouncil,
    required String councilNumber,
  }) {
    final saved = _stringList(data?['memberships']);
    final extras = <String>[
      if (stateCouncil.trim().isNotEmpty) stateCouncil.trim(),
      if (councilNumber.trim().isNotEmpty)
        'Medical council registration: ${councilNumber.trim()}',
    ];
    return [...saved, ...extras];
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }
}
