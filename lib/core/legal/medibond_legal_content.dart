/// Which DoctorNect role the legal copy is tailored for.
enum LegalAudience {
  patient,
  doctor,
  pharmacy,
  lab,
  ambulance,
}

enum LegalDocumentType {
  termsOfService,
  privacyPolicy,
}

class LegalSection {
  const LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

abstract final class DoctorNectLegalContent {
  static String title(LegalDocumentType type) => switch (type) {
        LegalDocumentType.termsOfService => 'Terms of Service',
        LegalDocumentType.privacyPolicy => 'Privacy Policy',
      };

  static String get lastUpdated => 'Last updated: 27 June 2026';

  static List<LegalSection> sections({
    required LegalDocumentType type,
    required LegalAudience audience,
  }) {
    return switch (type) {
      LegalDocumentType.termsOfService => _terms(audience),
      LegalDocumentType.privacyPolicy => _privacy(audience),
    };
  }

  static List<LegalSection> _terms(LegalAudience audience) =>
      switch (audience) {
        LegalAudience.patient => _patientTerms(),
        LegalAudience.pharmacy => _pharmacyTerms(),
        LegalAudience.lab => _labTerms(),
        LegalAudience.ambulance => _ambulanceTerms(),
        LegalAudience.doctor => _doctorTerms(),
      };

  static List<LegalSection> _privacy(LegalAudience audience) =>
      switch (audience) {
        LegalAudience.patient => _patientPrivacy(),
        LegalAudience.pharmacy => _pharmacyPrivacy(),
        LegalAudience.lab => _labPrivacy(),
        LegalAudience.ambulance => _ambulancePrivacy(),
        LegalAudience.doctor => _doctorPrivacy(),
      };

  // ── Patient Terms ───────────────────────────────────────────────────────────

  static List<LegalSection> _patientTerms() => [
        const LegalSection(
          title: '1. Acceptance of terms',
          paragraphs: [
            'These Terms of Service ("Terms") govern your use of the DoctorNect mobile application and related services ("Platform") as a patient or caregiver.',
            'By creating an account, logging in, or using DoctorNect, you agree to these Terms and our Privacy Policy. If you do not agree, please do not use the Platform.',
            'We may update these Terms from time to time. The "Last updated" date at the top of this document will change when we do. Continued use after changes are posted constitutes acceptance of the revised Terms.',
          ],
        ),
        const LegalSection(
          title: '2. About DoctorNect',
          paragraphs: [
            'DoctorNect is a digital healthcare platform that helps you find doctors, book appointments, manage health records, order medicines through partner pharmacies, book diagnostic tests through partner laboratories, and request ambulance transport through registered providers.',
            'DoctorNect is a technology intermediary. Doctors, pharmacies, laboratories, and ambulance operators on the Platform are independent service providers. DoctorNect does not provide medical care, dispense medicines, perform diagnostic tests, or operate emergency transport vehicles.',
            'We facilitate discovery, booking, communication, and record-keeping but do not guarantee the availability of any provider, specific medical outcomes, or uninterrupted access to the Platform.',
          ],
        ),
        const LegalSection(
          title: '3. Eligibility & account registration',
          paragraphs: [
            'You must be at least 18 years old to create a patient account, or have a parent or legal guardian create and manage an account on your behalf where permitted by law.',
            'You agree to provide accurate, current, and complete information during registration and to keep your profile updated.',
            'You are responsible for maintaining the confidentiality of your login credentials and for all activity that occurs under your account. Notify us immediately at support@doctornect.com if you suspect unauthorised access.',
            'You may add family member profiles under your account. You represent that you have authority to manage health information for each family member you add.',
          ],
        ),
        const LegalSection(
          title: '4. Health information & records',
          paragraphs: [
            'You may store personal health information on DoctorNect, including medical history, allergies, prescriptions, lab reports, vaccination records, and documents you upload.',
            'Information you share with a doctor, pharmacy, or laboratory through DoctorNect is shared for the purpose of care, fulfilment, or reporting you initiate or authorise.',
            'DoctorNect does not verify the clinical accuracy of information entered by you or your providers. You are responsible for reviewing your records and correcting errors where possible.',
            'The Platform is not a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of a qualified healthcare provider for medical questions.',
          ],
        ),
        const LegalSection(
          title: '5. Appointments & consultations',
          paragraphs: [
            'Appointment availability, fees, and policies are set by individual doctors and clinics. Booking through DoctorNect constitutes a request; confirmation depends on the provider\'s rules.',
            'You agree to attend confirmed appointments on time or cancel or reschedule according to the provider\'s stated policy.',
            'Teleconsultation features, where available, are subject to applicable telemedicine guidelines and the provider\'s professional judgement.',
            'Providers are solely responsible for clinical decisions, prescriptions, and follow-up care arising from consultations.',
          ],
        ),
        const LegalSection(
          title: '6. Pharmacy, laboratory & ambulance services',
          paragraphs: [
            'When you send a prescription to a partner pharmacy or order medicines, fulfilment is handled by that pharmacy subject to valid prescriptions and applicable drug laws.',
            'When you book a diagnostic test or home sample collection, the partner laboratory is responsible for sample handling, processing, and report delivery.',
            'When you request ambulance transport, registered ambulance providers respond based on their availability. DoctorNect is not an emergency dispatch service. For life-threatening emergencies, call official emergency numbers (e.g. 112 in India) immediately.',
            'Ratings and reviews you submit should be honest and based on your genuine experience. We may remove content that is abusive, false, or violates these Terms.',
          ],
        ),
        const LegalSection(
          title: '7. Payments & refunds',
          paragraphs: [
            'Where DoctorNect or a provider enables in-app or linked payments, you agree to pay applicable fees, taxes, and charges displayed at checkout.',
            'Refund and cancellation rules for paid services are determined by the relevant provider and applicable law unless DoctorNect explicitly states otherwise for a specific feature.',
            'DoctorNect is not responsible for billing disputes between you and a provider except where we expressly facilitate payment and state a refund policy.',
          ],
        ),
        ..._sharedTermsTail(startSection: 8),
      ];

