enum UserType { doctor, patient, medicalStore, lab, ambulance, superAdmin }

extension UserTypeX on UserType {
  bool get isDoctor => this == UserType.doctor;
  bool get isPatient => this == UserType.patient;
  bool get isMedicalStore => this == UserType.medicalStore;
  bool get isLab => this == UserType.lab;
  bool get isAmbulance => this == UserType.ambulance;
  bool get isSuperAdmin => this == UserType.superAdmin;
}
