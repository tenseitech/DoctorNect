import '../../../core/firebase/firestore_service.dart';
import '../profile/data/patient_profile_mock.dart';
import 'models/lab_models.dart';
import '../../../core/location/location_match.dart';

abstract final class LabCityFilter {
  LabCityFilter._();

  static String patientCity() {
    final addressCity = PatientProfileMock.profileAddress.city.trim();
    if (addressCity.isNotEmpty) return addressCity;
    return PatientProfileMock.profileCity.trim();
  }

  static String partnerLabKey(PartnerLab lab) {
    final id = lab.id?.trim();
    if (id != null && id.isNotEmpty) return id;
    return lab.name.trim().toLowerCase();
  }

  static bool registeredLabInCity(
      RegisteredLabProfile lab, String patientCity) {
    return registeredLabMatchesCity(lab, patientCity);
  }

  static bool partnerLabInCity(
    PartnerLab lab,
    String patientCity,
    Map<String, RegisteredLabProfile> registryById,
  ) {
    final city = patientCity.trim();
    if (city.isEmpty) return false;

    final id = lab.id?.trim();
    if (id != null && id.isNotEmpty) {
      final registered = registryById[id];
      if (registered != null) {
        return registeredLabInCity(registered, patientCity);
      }
    }

    return cityFieldsMatch(city, [lab.area]);
  }
}
