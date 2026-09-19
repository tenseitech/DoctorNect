import 'package:flutter/material.dart';

import '../../../core/session/doctor_session.dart';
import '../../patient/data/featured_doctors_service.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../profile/data/doctor_profile_store.dart';

abstract final class DoctorHomeCarouselData {
  static const _periods = [
    FeaturedDoctorPeriod.day,
    FeaturedDoctorPeriod.week,
    FeaturedDoctorPeriod.month,
    FeaturedDoctorPeriod.year,
  ];

  static List<HomeCarouselItem> buildItems() {
    final entries = _periods
        .map(FeaturedDoctorsService.featuredFor)
        .whereType<FeaturedDoctorEntry>()
        .toList();

    if (entries.isEmpty) return const [];

    return entries.map(_toCarouselItem).toList();
  }

  static HomeCarouselItem _toCarouselItem(FeaturedDoctorEntry entry) {
    final doctor = entry.doctor;
    final rawName = doctor.name.trim();
    final displayName =
        rawName.toLowerCase().startsWith('dr.') ? rawName : 'Dr. $rawName';

    final clinic = doctor.clinicName.trim();
    final location = _resolveLocation(doctor);
    final detailParts = <String>[
      if (doctor.specialization.trim().isNotEmpty) doctor.specialization.trim(),
      if (clinic.isNotEmpty) clinic,
      if (location.isNotEmpty) location,
    ];

    final subtitle = detailParts.isEmpty
        ? '${doctor.rating}★ · ${entry.subtitle}'
        : '${detailParts.join(' · ')}\n${doctor.rating}★ · ${entry.subtitle}';

    final accent = entry.accent;
    final gradient = [
      accent,
      Color.lerp(accent, const Color(0xFF0F172A), 0.35)!,
    ];

    return HomeCarouselItem(
      banner: PromoBanner(
        kind: HomeCarouselKind.productAd,
        badgeLabelOverride: entry.title,
        title: displayName,
        subtitle: subtitle,
        gradientColors: gradient,
        icon: Icons.person_outline_rounded,
      ),
      ctaLabel: 'View profile',
      ctaRoute: 'featured_doctor:${doctor.id}',
    );
  }

  static String _resolveLocation(DoctorListing doctor) {
    if (doctor.state.trim().isNotEmpty) return doctor.state.trim();
    if (doctor.addressLine1.trim().isNotEmpty)
      return doctor.addressLine1.trim();
    if (doctor.area.trim().isNotEmpty) return doctor.area.trim();
    if (doctor.id == DoctorSession.loggedInDoctorId) {
      final profile = DoctorProfileStore.instance.profile;
      if (profile.state.trim().isNotEmpty) return profile.state.trim();
      if (profile.addressLine1.trim().isNotEmpty)
        return profile.addressLine1.trim();
    }
    return '';
  }
}