  // ── Pharmacy Terms ──────────────────────────────────────────────────────────

  static List<LegalSection> _pharmacyTerms() => [
        const LegalSection(
          title: '1. Acceptance of terms',
          paragraphs: [
            'These Terms of Service ("Terms") govern your use of DoctorNect as a registered pharmacy or medical store partner ("Pharmacy Partner").',
            'By registering, logging in, or using the pharmacy features of DoctorNect, you agree to these Terms and our Privacy Policy.',
            'We may update these Terms from time to time. Continued use after changes are posted constitutes acceptance of the revised Terms.',
          ],
        ),
        const LegalSection(
          title: '2. About DoctorNect',
          paragraphs: [
            'DoctorNect connects Pharmacy Partners with doctors and patients for electronic prescription receipt, order management, and related communication.',
            'DoctorNect does not own or operate your store, employ your staff, or dispense medicines on your behalf. You remain an independent business responsible for compliance with all applicable pharmacy and drug-control laws.',
          ],
        ),
        const LegalSection(
          title: '3. Partner eligibility & verification',
          paragraphs: [
            'You represent that you hold valid drug licence, GST registration (where applicable), and other permits required to operate a pharmacy or medical store in your jurisdiction.',
            'You agree to provide accurate store name, owner name, address, licence numbers, and contact details during registration and to keep your profile current.',
            'DoctorNect may request supporting documents and may suspend or remove accounts that fail verification or receive credible regulatory or patient complaints.',
            'Licence and owner identity fields marked as locked after registration can only be changed through DoctorNect support with valid documentation.',
          ],
        ),
        const LegalSection(
          title: '4. Prescription fulfilment obligations',
          paragraphs: [
            'You may dispense medicines only against valid prescriptions received through DoctorNect or otherwise lawfully presented.',
            'You are responsible for verifying prescription authenticity, patient identity where required, drug interactions, substitutions permitted by law, and maintaining dispensing records.',
            'You must update order status (e.g. received, processing, dispensed, partially dispensed) accurately and in a timely manner so doctors and patients receive correct notifications.',
            'You must not fulfil orders for controlled substances or prescriptions you reasonably believe are fraudulent, expired, or clinically inappropriate; report concerns through support channels where appropriate.',
          ],
        ),
        const LegalSection(
          title: '5. Inventory, pricing & patient communication',
          paragraphs: [
            'You are responsible for stock availability, storage conditions, expiry management, and pricing of medicines you dispense.',
            'Any prices or availability shown to patients through DoctorNect must be accurate to the best of your knowledge at the time of display.',
            'Communications with patients and doctors through the Platform must be professional and limited to prescription fulfilment and related service matters.',
          ],
        ),
        const LegalSection(
          title: '6. Doctor connections & data use',
          paragraphs: [
            'Connection requests between your store and doctors must be initiated and accepted through DoctorNect\'s connect workflow.',
            'Patient and prescription data accessible through your account may be used only for lawful dispensing, order fulfilment, and related pharmacy operations.',
            'You must not export, sell, or misuse patient or prescription data for marketing unrelated to a specific order without explicit consent where required by law.',
          ],
        ),
        ..._sharedTermsTail(startSection: 7),
      ];

  // ── Lab Terms ───────────────────────────────────────────────────────────────

