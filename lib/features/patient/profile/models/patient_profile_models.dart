enum FamilyRelation { spouse, child, parent, sibling, friend, other }

enum ReminderTiming { oneHour, twoHours, oneDay }

class PatientAddress {
  const PatientAddress({
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.country = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.landmark = '',
  });

  final String addressLine1;
  final String addressLine2;
  final String country;
  final String city;
  final String state;
  final String pincode;
  final String landmark;

  bool get hasContent =>
      addressLine1.trim().isNotEmpty ||
      addressLine2.trim().isNotEmpty ||
      country.trim().isNotEmpty ||
      city.trim().isNotEmpty ||
      state.trim().isNotEmpty ||
      pincode.trim().isNotEmpty ||
      landmark.trim().isNotEmpty;

  String get shortLabel {
    if (city.trim().isNotEmpty) return city.trim();
    if (addressLine1.trim().isNotEmpty) return addressLine1.trim();
    return '';
  }

  String get fullLabel {
    final parts = <String>[
      addressLine1,
      addressLine2,
      if (landmark.trim().isNotEmpty) 'Near ${landmark.trim()}',
      if (country.trim().isNotEmpty) country,
      city,
      state,
      pincode,
    ].where((part) => part.trim().isNotEmpty).map((part) => part.trim());
    return parts.join(', ');
  }

  Map<String, dynamic> toMap() => {
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'country': country,
        'city': city,
        'state': state,
        'pincode': pincode,
        'landmark': landmark,
      };

  factory PatientAddress.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const PatientAddress();
    return PatientAddress(
      addressLine1: data['addressLine1'] as String? ?? '',
      addressLine2: data['addressLine2'] as String? ?? '',
      country: data['country'] as String? ?? '',
      city: data['city'] as String? ?? '',
      state: data['state'] as String? ?? '',
      pincode: data['pincode'] as String? ?? '',
      landmark: data['landmark'] as String? ?? '',
    );
  }

  PatientAddress copyWith({
    String? addressLine1,
    String? addressLine2,
    String? country,
    String? city,
    String? state,
    String? pincode,
    String? landmark,
  }) {
    return PatientAddress(
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      country: country ?? this.country,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      landmark: landmark ?? this.landmark,
    );
  }
}

class PatientProfile {
  PatientProfile({
    required this.name,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    required this.mobile,
    required this.email,
    this.height = 0.0,
    this.weight = 0.0,
    this.photoInitial,
    this.photoUrl,
  });

  String name;
  int age;
  String gender;
  String bloodGroup;
  String mobile;
  String email;
  double height;
  double weight;
  String? photoInitial;
  String? photoUrl;
}

class FamilyProfileMember {
  FamilyProfileMember({
    required this.id,
    required this.name,
    required this.relation,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    this.allergies = const [],
    this.conditions = const [],
    this.insuranceCovered = false,
    this.dateOfBirth,
    this.photoInitial,
  });

  final String id;
  final String name;
  final FamilyRelation relation;
  final int age;
  final String gender;
  final String bloodGroup;
  final List<String> allergies;
  final List<String> conditions;
  final bool insuranceCovered;
  final DateTime? dateOfBirth;
  final String? photoInitial;

  String get relationLabel => switch (relation) {
        FamilyRelation.spouse => 'Spouse',
        FamilyRelation.child => 'Child',
        FamilyRelation.parent => 'Parent',
        FamilyRelation.sibling => 'Sibling',
        FamilyRelation.friend => 'Friend',
        FamilyRelation.other => 'Other',
      };
}

class PatientPrescription {
  const PatientPrescription({
    required this.id,
    required this.title,
    required this.doctorName,
    required this.date,
    required this.fileName,
    this.prescriptionId,
  });

  final String id;
  final String title;
  final String doctorName;
  final DateTime date;
  final String fileName;
  final String? prescriptionId;
}

class MedicationReminder {
  MedicationReminder({
    required this.name,
    this.morningTime,
    this.afternoonTime,
    this.eveningTime,
    this.nightTime,
  });

  String name;
  String? morningTime;
  String? afternoonTime;
  String? eveningTime;
  String? nightTime;
}

class NotificationPrefs {
  NotificationPrefs({
    this.appointmentReminders = true,
    this.reminderTiming = ReminderTiming.twoHours,
    this.medicationReminders = false,
    this.medications = const [],
    this.labReportAlert = true,
    this.healthTips = true,
    this.offers = false,
    this.channelApp = true,
    this.channelSms = true,
    this.channelEmail = false,
    this.channelWhatsapp = true,
  });

  bool appointmentReminders;
  ReminderTiming reminderTiming;
  bool medicationReminders;
  List<MedicationReminder> medications;
  bool labReportAlert;
  bool healthTips;
  bool offers;
  bool channelApp;
  bool channelSms;
  bool channelEmail;
  bool channelWhatsapp;
}

class PrivacyPrefs {
  PrivacyPrefs({
    this.shareRecordsWithDoctors = true,
    this.allowHealthInsights = false,
    this.twoFactorEnabled = false,
  });

  bool shareRecordsWithDoctors;
  bool allowHealthInsights;
  bool twoFactorEnabled;
}

class FaqItem {
  const FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}
