/// Mirrors the fields that were required on the legacy registration forms.
abstract final class ProfileCompletionChecker {
  static bool isDoctorDocComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (_empty(data['name'])) return false;
    if (_empty(data['qualification'])) return false;
    if (_empty(data['specialization'])) return false;
    if (_empty(data['councilNumber'])) return false;
    if (_empty(data['stateCouncil'])) return false;
    if (_empty(data['mobile'])) return false;
    if (_empty(data['gender'])) return false;
    if (data['dateOfBirth'] == null) return false;
    final langs = data['languages'];
    if (langs is! List || langs.isEmpty) return false;

    final address = data['address'];
    if (address is! Map) return false;
    if (_empty(address['country'])) return false;
    if (_empty(address['state'])) return false;
    if (_empty(address['city'])) return false;
    if (_empty(address['addressLine1'])) return false;
    if (_empty(address['pinCode'])) return false;

    final kycSubmitted = data['kycSubmitted'] == true;
    final hasCert = !_empty(data['registrationCertificate']);
    final hasId = !_empty(data['idProof']);
    return kycSubmitted || (hasCert && hasId);
  }

  static bool isPharmacyDocComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (_empty(data['storeName'])) return false;
    if (_empty(data['ownerName'])) return false;
    if (_empty(data['drugLicenseNumber'])) return false;
    if (_empty(data['phone'])) return false;
    if (_empty(data['email'])) return false;

    final address = data['address'];
    if (address is! Map) return false;
    if (_empty(address['country'])) return false;
    if (_empty(address['state'])) return false;
    if (_empty(address['city'])) return false;
    if (_empty(address['addressLine1'])) return false;
    if (_empty(address['pinCode'])) return false;
    return true;
  }

  static bool isLabDocComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    final labName = data['labName'] as String? ?? data['name'] as String? ?? '';
    if (labName.trim().isEmpty) return false;
    if (_empty(data['licenseNumber'])) return false;
    if (_empty(data['phone'])) return false;
    if (_empty(data['email'])) return false;

    final address = data['address'];
    if (address is! Map) return false;
    if (_empty(address['country'])) return false;
    if (_empty(address['state'])) return false;
    if (_empty(address['city'])) return false;
    if (_empty(address['addressLine1'])) return false;
    if (_empty(address['pinCode'])) return false;
    return true;
  }

  static bool isAmbulanceDocComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (_empty(data['serviceName'])) return false;
    if (_empty(data['ownerName'])) return false;
    if (_empty(data['driverName'])) return false;
    if (_empty(data['phone'])) return false;
    if (_empty(data['vehicleNumber'])) return false;
    if (_empty(data['city'])) return false;
    if (_empty(data['licenseNumber'])) return false;
    if (_empty(data['username'])) return false;

    final areas = data['serviceAreas'];
    if (areas is! List || areas.isEmpty) return false;

    final address = data['address'];
    if (address is! Map) return false;
    if (_empty(address['country'])) return false;
    if (_empty(address['state'])) return false;
    if (_empty(address['addressLine1'])) return false;
    if (_empty(address['pinCode'])) return false;
    return true;
  }

  static bool _empty(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }
}