  static List<LegalSection> _labTerms() => [
        const LegalSection(
          title: '1. Acceptance of terms',
          paragraphs: [
            'These Terms of Service ("Terms") govern your use of DoctorNect as a registered diagnostic laboratory partner ("Lab Partner").',
            'By registering, logging in, or using the laboratory features of DoctorNect, you agree to these Terms and our Privacy Policy.',
            'We may update these Terms from time to time. Continued use after changes are posted constitutes acceptance of the revised Terms.',
          ],
        ),
        const LegalSection(
          title: '2. About DoctorNect',
          paragraphs: [
            'DoctorNect connects Lab Partners with doctors and patients for test orders, walk-in registrations, home sample bookings, and digital report delivery.',
            'DoctorNect does not perform diagnostic testing, collect biological samples, or issue clinical reports on your behalf. You remain an independent laboratory responsible for quality, accuracy, and regulatory compliance.',
          ],
        ),
        const LegalSection(
          title: '3. Partner eligibility & verification',
          paragraphs: [
            'You represent that you hold valid laboratory registration, accreditation, and licences required to operate in your jurisdiction.',
            'You agree to provide accurate lab name, address, licence number, contact details, and service information and to keep your profile current.',
            'DoctorNect may request supporting documents and may suspend or remove accounts that fail verification or receive credible complaints.',
            'Licence number and other fields marked as locked after registration can only be changed through DoctorNect support with valid documentation.',
          ],
        ),
        const LegalSection(
          title: '4. Test orders & sample handling',
          paragraphs: [
            'You must process test orders received from connected doctors and patient bookings in accordance with applicable clinical standards, quality systems, and turnaround times you publish or agree to.',
            'You are responsible for correct patient identification, sample collection, labelling, chain of custody, processing, and quality control.',
            'You must update order and booking status (e.g. ordered, processing, completed) accurately so patients and doctors receive timely notifications.',
          ],
        ),
        const LegalSection(
          title: '5. Reports & digital delivery',
          paragraphs: [
            'Diagnostic reports uploaded through DoctorNect must be complete, legible, and issued under your laboratory\'s authority.',
            'By uploading a report, you authorise DoctorNect to deliver it to the patient and, where applicable, the ordering doctor associated with the test.',
            'You are responsible for the clinical content of reports. DoctorNect hosts files for delivery but does not alter clinical results.',
            'You must protect report files and only share them with authorised patients and providers through the Platform or other lawful channels.',
          ],
        ),
        const LegalSection(
          title: '6. Walk-in patients, bookings & connections',
          paragraphs: [
            'Walk-in patient data you enter at the lab counter must be collected lawfully and used only for test registration, billing, and report delivery.',
            'Home collection bookings require you to honour confirmed slots or communicate delays promptly to patients.',
            'Doctor connection data may be used only to manage referrals, test orders, and professional communication related to laboratory services.',
          ],
        ),
        ..._sharedTermsTail(startSection: 7),
      ];

  // ── Ambulance Terms ─────────────────────────────────────────────────────────

  static List<LegalSection> _ambulanceTerms() => [
        const LegalSection(
          title: '1. Acceptance of terms',
          paragraphs: [
            'These Terms of Service ("Terms") govern your use of DoctorNect as a registered ambulance or medical transport service provider ("Ambulance Partner").',
            'By registering, logging in, or using the ambulance driver features of DoctorNect, you agree to these Terms and our Privacy Policy.',
            'We may update these Terms from time to time. Continued use after changes are posted constitutes acceptance of the revised Terms.',
          ],
        ),
        const LegalSection(
          title: '2. About DoctorNect',
          paragraphs: [
            'DoctorNect helps patients and doctors discover and book ambulance transport from registered providers. DoctorNect does not own vehicles, employ drivers, or provide emergency medical care.',
            'You operate as an independent transport service. Clinical care during transport, where provided, remains your responsibility subject to applicable law and your qualifications.',
          ],
        ),
        const LegalSection(
          title: '3. Service registration & verification',
          paragraphs: [
            'You represent that your service, vehicles, drivers, and equipment meet all registrations, permits, and insurance requirements for medical or patient transport in your operating areas.',
            'You agree to provide accurate service name, driver details, vehicle numbers, licence information, service areas, contact details, and capability flags (e.g. oxygen, ventilator, stretcher).',
            'DoctorNect may request supporting documents and may suspend accounts that fail verification or receive credible safety complaints.',
            'You are responsible for maintaining the confidentiality of your username and PIN used to access the driver app.',
          ],
        ),
        const LegalSection(
          title: '4. Availability & response obligations',
          paragraphs: [
            'Your online/offline availability status must reflect whether you are genuinely able to accept new transport requests.',
            'You agree to review incoming requests promptly and to accept or decline them in good faith based on actual capacity, distance, and safety considerations.',
            'Once you accept a trip, you must proceed to the pickup location without unreasonable delay and keep the patient or booker informed of material delays.',
            'DoctorNect is not a government emergency dispatch system. For life-threatening emergencies, patients should contact official emergency services (e.g. 112 in India). You should not discourage callers from doing so.',
          ],
        ),
        const LegalSection(
          title: '5. Trip management, safety & ratings',
          paragraphs: [
            'You must prioritise patient safety, follow traffic laws, and maintain vehicles and equipment in roadworthy and hygienic condition.',
            'You may mark trips as completed only after the transport service described in the booking has been fulfilled or lawfully cancelled according to Platform rules.',
            'Patients may rate completed trips. You agree not to retaliate against patients for honest reviews or to solicit fraudulent ratings.',
            'Pickup and destination addresses, contact numbers, and notes provided in a booking may be used only to fulfil that transport request.',
          ],
        ),
        const LegalSection(
          title: '6. Location & communications',
          paragraphs: [
            'During active trips, location-related data may be processed to support booking workflows and notifications as described in our Privacy Policy.',
            'You must not use patient contact details obtained through DoctorNect for unsolicited marketing unrelated to the booked transport.',
          ],
        ),
        ..._sharedTermsTail(startSection: 7),
      ];

