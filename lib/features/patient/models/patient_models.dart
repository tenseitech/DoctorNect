import 'package:flutter/material.dart';

enum DoctorAvailability { today, tomorrow, later }

enum AppointmentStatusPatient { upcoming, completed, cancelled }

enum SearchSort { relevance, rating, experience, distance }

class PatientContext {
  const PatientContext({
    required this.name,
    required this.city,
  });

  final String name;
  final String city;
}

class SpecialityShortcut {
  const SpecialityShortcut({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

enum HomeCarouselKind { healthTip, productAd }

class PromoBanner {
  const PromoBanner({
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.gradientColors,
    this.icon,
    this.badgeLabelOverride,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final HomeCarouselKind kind;
  final List<Color> gradientColors;
  final IconData? icon;
  final String? badgeLabelOverride;
  final String? imageUrl;

  String get badgeLabel =>
      badgeLabelOverride ??
      (kind == HomeCarouselKind.healthTip ? 'Health Tip' : 'Sponsored');
}

class HomeCarouselItem {
  const HomeCarouselItem({
    required this.banner,
    this.ctaLabel,
    this.ctaRoute,
  });

  final PromoBanner banner;
  final String? ctaLabel;
  final String? ctaRoute;
}

@Deprecated('Use HomeCarouselItem')
typedef PatientCarouselItem = HomeCarouselItem;

class ServiceItem {
  const ServiceItem({required this.label, required this.icon, required this.route});

  final String label;
  final IconData icon;
  final String route;
}

class MyDoc {
  const MyDoc({
    required this.id,
    required this.name,
    required this.specialization,
    required this.rating,
    required this.reviewCount,
    required this.city,
    this.photoUrl,
    this.photoPath,
  });

  final String id;
  final String name;
  final String specialization;
  final double rating;
  final int reviewCount;
  final String city;
  final String? photoUrl;
  final String? photoPath;
}

class RecentAppointment {
  const RecentAppointment({
    required this.doctorName,
    required this.date,
    required this.status,
    required this.doctorId,
  });

  final String doctorName;
  final DateTime date;
  final AppointmentStatusPatient status;
  final String doctorId;
}

class HealthTip {
  const HealthTip({required this.title, required this.category});

  final String title;
  final String category;
}

class DoctorListing {
  const DoctorListing({
    required this.id,
    required this.name,
    required this.specialization,
    required this.qualification,
    required this.experienceYears,
    required this.rating,
    required this.reviewCount,
    required this.clinicName,
    required this.area,
    required this.distanceKm,
    required this.availability,
    required this.nextSlot,
    required this.verified,
    required this.gender,
    required this.languages,
    this.addressLine1 = '',
    this.state = '',
    this.city = '',
    this.photoPath,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String specialization;
  final String qualification;
  final int experienceYears;
  final double rating;
  final int reviewCount;
  final String clinicName;
  final String area;
  final double distanceKm;
  final DoctorAvailability availability;
  final String nextSlot;
  final bool verified;
  final String gender;
  final List<String> languages;
  final String addressLine1;
  final String state;
  final String city;
  final String? photoPath;
  final String? photoUrl;

  String get locationLabel {
    final parts = <String>[];
    if (addressLine1.trim().isNotEmpty) parts.add(addressLine1.trim());
    if (area.trim().isNotEmpty) parts.add(area.trim());
    if (state.trim().isNotEmpty) parts.add(state.trim());
    if (parts.isEmpty && clinicName.trim().isNotEmpty) parts.add(clinicName.trim());
    return parts.join(', ');
  }
}

class ActiveFilter {
  const ActiveFilter({required this.key, required this.label});

  final String key;
  final String label;
}

class DoctorPatientSummary {
  const DoctorPatientSummary({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.mobile,
    required this.lastVisitDate,
    required this.totalVisits,
    required this.conditions,
    required this.isNew,
    required this.isFollowUp,
  });

  final String id;
  final String name;
  final int age;
  final String gender;
  final String mobile;
  final DateTime lastVisitDate;
  final int totalVisits;
  final List<String> conditions;
  final bool isNew;
  final bool isFollowUp;
}

class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.date,
    required this.diagnosis,
    this.chiefComplaints = const [],
    this.observations = const [],
    this.symptoms = const [],
    this.hasPrescription = false,
    this.hasLabReports = false,
    this.status,
  });
  final String? id;
  final DateTime date;
  final String diagnosis;
  final List<String> chiefComplaints;
  final List<String> observations;
  final List<String> symptoms;
  final bool hasPrescription;
  final bool hasLabReports;
  final dynamic status;
}

enum PatientFileType { prescription, labReport, imaging, dischargeSummary }

class PatientFile {
  const PatientFile({
    required this.id,
    required this.name,
    required this.type,
    required this.date,
  });
  final String id;
  final String name;
  final PatientFileType type;
  final DateTime date;
}

class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

class InsuranceInfo {
  const InsuranceInfo({required this.provider, required this.policyNumber});
  final String provider;
  final String policyNumber;
}

class AllergyRecord {
  const AllergyRecord({required this.name, required this.severity});
  final String name;
  final String severity;
}

class VaccinationRecord {
  const VaccinationRecord({required this.name, required this.date});
  final String name;
  final DateTime date;
}

class SurgeryRecord {
  const SurgeryRecord({required this.procedure, required this.date});
  final String procedure;
  final DateTime date;
}

class MedicationRecord {
  const MedicationRecord({
    required this.name,
    required this.dosage,
    this.frequency = '',
    this.duration = '',
  });
  final String name;
  final String dosage;
  final String frequency;
  final String duration;
}

class DoctorPatientProfile {
  const DoctorPatientProfile({
    required this.summary,
    required this.dateOfBirth,
    required this.bloodGroup,
    required this.email,
    required this.emergencyContact,
    required this.insurance,
    required this.knownConditions,
    required this.allergies,
    required this.surgeries,
    required this.familyHistory,
    required this.currentMedications,
    required this.vaccinations,
    required this.visits,
    required this.files,
  });

  final DoctorPatientSummary summary;
  final DateTime dateOfBirth;
  final String bloodGroup;
  final String email;
  final EmergencyContact emergencyContact;
  final InsuranceInfo insurance;
  final List<String> knownConditions;
  final List<AllergyRecord> allergies;
  final List<SurgeryRecord> surgeries;
  final String familyHistory;
  final List<MedicationRecord> currentMedications;
  final List<VaccinationRecord> vaccinations;
  final List<VisitRecord> visits;
  final List<PatientFile> files;
}


enum PatientSort { lastVisit, name, appointmentCount }


enum PatientFilter { all, returning, newPatient, followUp, dueForVisit, abnormalLabs }
