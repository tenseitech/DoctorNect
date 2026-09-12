import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/enums/user_type.dart';

class AuthLoginFeature {
  const AuthLoginFeature(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

/// Role-specific copy and highlights for revamped login layouts.
class AuthLoginBranding {
  const AuthLoginBranding({
    required this.features,
    this.gradientDarken = 0.52,
    this.footerNote = 'Encrypted · Secure · Trusted',
  });

  final List<AuthLoginFeature> features;
  final double gradientDarken;
  final String footerNote;

  Color gradientEnd(Color accent) =>
      Color.lerp(accent, const Color(0xFF0A1628), gradientDarken)!;

  static AuthLoginBranding forUserType(UserType type) => switch (type) {
        UserType.superAdmin => superAdmin,
        UserType.doctor => doctor,
        UserType.patient => patient,
        UserType.medicalStore => pharmacy,
        UserType.lab => lab,
        UserType.ambulance => ambulance,
      };

  static const superAdmin = AuthLoginBranding(
    features: [
      AuthLoginFeature(Icons.security_rounded, 'Access Control', 'Manage system roles and permissions'),
      AuthLoginFeature(Icons.verified_user_rounded, 'Verifications', 'Review and approve healthcare providers'),
      AuthLoginFeature(Icons.history_rounded, 'Audit Logs', 'Track administrative activities securely'),
    ],
    footerNote: 'System Administration · Operations Portal',
  );

  static const doctor = AuthLoginBranding(
    features: [
      AuthLoginFeature(Icons.calendar_month_outlined, 'Appointments', 'Manage your daily schedule'),
      AuthLoginFeature(Icons.people_outline_rounded, 'Patients', 'Records and history in one place'),
      AuthLoginFeature(AppIcons.prescription, 'Prescriptions', 'Issue digital scripts quickly'),
    ],
    footerNote: 'HIPAA-aware · Encrypted · Secure',
  );

  static const patient = AuthLoginBranding(
    features: [
      AuthLoginFeature(Icons.person_search_outlined, 'Find doctors', 'Book trusted specialists nearby'),
      AuthLoginFeature(Icons.folder_shared_outlined, 'Health records', 'Prescriptions and visits in one place'),
      AuthLoginFeature(Icons.family_restroom_outlined, 'Family profiles', 'Manage care for loved ones'),
    ],
  );

  static const pharmacy = AuthLoginBranding(
    features: [
      AuthLoginFeature(AppIcons.prescription, 'Prescriptions', 'Receive and dispense orders'),
      AuthLoginFeature(Icons.inventory_2_outlined, 'Inventory', 'Track stock and fulfilments'),
      AuthLoginFeature(Icons.storefront_outlined, 'Store dashboard', 'Connect with doctors and patients'),
    ],
  );

  static const lab = AuthLoginBranding(
    features: [
      AuthLoginFeature(Icons.biotech_outlined, 'Test orders', 'Manage incoming lab requests'),
      AuthLoginFeature(Icons.assignment_outlined, 'Reports', 'Upload and share results quickly'),
      AuthLoginFeature(Icons.hub_outlined, 'Doctor network', 'Stay connected with referring doctors'),
    ],
  );

  static const ambulance = AuthLoginBranding(
    features: [
      AuthLoginFeature(Icons.emergency_outlined, 'Emergency dispatch', 'Respond to patient requests fast'),
      AuthLoginFeature(Icons.my_location_outlined, 'Live availability', 'Stay online when you are on duty'),
      AuthLoginFeature(Icons.directions_car_filled_outlined, 'Driver dashboard', 'Manage trips and service status'),
    ],
    gradientDarken: 0.55,
  );
}