  // ── Doctor Terms (existing, preserved) ──────────────────────────────────────

  static List<LegalSection> _doctorTerms() => [
        const LegalSection(
          title: '1. Acceptance of terms',
          paragraphs: [
            'These Terms of Service ("Terms") govern your use of DoctorNect as a registered healthcare provider, clinic, or practice administrator.',
            'By creating an account, logging in, or using DoctorNect, you agree to these Terms and our Privacy Policy. If you do not agree, do not use the platform.',
            'We may update these Terms from time to time. Continued use after changes are posted constitutes acceptance of the revised Terms.',
          ],
        ),
        const LegalSection(
          title: '2. About DoctorNect',
          paragraphs: [
            'DoctorNect is a digital healthcare platform that connects patients with doctors, pharmacies, laboratories, and ambulance services for appointments, records, prescriptions, and related services.',
            'We facilitate communication and workflows but do not guarantee availability of any provider, specific medical outcomes, or uninterrupted service.',
          ],
        ),
        const LegalSection(
          title: '3. Provider eligibility & verification',
          paragraphs: [
            'You represent that you hold valid medical registration, licenses, and qualifications required to practise in your jurisdiction.',
            'DoctorNect may request identity, registration, and clinic documents before or after activating your profile. We may suspend or remove profiles that fail verification or receive credible complaints.',
            'You are solely responsible for the accuracy of your professional details, specializations, fees, availability, and clinic information displayed to patients.',
          ],
        ),
        const LegalSection(
          title: '4. Clinical & professional responsibilities',
          paragraphs: [
            'DoctorNect is a technology platform. It does not provide medical advice, diagnosis, or treatment. All clinical decisions remain your professional responsibility.',
            'You must maintain appropriate medical records, obtain informed consent where required, and comply with applicable medical council rules, telemedicine guidelines, and local laws.',
            'Prescriptions, lab orders, referrals, and patient communications issued through DoctorNect must follow your professional standards and applicable regulations.',
          ],
        ),
        const LegalSection(
          title: '5. Patient data & confidentiality',
          paragraphs: [
            'You may access patient information only for legitimate care, appointment management, or related platform features.',
            'You must not disclose, sell, or misuse patient data. You agree to follow applicable privacy laws and DoctorNect\'s Privacy Policy.',
            'If you employ staff who access DoctorNect on your behalf, you are responsible for their compliance with these Terms.',
          ],
        ),
        const LegalSection(
          title: '6. Appointments, fees & cancellations',
          paragraphs: [
            'You control your schedule, consultation fees, and booking rules within the app. Patients book based on the information you publish.',
            'You agree to honour confirmed appointments or provide timely rescheduling/cancellation notice according to your stated policy.',
            'Any payment collection, refunds, or disputes between you and patients are handled according to your practice policy and applicable law unless DoctorNect explicitly facilitates payment for a feature.',
          ],
        ),
        ..._sharedTermsTail(startSection: 7),
      ];

