import '../models/clinical_models.dart';
import 'dosage_units.dart';

abstract final class ClinicalMockData {
  static const doctorName = 'Dr. Rahul Sharma';
  static const registrationNo = 'MCI-12345-MH';
  static const clinicName = 'DoctorNect Health Clinic';
  static const clinicAddress = '12, Linking Road, Bandra West, Mumbai 400050';

  static const icd10Suggestions = [
    'J06.9 - Acute upper respiratory infection',
    'I10 - Essential hypertension',
    'E11.9 - Type 2 diabetes mellitus',
    'M54.5 - Low back pain',
    'J45.909 - Asthma, unspecified',
    'K21.0 - GERD with esophagitis',
    'F41.1 - Generalized anxiety disorder',
    'L30.9 - Dermatitis, unspecified',
    'N39.0 - UTI, site not specified',
    'R51 - Headache',
  ];

  static const drugSuggestions = [
    'Paracetamol 500mg',
    'Amoxicillin 500mg',
    'Azithromycin 500mg',
    'Omeprazole 20mg',
    'Metformin 500mg',
    'Amlodipine 5mg',
    'Cetirizine 10mg',
    'Pantoprazole 40mg',
    'Atorvastatin 10mg',
    'Salbutamol Inhaler',
    'Ibuprofen 400mg',
    'Vitamin D3 60k',
  ];

  static const dosageUnits = kDosageUnits;
  static const frequencies = ['OD', 'BD', 'TDS', 'QID', 'SOS', 'As directed'];
  static const routes = ['Oral', 'Topical', 'IV', 'IM', 'Inhaled'];
  static const durationUnits = ['Days', 'Weeks', 'Months'];
  static const instructionOptions = [
    'Before food',
    'After food',
    'With food',
    'Empty stomach',
  ];

  static const medicineForms = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Cream',
    'Drops',
    'Inhaler',
    'Ointment',
  ];

  static const diagnosisTypes = ['Provisional', 'Confirmed'];

  static const genders = ['Male', 'Female', 'Other'];

  static const symptomSuggestions = [
    'Fever',
    'Cough',
    'Cold',
    'Headache',
    'Body ache',
    'Nausea',
    'Vomiting',
    'Diarrhea',
    'Chest pain',
    'Breathlessness',
    'Fatigue',
    'Dizziness',
  ];

  static const radiologyTests = [
    'Chest X-Ray PA View',
    'Ultrasound Abdomen',
    'MRI Brain',
    'CT Scan Chest',
    'ECG',
    '2D Echo',
    'USG Pelvis',
    'X-Ray Spine',
  ];

  static const labTestNames = [
    'Complete Blood Count (CBC)',
    'HbA1c',
    'Lipid Profile',
    'Liver Function Test (LFT)',
    'Renal Function Test (RFT)',
    'Fasting Blood Sugar',
    'Post Prandial Blood Sugar',
    'Thyroid Profile (T3/T4/TSH)',
    'Urine Routine & Microscopy',
    'Vitamin D3',
    'Vitamin B12',
    'ESR',
    'CRP',
  ];

  static const qualifications = 'MBBS, MD (General Medicine)';

  static const consultationTimings = 'Mon–Sat · 9:00 AM – 8:00 PM';

  static const reviewSystems = [
    'Cardiovascular',
    'Respiratory',
    'GI',
    'Neurological',
    'Musculoskeletal',
    'Skin',
    'Eyes',
    'ENT',
  ];

  static const allergySeverities = ['Mild', 'Moderate', 'Severe'];

  static const labTests = [
    LabTestItem(id: '1', name: 'Complete Blood Count (CBC)', category: 'Blood Tests'),
    LabTestItem(id: '2', name: 'HbA1c', category: 'Blood Tests'),
    LabTestItem(id: '3', name: 'Lipid Profile', category: 'Blood Tests'),
    LabTestItem(id: '4', name: 'Liver Function Test', category: 'Blood Tests'),
    LabTestItem(id: '5', name: 'Thyroid Profile (T3/T4/TSH)', category: 'Blood Tests'),
    LabTestItem(id: '6', name: 'Urine Routine & Microscopy', category: 'Urine Tests'),
    LabTestItem(id: '7', name: 'Chest X-Ray PA View', category: 'Imaging'),
    LabTestItem(id: '8', name: 'Ultrasound Abdomen', category: 'Imaging'),
    LabTestItem(id: '9', name: 'Blood Culture', category: 'Culture'),
    LabTestItem(id: '10', name: 'Skin Biopsy', category: 'Biopsy'),
    LabTestItem(id: '11', name: '12-Lead ECG', category: 'ECG'),
    LabTestItem(id: '12', name: 'Vitamin D3', category: 'Other'),
  ];

  static const labCategories = [
    'Blood Tests',
    'Urine Tests',
    'Imaging',
    'Culture',
    'Biopsy',
    'ECG',
    'Other',
  ];

  static const partnerLabs = [
    'Practo Labs',
    'Thyrocare',
    'Dr. Lal PathLabs',
    'SRL Diagnostics',
    'Metropolis Healthcare',
  ];
}
