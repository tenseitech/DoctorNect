import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/specialty_categories.dart';
import '../../../core/data/shared_appointments_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'patient_favorites_store.dart';
import 'registered_doctors_store.dart';

/// Static UI config + live data from Firestore-backed stores.
class PatientMockData {
  static PatientContext patient = const PatientContext(name: '', city: '');

  static const cities = [
    'Mumbai',
    'Pune',
    'Nagpur',
    'Nashik',
    'Aurangabad',
    'Solapur',
    'Amravati',
    'Kolhapur',
    'Sangli',
    'Satara',
    'Jalgaon',
    'Akola',
    'Latur',
    'Nanded',
    'Chandrapur',
    'Dhule',
    'Ahmednagar',
    'Ratnagiri',
    'Wardha',
    'Yavatmal',
    'Buldhana',
    'Osmanabad',
    'Parbhani',
    'Beed',
    'Hingoli',
    'Washim',
    'Gadchiroli',
    'Gondia',
    'Bhandara',
    'Nandurbar',
  ];

  static List<SpecialityShortcut> get specialityShortcuts => [
        for (final label in specialtyCategories.keys)
          SpecialityShortcut(label: label, icon: _iconForCategory(label)),
      ];

  static IconData _iconForCategory(String label) {
    final l = label.toLowerCase();
    if (l.contains('skin') || l.contains('hair') || l.contains('nail')) {
      return Icons.face_retouching_natural_outlined;
    }
    if (l.contains('heart') || l.contains('blood vessel'))
      return Icons.favorite_outline;
    if (l.contains('women')) return Icons.pregnant_woman_outlined;
    if (l.contains('child') || l.contains('pediatr')) {
      return AppIcons.childCare.data;
    }
    if (l.contains('bone') || l.contains('joint') || l.contains('muscle')) {
      return AppIcons.boneAndJoint.data;
    }
    if (l.contains('mental')) return Icons.psychology_outlined;
    if (l.contains('ent') ||
        l.contains('ear') ||
        l.contains('nose') ||
        l.contains('throat')) {
      return Icons.hearing_outlined;
    }
    if (l.contains('dental')) return Icons.emoji_emotions_outlined;
    if (l.contains('eye')) return Icons.visibility_outlined;
    if (l.contains('diagnostic') || l.contains('lab'))
      return Icons.biotech_outlined;
    if (l.contains('surgery')) return Icons.content_cut_outlined;
    if (l.contains('brain') || l.contains('nervous'))
      return Icons.psychology_alt_outlined;
    if (l.contains('stomach') || l.contains('digest')) {
      return Icons.medical_services_outlined;
    }
    if (l.contains('kidney') || l.contains('urolog'))
      return Icons.water_drop_outlined;
    if (l.contains('lung') || l.contains('breath')) return Icons.air_outlined;
    if (l.contains('diabetes') || l.contains('hormone'))
      return Icons.bloodtype_outlined;
    if (l.contains('cancer')) return Icons.health_and_safety_outlined;
    if (l.contains('emergency') || l.contains('critical'))
      return Icons.local_hospital_outlined;
    if (l.contains('ayush') ||
        l.contains('alternative') ||
        l.contains('traditional')) {
      return Icons.spa_outlined;
    }
    if (l.contains('physio') || l.contains('rehab'))
      return Icons.self_improvement_outlined;
    if (l.contains('nutrition') || l.contains('lifestyle'))
      return Icons.restaurant_menu_outlined;
    if (l.contains('pain') || l.contains('palliative'))
      return Icons.healing_outlined;
    if (l.contains('elderly')) return Icons.elderly_outlined;
    if (l.contains('infection') || l.contains('immunity'))
      return Icons.coronavirus_outlined;
    if (l.contains('general') || l.contains('preventive'))
      return Icons.medical_services_outlined;
    return Icons.medical_services_outlined;
  }

  static const carouselItems = [
    HomeCarouselItem(
      banner: PromoBanner(
        kind: HomeCarouselKind.productAd,
        title: 'DoctorNect Health Kit',
        subtitle: 'Get 20% off on your first First-Aid kit purchase!',
        gradientColors: [Color(0xFF1D4ED8), Color(0xFF3730A3)],
        icon: Icons.medical_services_outlined,
      ),
      ctaLabel: 'Learn more',
      ctaRoute: 'help',
    ),
    HomeCarouselItem(
      banner: PromoBanner(
        kind: HomeCarouselKind.productAd,
        title: 'Full Body Checkup',
        subtitle:
            'Book a comprehensive body checkup today from available labs.',
        gradientColors: [Color(0xFF6D28D9), Color(0xFF4C1D95)],
        icon: Icons.biotech_outlined,
      ),
      ctaLabel: 'Book Lab Test',
      ctaRoute: 'lab',
    ),
  ];

  static List<PromoBanner> get banners =>
      carouselItems.map((item) => item.banner).toList(growable: false);

  static const services = [
    ServiceItem(
      label: 'Medical Record',
      icon: TablerIcons.file_description,
      route: 'records',
      assetPath: 'assets/images/services/records.png',
    ),
    ServiceItem(
      label: 'SOS',
      icon: Icons.emergency_rounded,
      route: 'sos',
      assetPath: 'assets/images/services/sos.png',
    ),
    ServiceItem(
      label: 'Digital Pass',
      icon: Icons.badge_rounded,
      route: 'digital-pass',
    ),
  ];

  static List<MyDoc> get myDocs =>
      PatientFavoritesStore.instance.visibleDoctors();

  static List<MyDoc> doctorsInCity(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final docs = <MyDoc>[];
    for (final doctor in RegisteredDoctorsStore.instance.searchableDoctors) {
      if (doctor.area.trim().toLowerCase() != normalized) continue;
      docs.add(
        MyDoc(
          id: doctor.id,
          name: doctor.name,
          specialization: doctor.specialization,
          rating: doctor.rating,
          reviewCount: doctor.reviewCount,
          city: doctor.area,
          photoUrl: doctor.photoUrl,
          photoPath: doctor.photoPath,
        ),
      );
      if (docs.length >= 8) break;
    }
    return docs;
  }

  static List<RecentAppointment> get recentAppointments {
    final completed = SharedAppointmentsStore.instance
        .patientAppointments()
        .where((a) =>
            a.cancellationReason == null && a.dateTime.isBefore(DateTime.now()))
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return completed.take(3).map((a) {
      return RecentAppointment(
        doctorName: 'Dr. ${a.doctorName}',
        date: a.dateTime,
        status: AppointmentStatusPatient.completed,
        doctorId: a.doctorId,
      );
    }).toList();
  }

  static const healthTips = [
    HealthTip(title: '5 habits for a healthier heart', category: 'Cardiology'),
    HealthTip(title: 'Managing diabetes in summer', category: 'Wellness'),
    HealthTip(title: 'When to see a dermatologist', category: 'Skin Care'),
  ];

  static List<DoctorListing> get allDoctors =>
      RegisteredDoctorsStore.instance.searchableDoctors;
}