  static List<LegalSection> _sharedTermsTail({required int startSection}) => [
        LegalSection(
          title: '$startSection. Acceptable use',
          paragraphs: const [
            'You may not use DoctorNect for unlawful, fraudulent, abusive, or harmful activity.',
            'You may not attempt to access accounts or data that do not belong to you, reverse engineer the app, scrape data in bulk, or interfere with platform security.',
            'We may investigate violations and suspend or terminate accounts without prior notice where necessary to protect users or the Platform.',
          ],
        ),
        LegalSection(
          title: '${startSection + 1}. Intellectual property',
          paragraphs: const [
            'DoctorNect, its logo, software, and content are owned by us or our licensors. You receive a limited, non-exclusive licence to use the app for its intended purpose.',
            'You retain ownership of content you upload, but grant DoctorNect a licence to host, display, transmit, and process it solely to operate and improve the service.',
          ],
        ),
        LegalSection(
          title: '${startSection + 2}. Disclaimers & limitation of liability',
          paragraphs: const [
            'DoctorNect is provided "as is" to the extent permitted by law. We do not warrant uninterrupted or error-free operation.',
            'To the maximum extent permitted by law, DoctorNect and its affiliates are not liable for indirect, incidental, special, or consequential damages arising from use of the Platform.',
            'Nothing in these Terms limits liability that cannot be excluded under applicable law, including consumer protection laws that may apply to you.',
          ],
        ),
        LegalSection(
          title: '${startSection + 3}. Termination',
          paragraphs: const [
            'You may stop using DoctorNect at any time. We may suspend or terminate access if you breach these Terms, pose a risk to users, or as required by law.',
            'Provisions that by nature should survive termination—such as confidentiality, liability limits, and dispute resolution—will continue to apply.',
          ],
        ),
        LegalSection(
          title: '${startSection + 4}. Governing law & contact',
          paragraphs: const [
            'These Terms are governed by the laws of India, without regard to conflict-of-law principles, unless mandatory local law requires otherwise.',
            'For questions about these Terms, contact support@doctornect.com or use the support options in the About section of the app.',
          ],
        ),
      ];

  // ── Patient Privacy ─────────────────────────────────────────────────────────

  static List<LegalSection> _patientPrivacy() => [
        const LegalSection(
          title: '1. Introduction',
          paragraphs: [
            'DoctorNect ("we", "us", "our") respects your privacy. This Privacy Policy explains what personal and health-related information we collect when you use DoctorNect as a patient, how we use it, who we share it with, and the choices available to you.',
            'By creating an account or using the Platform, you consent to the practices described here. If you do not agree, please do not use DoctorNect.',
          ],
        ),
        const LegalSection(
          title: '2. Who is responsible for your data',
          paragraphs: [
            'DoctorNect operates the Platform and is responsible for processing personal data described in this policy for account management, bookings, notifications, and platform security.',
            'Doctors, pharmacies, laboratories, and ambulance providers you interact with may also process your data as independent controllers for the clinical or service records they create. Their use of your information is also subject to their professional obligations and applicable law.',
          ],
        ),
        const LegalSection(
          title: '3. Information we collect',
          paragraphs: [
            'Account & identity data: full name, age, date of birth, gender, profile photo, mobile number, email address, and login credentials.',
            'Health & medical data you provide or generate: medical history, allergies, chronic conditions, prescriptions, lab reports, vaccination records, documents you upload, appointment notes shared with you, and family member profiles you create.',
            'Booking & service data: doctor appointments, pharmacy orders, laboratory test bookings (including home collection address and slot), ambulance requests (pickup/drop locations, contact number, notes), ratings, and reviews.',
            'Technical & usage data: device type, operating system, app version, IP address, crash logs, in-app actions, and Firebase Cloud Messaging (FCM) token for push notifications.',
            'Communications: messages and support requests you send through the Platform.',
          ],
        ),
        const LegalSection(
          title: '4. How we use your information',
          paragraphs: [
            'To create and manage your account and family profiles.',
            'To book and manage appointments, prescriptions, lab tests, and ambulance transport with providers you select.',
            'To store and display your health records and reports you upload or receive from connected providers.',
            'To send transactional notifications (e.g. appointment reminders, order updates, report ready alerts) via push notification, SMS, or email where enabled.',
            'To improve Platform safety, troubleshoot errors, prevent fraud, and analyse aggregated usage trends.',
            'To comply with legal obligations and respond to lawful requests from authorities.',
          ],
        ),
        const LegalSection(
          title: '5. Legal basis for processing (India)',
          paragraphs: [
            'We process your personal data based on your consent when you register and use features that require data collection, and on contractual necessity to provide the services you request.',
            'We may also process data where required by law or where necessary to protect vital interests in genuine emergency situations, to the extent permitted under applicable Indian law including the Digital Personal Data Protection Act, 2023 and rules thereunder.',
          ],
        ),
        const LegalSection(
          title: '6. How we share your information',
          paragraphs: [
            'With healthcare providers you choose: when you book a doctor, send a prescription to a pharmacy, order a lab test, or request ambulance transport, we share the information necessary to fulfil that request (e.g. name, contact, clinical details, addresses).',
            'With service providers: we use cloud infrastructure providers such as Google Firebase (authentication, database, storage, messaging) to host and deliver the Platform. They process data on our instructions under contractual safeguards.',
            'For legal reasons: we may disclose information if required by law, court order, or government request, or to protect the rights, safety, or property of DoctorNect, users, or the public.',
            'We do not sell your personal information to third parties for their independent marketing.',
          ],
        ),
        const LegalSection(
          title: '7. Data retention',
          paragraphs: [
            'We retain your account and health record data for as long as your account is active or as needed to provide services you request.',
            'You may request account deletion subject to legal retention requirements (e.g. medical records that providers must retain under law). Some anonymised or aggregated data may be kept for analytics.',
            'Backup copies may persist for a limited period after deletion before being overwritten.',
          ],
        ),
        ..._sharedPrivacyTail(startSection: 8),
      ];

