import '../../../../core/session/patient_session.dart';
import '../../profile/data/patient_profile_mock.dart';

/// Shared age checks for patient lab booking entry points.
abstract final class PatientLabAgeGuard {
  PatientLabAgeGuard._();

  static bool isValidAge(int age) => age > 0 && age <= 120;

  static bool profileAgeValid() => isValidAge(PatientProfileMock.profile.age);

  static String selfAgeLabel() {
    final profile = PatientProfileMock.profile;
    final name = profile.name.isNotEmpty ? profile.name : PatientSession.loggedInPatientName;
    if (isValidAge(profile.age)) return '$name (${profile.age}y)';
    return '$name (age not set)';
  }

  static const missingAgeSnackbarMessage =
      'Please set a valid age in Profile before booking lab tests.';

  static const missingAgeHint =
      'Age is required for lab bookings. Update your Profile before continuing.';
}
