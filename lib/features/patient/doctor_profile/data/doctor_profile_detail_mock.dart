import '../../data/registered_doctors_store.dart';
import '../models/doctor_profile_detail.dart';

class DoctorProfileDetailMock {
  static DoctorProfileDetail? forId(String id) {
    final listing = RegisteredDoctorsStore.instance.findById(id);
    if (listing == null) return null;

    final now = DateTime.now();
    return DoctorProfileDetail(
      id: listing.id,
      name: listing.name,
      specialization: listing.specialization,
      qualification: listing.qualification,
      experienceYears: listing.experienceYears,
      rating: listing.rating,
      reviewCount: listing.reviewCount,
      verified: listing.verified,
      languages: listing.languages,
      phone: '+91 98765 43210',
      about:
          'Dr. ${listing.name} is a compassionate ${listing.specialization.toLowerCase()} with over ${listing.experienceYears} years of experience. Focused on evidence-based care and patient education.',
      specialities: [listing.specialization, 'General Checkup', 'Chronic Disease Management'],
      services: ['Consultation', 'Follow-up', 'Health Screening', 'Prescription'],
      timings: const [
        ClinicTiming(day: 'Mon – Fri', hours: '9:00 AM – 1:00 PM, 4:00 – 8:00 PM'),
        ClinicTiming(day: 'Saturday', hours: '10:00 AM – 2:00 PM'),
        ClinicTiming(day: 'Sunday', hours: 'Closed'),
      ],
      education: [
        EducationEntry(degree: 'MBBS', college: 'Seth GS Medical College', year: 2008),
        EducationEntry(degree: listing.qualification.contains('MD') ? 'MD' : 'DNB', college: 'KEM Hospital', year: 2012),
      ],
      pastWorkplaces: [
        'Lilavati Hospital, Mumbai (2012–2018)',
        '${listing.clinicName} (2018–present)',
      ],
      awards: ['Best Physician Award 2024 — Mumbai Medical Association'],
      publications: ['Published research on preventive healthcare (2022)'],
      memberships: ['Indian Medical Association', 'Maharashtra Medical Council'],
      reviews: [
        PatientDoctorReview(
          id: 'pr1',
          maskedName: 'R*** S***',
          rating: 5,
          text: 'Very thorough and patient. Explained everything clearly.',
          date: now.subtract(const Duration(days: 5)),
          doctorReply: 'Thank you for your kind feedback!',
          helpfulCount: 12,
        ),
        PatientDoctorReview(
          id: 'pr2',
          maskedName: 'A*** P***',
          rating: 4,
          text: 'Good consultation. Slight wait at clinic.',
          date: now.subtract(const Duration(days: 18)),
          helpfulCount: 5,
        ),
        PatientDoctorReview(
          id: 'pr3',
          maskedName: 'S*** R***',
          rating: 5,
          text: 'Clinic visit was smooth and helpful.',
          date: now.subtract(const Duration(days: 30)),
          helpfulCount: 8,
        ),
      ],
      address: '${listing.clinicName}, ${listing.area}, Mumbai 400050',
      landmark: 'Opposite Bandra Station',
      mapsUrl: 'https://maps.google.com/?q=${listing.clinicName}+${listing.area}',
      nearbyLandmarks: ['Bandra Station (5 min walk)', 'Linking Road (10 min)'],
      clinicName: listing.clinicName,
      area: listing.area,
    );
  }
}