  // ── Pharmacy Privacy ────────────────────────────────────────────────────────

  static List<LegalSection> _pharmacyPrivacy() => [
        const LegalSection(
          title: '1. Introduction',
          paragraphs: [
            'This Privacy Policy explains how DoctorNect collects, uses, stores, and shares information when you register and operate a pharmacy or medical store account on the Platform.',
            'By using DoctorNect as a Pharmacy Partner, you agree to this policy. You must also ensure your staff who access the Platform understand and follow it.',
          ],
        ),
        const LegalSection(
          title: '2. Who is responsible for your data',
          paragraphs: [
            'DoctorNect is the data controller for account, store profile, and Platform usage data described below.',
            'Patient and prescription data you access through DoctorNect is shared with you to fulfil orders initiated by patients or doctors. You are responsible for handling that data in compliance with applicable pharmacy and privacy laws.',
          ],
        ),
        const LegalSection(
          title: '3. Information we collect',
          paragraphs: [
            'Store profile data: store name, owner name, address, city, drug licence number, GST number (if provided), phone number, email address, and account login credentials.',
            'Operational data: prescription orders received from doctors, dispensing status updates, partial fulfilment notes, connection requests with doctors, and in-app notifications.',
            'Patient data visible to you: patient name, contact details, and prescription contents necessary to dispense medicines for orders routed to your store.',
            'Technical data: device information, app version, log files, IP address, and FCM token for order and connection alerts.',
            'Communications: messages with doctors or patients through Platform features and support correspondence.',
          ],
        ),
        const LegalSection(
          title: '4. How we use your information',
          paragraphs: [
            'To register, verify, and display your store profile to connected doctors and patients.',
            'To deliver electronic prescriptions, manage order workflows, and send notifications about new prescriptions, connection requests, and status changes.',
            'To maintain records of transactions on the Platform for dispute resolution, auditing, and legal compliance.',
            'To improve Platform reliability, security, and partner experience through aggregated analytics.',
            'To comply with applicable laws and respond to lawful requests.',
          ],
        ),
        const LegalSection(
          title: '5. How we share your information',
          paragraphs: [
            'With connected doctors and patients: your store name, address, contact details, and order status are visible to parties involved in a prescription or order.',
            'With cloud service providers: we use Google Firebase and similar infrastructure to store and sync data securely.',
            'We do not sell Pharmacy Partner data to third-party marketers.',
            'We may disclose information when required by law or to protect users and the Platform.',
          ],
        ),
        const LegalSection(
          title: '6. Your responsibilities regarding patient data',
          paragraphs: [
            'You may use patient and prescription data accessed through DoctorNect only for lawful dispensing and related pharmacy operations.',
            'You must implement appropriate staff access controls and not download or share patient data outside the Platform except as required for lawful dispensing or record-keeping.',
            'Notify support@doctornect.com without undue delay if you become aware of a data breach affecting information obtained through DoctorNect.',
          ],
        ),
        ..._sharedPrivacyTail(startSection: 7),
      ];

  // ── Lab Privacy ─────────────────────────────────────────────────────────────

