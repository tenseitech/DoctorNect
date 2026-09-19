import '../data/review_edit_policy.dart';

class DoctorProfileDetail {
  const DoctorProfileDetail({
    required this.id,
    required this.name,
    required this.specialization,
    required this.qualification,
    required this.experienceYears,
    required this.rating,
    required this.reviewCount,
    required this.verified,
    required this.languages,
    required this.phone,
    required this.about,
    required this.specialities,
    required this.services,
    required this.timings,
    required this.education,
    required this.pastWorkplaces,
    required this.awards,
    required this.publications,
    required this.memberships,
    required this.reviews,
    required this.address,
    required this.landmark,
    required this.mapsUrl,
    required this.nearbyLandmarks,
    required this.clinicName,
    required this.area,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String specialization;
  final String qualification;
  final int experienceYears;
  final double rating;
  final int reviewCount;
  final bool verified;
  final List<String> languages;
  final String phone;
  final String about;
  final List<String> specialities;
  final List<String> services;
  final List<ClinicTiming> timings;
  final List<EducationEntry> education;
  final List<String> pastWorkplaces;
  final List<String> awards;
  final List<String> publications;
  final List<String> memberships;
  final List<PatientDoctorReview> reviews;
  final String address;
  final String landmark;
  final String mapsUrl;
  final List<String> nearbyLandmarks;
  final String clinicName;
  final String area;
  final String? photoUrl;
}

class ClinicTiming {
  const ClinicTiming({required this.day, required this.hours});

  final String day;
  final String hours;
}

class EducationEntry {
  const EducationEntry({
    required this.degree,
    required this.college,
    required this.year,
  });

  final String degree;
  final String college;
  final int year;
}

class PatientDoctorReview {
  PatientDoctorReview({
    required this.id,
    required this.maskedName,
    required this.rating,
    required this.text,
    required this.date,
    this.patientId,
    this.doctorReply,
    this.helpfulCount = 0,
  });

  final String id;
  final String maskedName;
  final int rating;
  final String text;
  final DateTime date;
  final String? patientId;
  final String? doctorReply;
  int helpfulCount;

  bool canBeEditedBy(String currentPatientId) {
    if (currentPatientId.isEmpty ||
        patientId == null ||
        patientId != currentPatientId) {
      return false;
    }
    return ReviewEditPolicy.withinEditWindow(date);
  }
}
