import '../../firebase_options.secrets.dart';
import 'package:flutter/foundation.dart';

abstract final class AppConstants {
  /// Legacy alias — prefer [ResponsiveLayout.contentMaxWidth] in build methods.
  static const double maxContentWidth = 1100;
  static const double cardRadius = 12;
  static const double inputRadius = 8;
  static const int splashDurationSeconds = 0;
  static const int otpLength = 6;

  /// Client OTP resend cooldown. Backend [RESEND_COOLDOWN_MS] is 60s.
  static const int otpResendCooldownSeconds = 60;

  /// Shown on registration OTP UI so testers can confirm which app build is installed.
  static const registrationBuildFingerprint = 'H7-fix-20260723';

  /// reCAPTCHA v3 site key from Firebase Console → App Check → Web.
  /// Pass at build time: --dart-define=RECAPTCHA_SITE_KEY=your_key
  /// or set RECAPTCHA_SITE_KEY in project root `.env` and run generate_firebase_secrets.ps1.
  static const firebaseAppCheckRecaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '',
  );

  static String get resolvedAppCheckRecaptchaSiteKey {
    final fromDefine = firebaseAppCheckRecaptchaSiteKey.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      final fromSecrets = FirebaseOptionsSecrets.recaptchaSiteKey.trim();
      if (fromSecrets.isNotEmpty) return fromSecrets;
    }
    return '';
  }

  /// Optional fixed App Check debug token for local mobile builds.
  /// Generate a UUID, register it in Firebase Console → App Check → Manage debug
  /// tokens, then run:
  /// `flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=your-uuid`
  static const appCheckDebugToken = String.fromEnvironment(
    'APP_CHECK_DEBUG_TOKEN',
    defaultValue: '',
  );

  static String get resolvedAppCheckDebugToken {
    final fromDefine = appCheckDebugToken.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      final fromSecrets = FirebaseOptionsSecrets.appCheckDebugToken.trim();
      if (fromSecrets.isNotEmpty) return fromSecrets;
    }
    return '';
  }

  static const Map<String, List<String>> specializationCategories = {
    'Surgery': [
      'General Surgery',
      'Cardiothoracic Surgery',
      'Neurosurgery',
      'Orthopedic Surgery',
      'Plastic & Reconstructive Surgery',
      'Vascular Surgery',
      'Pediatric Surgery',
      'Urological Surgery',
      'Colorectal Surgery',
      'Surgical Oncology',
      'Trauma Surgery',
      'Laparoscopic Surgery',
      'Robotic Surgery',
      'Burn Surgery',
      'Liver Transplant Surgery',
      'Kidney Transplant Surgery',
      'Hand Surgery',
      'Spine Surgery',
      'Bariatric Surgery',
      'Oral & Maxillofacial Surgery',
    ],
    'Medicine (Internal)': [
      'General Medicine (Internal Medicine)',
      'Cardiology',
      'Neurology',
      'Gastroenterology',
      'Pulmonology',
      'Nephrology',
      'Endocrinology',
      'Rheumatology',
      'Hematology',
      'Infectious Disease',
      'Critical Care Medicine',
      'Sports Medicine',
      'Geriatrics',
      'Clinical Pharmacology',
      'Occupational Medicine',
      'Sleep Medicine',
      'Palliative Medicine',
      'Metabolic Medicine',
      'Hepatology',
      'Immunology',
    ],
    'Obstetrics & Gynecology': [
      'Obstetrics & Gynecology (OB-GYN)',
      'Maternal-Fetal Medicine',
      'Reproductive Medicine & IVF',
      'Gynecologic Oncology',
      'Urogynecology',
      'Laparoscopic Gynecology',
      'Endoscopic Gynecology',
      'Adolescent Gynecology',
      'Menopause & HRT',
    ],
    'Pediatrics': [
      'General Pediatrics',
      'Neonatology',
      'Pediatric Cardiology',
      'Pediatric Neurology',
      'Pediatric Oncology',
      'Pediatric Nephrology',
      'Pediatric Pulmonology',
      'Pediatric Gastroenterology',
      'Pediatric Endocrinology',
      'Pediatric Hematology',
      'Developmental Pediatrics',
      'Pediatric Intensivist',
      'Pediatric Rheumatology',
      'Pediatric Infectious Diseases',
    ],
    'Diagnostics & Radiology': [
      'Radiodiagnosis',
      'Interventional Radiology',
      'Nuclear Medicine',
      'Radiation Oncology',
      'Neuroradiology',
      'Musculoskeletal Radiology',
      'Breast Imaging',
      'Pediatric Radiology',
      'CT & MRI Specialist',
      'Ultrasound Specialist',
    ],
    'Oncology': [
      'Medical Oncology',
      'Surgical Oncology',
      'Radiation Oncology',
      'Gynecologic Oncology',
      'Pediatric Oncology',
      'Hemato-Oncology',
      'Neuro-Oncology',
      'Head & Neck Oncology',
      'Thoracic Oncology',
      'Gastrointestinal Oncology',
      'Urologic Oncology',
    ],
    'Mental Health & Neurology': [
      'Psychiatry',
      'Child & Adolescent Psychiatry',
      'Geriatric Psychiatry',
      'Addiction Psychiatry',
      'Forensic Psychiatry',
      'Liaison Psychiatry',
      'Neuropsychiatry',
      'Epileptology',
      'Movement Disorders',
      'Neuro-Critical Care',
      'Cognitive Neurology',
    ],
    'Dentistry': [
      'General Dentistry',
      'Orthodontics',
      'Prosthodontics',
      'Periodontics',
      'Endodontics',
      'Oral Surgery',
      'Pedodontics (Pediatric Dentistry)',
      'Oral Pathology',
      'Oral Medicine',
      'Public Health Dentistry',
      'Implantology',
    ],
    'Sensory & ENT': [
      'ENT (Otolaryngology)',
      'Ophthalmology',
      'Audiology',
      'Speech & Language Pathology',
      'Otoneurology',
      'Skull Base Surgery',
      'Rhinology',
      'Laryngology',
      'Strabismus & Pediatric Ophthalmology',
      'Vitreo-Retinal Surgery',
      'Cornea & External Disease',
      'Oculoplasty',
    ],
    'Skin, Hair & Aesthetics': [
      'Dermatology',
      'Venereology (STIs)',
      'Leprosy',
      'Aesthetic Dermatology',
      'Cosmetic Surgery',
      'Hair Transplant',
      'Laser Dermatology',
      'Trichology',
    ],
    'Emergency & Critical Care': [
      'Emergency Medicine',
      'Critical Care / ICU',
      'Trauma & Acute Care Surgery',
      'Anesthesiology',
      'Pain Management',
      'Pre-Hospital & Disaster Medicine',
      'Toxicology',
    ],
    'Pathology & Lab Medicine': [
      'Anatomical Pathology',
      'Clinical Pathology',
      'Histopathology',
      'Cytopathology',
      'Microbiology',
      'Virology',
      'Biochemistry',
      'Hematopathology',
      'Immunopathology',
      'Molecular Pathology',
      'Transfusion Medicine (Blood Banking)',
      'Forensic Pathology',
    ],
    'Community & Preventive Medicine': [
      'Community Medicine',
      'Epidemiology',
      'Public Health',
      'Occupational Health',
      'Aviation Medicine',
      'Armed Forces Medicine',
      'Rural Medicine',
      'Nutrition & Dietetics',
      'Health Administration',
    ],
    'Rehabilitation & Allied': [
      'Physical Medicine & Rehabilitation (PMR)',
      'Physiotherapy',
      'Occupational Therapy',
      'Prosthetics & Orthotics',
      'Audiology & Rehabilitation',
      'Palliative Care',
      'Sports Rehabilitation',
    ],
    'Traditional & Integrative Medicine (AYUSH)': [
      'Ayurveda (BAMS)',
      'Homeopathy (BHMS)',
      'Unani Medicine (BUMS)',
      'Siddha Medicine',
      'Naturopathy & Yoga',
      'Acupuncture',
      'Panchkarma',
    ],
  };

  static List<String> get allSpecializations => [
        for (final list in specializationCategories.values) ...list,
      ];

  // Backward-compatible alias
  static List<String> get specializations => allSpecializations;

  static const List<String> languages = [
    'Hindi',
    'English',
    'Bengali',
    'Marathi',
    'Telugu',
    'Tamil',
    'Gujarati',
    'Kannada',
    'Malayalam',
    'Odia',
    'Punjabi',
    'Assamese',
    'Maithili',
    'Santali',
    'Kashmiri',
    'Nepali',
    'Sindhi',
    'Dogri',
    'Konkani',
    'Manipuri',
    'Bodo',
    'Santhali',
    'Urdu',
    'Sanskrit',
    'Rajasthani',
    'Chhattisgarhi',
    'Bhojpuri',
    'Tulu',
    'Khasi',
    'Mizo',
  ];

  static const List<String> genders = ['Male', 'Female', 'Other'];
  static const List<String> bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];

  static const String otherDoctorQualification = 'Other';

  static const List<String> doctorQualifications = [
    'MBBS',
    'MD',
    'MS',
    'DM',
    'MCh',
    'BDS',
    'MDS',
    'BAMS',
    'BHMS',
    'BUMS',
    'BNYS',
    'DNB',
    'FRCS',
    'MRCP',
    otherDoctorQualification,
  ];

  static bool isListedDoctorQualification(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    return doctorQualifications
        .where((q) => q != otherDoctorQualification)
        .contains(trimmed);
  }

  static String normalizeSpecialization(String? value) {
    return value?.trim() ?? '';
  }

  static String normalizeGender(String? value) {
    final trimmed = value?.trim() ?? '';
    if (genders.contains(trimmed)) return trimmed;
    return genders.first;
  }

  /// Canonical patient gender for appointments: Male | Female | Other.
  /// Accepts legacy single-letter codes (M/F/O) and case variants.
  static String normalizePatientGender(String? value, {String fallback = ''}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return fallback;
    if (genders.contains(trimmed)) return trimmed;

    switch (trimmed.toUpperCase()) {
      case 'M':
      case 'MALE':
        return 'Male';
      case 'F':
      case 'FEMALE':
        return 'Female';
      case 'O':
      case 'OTHER':
        return 'Other';
    }

    final lower = trimmed.toLowerCase();
    for (final gender in genders) {
      if (gender.toLowerCase() == lower) return gender;
    }
    return trimmed;
  }

  /// Display label for appointment/patient gender (handles legacy M/F/O).
  static String patientGenderLabel(String? value, {String fallback = '—'}) {
    final normalized = normalizePatientGender(value);
    return normalized.isEmpty ? fallback : normalized;
  }

  static bool isFemalePatientGender(String? value) =>
      normalizePatientGender(value) == 'Female';
}