  static List<LegalSection> _labPrivacy() => [
        const LegalSection(
          title: '1. Introduction',
          paragraphs: [
            'This Privacy Policy explains how DoctorNect collects, uses, stores, and shares information when you register and operate a diagnostic laboratory account on the Platform.',
            'By using DoctorNect as a Lab Partner, you agree to this policy and must ensure your staff comply with it.',
          ],
        ),
        const LegalSection(
          title: '2. Who is responsible for your data',
          paragraphs: [
            'DoctorNect is the data controller for laboratory account and Platform usage data described below.',
            'Patient test data and reports you process remain subject to your obligations as a healthcare service provider under applicable diagnostic and privacy laws.',
          ],
        ),
        const LegalSection(
          title: '3. Information we collect',
          paragraphs: [
            'Laboratory profile data: lab name, address, city/area, licence number, GST number (if provided), phone number, email address, and login credentials.',
            'Operational data: doctor test orders, patient app bookings, walk-in patient registrations (name, age, gender, phone, tests ordered), order status updates, and uploaded diagnostic reports (PDF/image files).',
            'Patient data visible to you: patient name, age, gender, contact number, test details, home collection address (if applicable), and doctor referral information.',
            'Connection data: doctor connection requests, active partnerships, and related notifications.',
            'Technical data: device information, app version, logs, IP address, and FCM token for order and booking alerts.',
          ],
        ),
        const LegalSection(
          title: '4. How we use your information',
          paragraphs: [
            'To register, verify, and present your laboratory to doctors and patients on DoctorNect.',
            'To receive and manage test orders, walk-in entries, and patient bookings.',
            'To host and deliver diagnostic reports you upload to authorised patients and ordering doctors.',
            'To send notifications about new orders, bookings, connection requests, and status changes.',
            'To maintain audit trails, improve Platform security, and comply with legal obligations.',
          ],
        ),
        const LegalSection(
          title: '5. How we share your information',
          paragraphs: [
            'With patients and doctors: when you upload a report or update an order, relevant information is shared with the patient and, where applicable, the referring doctor.',
            'With cloud storage providers: report files are stored using secure cloud infrastructure (e.g. Google Firebase Storage) to enable patient access.',
            'We do not sell laboratory data to third parties.',
            'We may disclose information when required by law or to protect users and the Platform.',
          ],
        ),
        const LegalSection(
          title: '6. Report files & sensitive health data',
          paragraphs: [
            'Diagnostic reports contain sensitive personal health information. You must upload reports only for patients who have undergone testing at your laboratory and only through authorised DoctorNect workflows.',
            'Patients receive in-app and push notifications when reports are shared. You are responsible for the accuracy and completeness of report content.',
            'Report files are retained according to DoctorNect\'s retention schedule and applicable medical record laws.',
          ],
        ),
        ..._sharedPrivacyTail(startSection: 7),
      ];

  // ── Ambulance Privacy ───────────────────────────────────────────────────────

  static List<LegalSection> _ambulancePrivacy() => [
        const LegalSection(
          title: '1. Introduction',
          paragraphs: [
            'This Privacy Policy explains how DoctorNect collects, uses, stores, and shares information when you register and operate an ambulance or medical transport service on the Platform.',
            'By using DoctorNect as an Ambulance Partner, you agree to this policy.',
          ],
        ),
        const LegalSection(
          title: '2. Who is responsible for your data',
          paragraphs: [
            'DoctorNect is the data controller for service account and Platform usage data described below.',
            'Patient trip information shared with you must be handled according to applicable transport, healthcare, and privacy laws in your operating region.',
          ],
        ),
        const LegalSection(
          title: '3. Information we collect',
          paragraphs: [
            'Service profile data: service name, owner name, driver name, username, phone number, vehicle number, ambulance type, city, service areas, base address, licence and insurance numbers, equipment capabilities (oxygen, ventilator, stretcher, 24×7), rate per km, and PIN credentials.',
            'Availability data: online/offline status you set, which determines whether you receive new booking broadcasts.',
            'Booking & trip data: patient name, pickup location, destination (where provided), contact phone, booking notes, trip status (pending, accepted, completed, cancelled), acceptance timestamps, and ratings/reviews from patients.',
            'Location-related data: approximate or precise location data may be processed during active trips and when you use location-enabled features, as permitted by your device settings and applicable law.',
            'Technical data: device information, app version, logs, IP address, FCM token for trip request alerts, and anonymous Firebase authentication identifiers.',
          ],
        ),
        const LegalSection(
          title: '4. How we use your information',
          paragraphs: [
            'To register your service and display your profile to patients and doctors booking transport.',
            'To broadcast trip requests to available drivers and manage accept/reject/complete workflows.',
            'To send push notifications about new requests, trip updates, and account alerts.',
            'To calculate and display service ratings based on patient feedback.',
            'To maintain trip history for dispute resolution, safety investigations, and legal compliance.',
            'To improve matching, reliability, and security of the transport feature.',
          ],
        ),
        const LegalSection(
          title: '5. How we share your information',
          paragraphs: [
            'With patients and doctors who book transport: your service name, driver name, vehicle number, phone number, ambulance type, and availability may be shown when you accept a trip or as part of service discovery.',
            'With patients after acceptance: contact and vehicle details needed to coordinate pickup.',
            'With cloud providers: data is stored and synced using Google Firebase and related infrastructure under contractual safeguards.',
            'We do not sell driver or service data to unrelated third parties.',
            'We may disclose information when required by law, court order, or to investigate safety incidents.',
          ],
        ),
        const LegalSection(
          title: '6. Location data',
          paragraphs: [
            'Location information may be collected when you use the driver app during active trips to support booking coordination and notifications. Collection practices depend on device permissions you grant.',
            'You can control certain location permissions through your device settings; disabling permissions may limit Platform functionality.',
            'We do not continuously track drivers when they are offline unless a separate feature explicitly requests it and you consent.',
          ],
        ),
        ..._sharedPrivacyTail(startSection: 7),
      ];

