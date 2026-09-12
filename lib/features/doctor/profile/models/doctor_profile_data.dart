import 'dart:typed_data';

import '../../../../core/constants/countries.dart';
import '../../models/doctor_models.dart';

class DoctorProfileData {
  DoctorProfileData({
    required this.fullName,
    required this.specialization,
    required this.verificationStatus,
    required this.rating,
    required this.reviewCount,
    this.photoPath,
    this.photoBytes,
    this.photoUrl,
    this.dateOfBirth,
    this.gender = 'Male',
    this.mobile = '',
    this.email = '',
    this.languages = const ['English', 'Hindi'],
    this.qualification = '',
    this.superSpecialization = '',
    this.yearsExperience = 0,
    this.registrationYear = 0,
    this.councilNumber = '',
    this.stateCouncil = '',
    this.certifications = const [],
    this.awards = '',
    this.publications = const [],
    this.clinicName = '',
    this.clinicType = 'Private',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.city = '',
    this.country = Countries.defaultCountry,
    this.state = '',
    this.pincode = '',
    this.mapsLink = '',
    this.landmark = '',
    this.clinicPhotoNames = const [],
    this.avgDurationMins = 15,
    this.maxPatientsPerDay = 20,
    this.advanceBookingDays = 7,
    this.autoAcceptAppointments = false,
    this.consultsAdultsOnly = false,
    this.appointmentReminders = true,
    this.remindHoursBefore = 2,
    this.newBookingAlert = true,
    this.cancellationAlert = true,
    this.notificationChannels = const ['App', 'SMS'],
    this.twoFactorEnabled = false,
    this.recoveryEmail = '',
    this.reviews = const [],
  });

  String fullName;
  String specialization;
  VerificationStatus verificationStatus;
  double rating;
  int reviewCount;
  String? photoPath;
  Uint8List? photoBytes;
  String? photoUrl;
  DateTime? dateOfBirth;
  String gender;
  String mobile;
  String email;
  List<String> languages;
  String qualification;
  String superSpecialization;
  int yearsExperience;
  int registrationYear;
  String councilNumber;
  String stateCouncil;
  List<String> certifications;
  String awards;
  List<String> publications;
  String clinicName;
  String clinicType;
  String addressLine1;
  String addressLine2;
  String city;
  String country;
  String state;
  String pincode;
  String mapsLink;
  String landmark;
  List<String> clinicPhotoNames;
  int avgDurationMins;
  int maxPatientsPerDay;
  int advanceBookingDays;
  bool autoAcceptAppointments;
  bool consultsAdultsOnly;
  bool appointmentReminders;
  int remindHoursBefore;
  bool newBookingAlert;
  bool cancellationAlert;
  List<String> notificationChannels;
  bool twoFactorEnabled;
  String recoveryEmail;
  List<PatientReview> reviews;

  DoctorProfileData copy() {
    return DoctorProfileData(
      fullName: fullName,
      specialization: specialization,
      verificationStatus: verificationStatus,
      rating: rating,
      reviewCount: reviewCount,
      photoPath: photoPath,
      photoBytes: photoBytes,
      photoUrl: photoUrl,
      dateOfBirth: dateOfBirth,
      gender: gender,
      mobile: mobile,
      email: email,
      languages: List<String>.from(languages),
      qualification: qualification,
      superSpecialization: superSpecialization,
      yearsExperience: yearsExperience,
      registrationYear: registrationYear,
      councilNumber: councilNumber,
      stateCouncil: stateCouncil,
      certifications: List<String>.from(certifications),
      awards: awards,
      publications: List<String>.from(publications),
      clinicName: clinicName,
      clinicType: clinicType,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      country: country,
      state: state,
      pincode: pincode,
      mapsLink: mapsLink,
      landmark: landmark,
      clinicPhotoNames: List<String>.from(clinicPhotoNames),
      avgDurationMins: avgDurationMins,
      maxPatientsPerDay: maxPatientsPerDay,
      advanceBookingDays: advanceBookingDays,
      autoAcceptAppointments: autoAcceptAppointments,
      consultsAdultsOnly: consultsAdultsOnly,
      appointmentReminders: appointmentReminders,
      remindHoursBefore: remindHoursBefore,
      newBookingAlert: newBookingAlert,
      cancellationAlert: cancellationAlert,
      notificationChannels: List<String>.from(notificationChannels),
      twoFactorEnabled: twoFactorEnabled,
      recoveryEmail: recoveryEmail,
      reviews: reviews.map((r) => r.copy()).toList(),
    );
  }
}

class PatientReview {
  PatientReview({
    required this.id,
    required this.maskedName,
    required this.rating,
    required this.text,
    required this.date,
    this.doctorReply,
    this.helpfulCount = 0,
  });

  final String id;
  final String maskedName;
  final int rating;
  final String text;
  final DateTime date;
  String? doctorReply;
  int helpfulCount;

  PatientReview copy() => PatientReview(
        id: id,
        maskedName: maskedName,
        rating: rating,
        text: text,
        date: date,
        doctorReply: doctorReply,
        helpfulCount: helpfulCount,
      );
}
