class PatientAccountRepository {
  PatientAccountRepository._();

  static final PatientAccountRepository instance = PatientAccountRepository._();

  Future<bool> isVerified(String patientId, {bool preferCache = false}) async {
    return true; // Patients have instant login access
  }
}