  // ── Doctor Privacy (preserved) ────────────────────────────────────────────────

  static List<LegalSection> _doctorPrivacy() => [
        const LegalSection(
          title: '1. Introduction',
          paragraphs: [
            'DoctorNect ("we", "us") respects your privacy. This Privacy Policy explains what information we collect, how we use it, and the choices you have when you use DoctorNect as a healthcare provider.',
            'By using DoctorNect, you consent to the practices described here, in addition to any role-specific notices shown in the app.',
          ],
        ),
        const LegalSection(
          title: '2. Data controller',
          paragraphs: [
            'DoctorNect operates the platform and is responsible for processing personal data described in this policy, except where providers act as independent controllers for clinical decisions and records they create.',
          ],
        ),
        const LegalSection(
          title: '3. Information we collect (doctors)',
          paragraphs: [
            'Profile & professional data: name, contact details, specialization, qualifications, registration numbers, clinic address, photos, fees, and availability.',
            'Practice data: appointments, patient lists you manage, prescriptions, clinical notes, lab orders, referrals, reviews, and messages sent through the platform.',
            'Technical data: device type, app version, log data, and push notification tokens for alerts.',
          ],
        ),
        const LegalSection(
          title: '4. How we use your information',
          paragraphs: [
            'To create and display your public profile to patients seeking care.',
            'To manage appointments, notifications, prescriptions, connected pharmacies/labs, and practice analytics.',
            'To verify identity, prevent fraud, improve platform security, and comply with legal obligations.',
          ],
        ),
        const LegalSection(
          title: '5. Sharing of information',
          paragraphs: [
            'Patient-facing profile fields you choose to publish are visible to patients on DoctorNect.',
            'Clinical information is shared only with patients and partners (e.g. pharmacy, lab) when you initiate or authorise a workflow.',
            'We use cloud infrastructure providers (such as Google Firebase) to store and sync data securely. We do not sell your personal information.',
          ],
        ),
        ..._sharedPrivacyTail(startSection: 6),
      ];

  static List<LegalSection> _sharedPrivacyTail({required int startSection}) => [
        LegalSection(
          title: '$startSection. Data security',
          paragraphs: const [
            'We use encryption in transit (HTTPS/TLS), access controls, authentication, and industry-standard cloud security measures provided by our infrastructure partners.',
            'No method of electronic transmission or storage is completely secure. You are responsible for safeguarding your login credentials and devices used to access DoctorNect.',
            'Report suspected security issues to support@doctornect.com promptly.',
          ],
        ),
        LegalSection(
          title: '${startSection + 1}. Your rights & choices',
          paragraphs: const [
            'Depending on applicable law, including the Digital Personal Data Protection Act, 2023 (India), you may have the right to access, correct, update, or delete your personal data, withdraw consent for optional processing, and lodge a complaint with a supervisory authority.',
            'You can update much of your profile information directly in the app.',
            'For other requests—including data export or account deletion—contact support@doctornect.com. We will respond within timelines required by applicable law.',
            'You may control push notifications through your device or in-app settings where available.',
          ],
        ),
        LegalSection(
          title: '${startSection + 2}. Children\'s privacy',
          paragraphs: const [
            'DoctorNect is not intended for children to register independently without parental or guardian involvement where required by law.',
            'Family or dependent profiles managed by an adult account holder must comply with applicable consent requirements for minors\' health data.',
          ],
        ),
        LegalSection(
          title: '${startSection + 3}. Cookies & similar technologies',
          paragraphs: const [
            'Our mobile app and web interfaces may use local storage, session tokens, and analytics identifiers to keep you signed in, remember preferences, and measure performance.',
            'You can limit certain tracking through device settings, though some features may not function without essential technical data.',
          ],
        ),
        LegalSection(
          title: '${startSection + 4}. International data transfers',
          paragraphs: const [
            'Your data may be processed on servers located in or outside India through our cloud providers. Where required, we implement appropriate contractual and technical safeguards for cross-border transfers.',
          ],
        ),
        LegalSection(
          title: '${startSection + 5}. Changes to this policy',
          paragraphs: const [
            'We may update this Privacy Policy periodically to reflect changes in our practices, technology, or legal requirements. Material changes will be indicated by an updated "Last updated" date.',
            'We encourage you to review this policy regularly. Continued use of DoctorNect after changes constitutes acceptance of the updated policy.',
          ],
        ),
        LegalSection(
          title: '${startSection + 6}. Contact us',
          paragraphs: const [
            'For privacy questions, data requests, or complaints, contact:',
            'Email: support@doctornect.com',
            'Include your registered name, role (patient/pharmacy/lab/ambulance), and a description of your request so we can assist you efficiently.',
          ],
        ),
      ];
}
