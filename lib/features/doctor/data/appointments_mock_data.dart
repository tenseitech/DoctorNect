import '../models/doctor_models.dart';

class AppointmentsMockData {
  static final _now = DateTime.now();
  static DateTime get _tomorrow =>
      DateTime(_now.year, _now.month, _now.day + 1, 10, 30);
  static DateTime get _dayAfter =>
      DateTime(_now.year, _now.month, _now.day + 2, 11, 0);

  static List<Appointment> get all => [
        Appointment(
          id: '1',
          tokenNumber: 12,
          patientName: 'Priya Mehta',
          age: 32,
          gender: 'F',
          timeSlot: '09:00 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 9),
          type: AppointmentType.newVisit,
          status: AppointmentStatus.inProgress,
          contactNumber: '+91 98765 43210',
          chiefComplaints: ['Persistent headache and fatigue for 2 weeks'],
          reports: const [
            PatientReport(id: 'r1', name: 'Blood Test Report.pdf', fileType: 'pdf'),
            PatientReport(id: 'r2', name: 'MRI Scan.jpg', fileType: 'image'),
          ],
          pastVisits: [
            PastVisit(
              date: DateTime(_now.year, _now.month - 2, 15),
              diagnosis: 'Migraine',
              notes: 'Prescribed sumatriptan',
            ),
          ],
          lastVitals: const PatientVitals(
            bloodPressure: '120/80 mmHg',
            pulse: '72 bpm',
            temperature: '98.4°F',
            weight: '58 kg',
          ),
        ),
        Appointment(
          id: '2',
          tokenNumber: 13,
          patientName: 'Arjun Patel',
          age: 45,
          gender: 'M',
          timeSlot: '09:30 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 9, 30),
          type: AppointmentType.followUp,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 91234 56789',
          chiefComplaints: ['Follow-up for hypertension management'],
          reports: const [
            PatientReport(id: 'r3', name: 'ECG Report.pdf', fileType: 'pdf'),
          ],
          pastVisits: [
            PastVisit(
              date: DateTime(_now.year, _now.month - 1, 10),
              diagnosis: 'Hypertension',
              notes: 'Started amlodipine 5mg',
            ),
          ],
          lastVitals: const PatientVitals(
            bloodPressure: '138/88 mmHg',
            pulse: '78 bpm',
            temperature: '98.1°F',
            weight: '82 kg',
          ),
        ),
        Appointment(
          id: '3',
          tokenNumber: 14,
          patientName: 'Sneha Reddy',
          age: 28,
          gender: 'F',
          timeSlot: '10:00 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 10),
          type: AppointmentType.newVisit,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 99887 76655',
          chiefComplaints: ['Skin rash on arms and neck'],
        ),
        Appointment(
          id: '4',
          tokenNumber: 15,
          patientName: 'Vikram Singh',
          age: 52,
          gender: 'M',
          timeSlot: '11:00 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 11),
          type: AppointmentType.followUp,
          status: AppointmentStatus.completed,
          contactNumber: '+91 97654 32109',
          chiefComplaints: ['Diabetes follow-up'],
          lastVitals: const PatientVitals(
            bloodPressure: '130/85 mmHg',
            pulse: '80 bpm',
            temperature: '98.6°F',
            weight: '90 kg',
          ),
        ),
        Appointment(
          id: '5',
          tokenNumber: 16,
          patientName: 'Ananya Iyer',
          age: 24,
          gender: 'F',
          timeSlot: '02:00 PM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 14),
          type: AppointmentType.newVisit,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 90123 45678',
          chiefComplaints: ['Annual health checkup'],
        ),
        Appointment(
          id: '6',
          tokenNumber: 17,
          patientName: 'Rohit Kumar',
          age: 38,
          gender: 'M',
          timeSlot: '04:30 PM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 16, 30),
          type: AppointmentType.followUp,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 88990 11223',
          chiefComplaints: ['Back pain follow-up'],
        ),
        Appointment(
          id: '7',
          tokenNumber: 18,
          patientName: 'Meera Joshi',
          age: 41,
          gender: 'F',
          timeSlot: '10:30 AM',
          appointmentDate: _tomorrow,
          type: AppointmentType.newVisit,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 88776 65544',
          chiefComplaints: ['Thyroid symptoms evaluation'],
        ),
        Appointment(
          id: '8',
          tokenNumber: 19,
          patientName: 'Karan Desai',
          age: 35,
          gender: 'M',
          timeSlot: '03:00 PM',
          appointmentDate: _dayAfter,
          type: AppointmentType.followUp,
          status: AppointmentStatus.confirmed,
          contactNumber: '+91 86655 44332',
          chiefComplaints: ['Asthma management review'],
        ),
        Appointment(
          id: '9',
          tokenNumber: 20,
          patientName: 'Divya Nair',
          age: 29,
          gender: 'F',
          timeSlot: '08:30 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day - 1, 8, 30),
          type: AppointmentType.newVisit,
          status: AppointmentStatus.completed,
          contactNumber: '+91 85544 33221',
          chiefComplaints: ['Fever and cough'],
        ),
        Appointment(
          id: '10',
          tokenNumber: 21,
          patientName: 'Sanjay Gupta',
          age: 48,
          gender: 'M',
          timeSlot: '12:00 PM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day - 2, 12),
          type: AppointmentType.followUp,
          status: AppointmentStatus.completed,
          contactNumber: '+91 84433 22110',
          chiefComplaints: ['Cholesterol review'],
        ),
        Appointment(
          id: '11',
          tokenNumber: 22,
          patientName: 'Lakshmi Rao',
          age: 55,
          gender: 'F',
          timeSlot: '11:30 AM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day, 11, 30),
          type: AppointmentType.newVisit,
          status: AppointmentStatus.cancelled,
          contactNumber: '+91 83322 11009',
          chiefComplaints: ['Joint pain consultation'],
        ),
        Appointment(
          id: '12',
          tokenNumber: 23,
          patientName: 'Imran Khan',
          age: 33,
          gender: 'M',
          timeSlot: '03:30 PM',
          appointmentDate: DateTime(_now.year, _now.month, _now.day - 1, 15, 30),
          type: AppointmentType.followUp,
          status: AppointmentStatus.noShow,
          contactNumber: '+91 82211 00998',
          chiefComplaints: ['Allergy follow-up'],
        ),
      ];

  static Appointment? findById(String id) {
    try {
      return all.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  static const rescheduleReasons = [
    'Doctor unavailable',
    'Emergency',
    'Patient request',
    'Clinic schedule change',
    'Other',
  ];

  static const availableSlots = [
    '09:00 AM',
    '09:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '02:00 PM',
    '02:30 PM',
    '03:00 PM',
    '03:30 PM',
    '04:00 PM',
    '04:30 PM',
  ];
}
