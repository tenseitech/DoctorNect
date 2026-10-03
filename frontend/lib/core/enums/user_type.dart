enum UserType { doctor, patient, medical, medicalStore, lab, ambulance, superAdmin }

extension UserTypeX on UserType {
  bool get isDoctor => this == UserType.doctor;
  bool get isPatient => this == UserType.patient;
  bool get isMedical => this == UserType.medical;
  bool get isMedicalStore => this == UserType.medicalStore;
  bool get isPharmacy => this == UserType.medicalStore;
  bool get isLab => this == UserType.lab;
  bool get isAmbulance => this == UserType.ambulance;
  bool get isSuperAdmin => this == UserType.superAdmin;
}
