import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/patient/lab/data/patient_lab_catalog_builder.dart';
import '../../../features/patient/lab/models/lab_models.dart';

import '../firebase_bootstrap.dart';

import '../firestore_paths.dart';

import '../firestore_read_helper.dart';

import 'lab_repository.dart';

class LabCatalogRepository {
  LabCatalogRepository._();

  static final LabCatalogRepository instance = LabCatalogRepository._();

  static const _docId = 'default';

  Future<LabCatalog> fetchCatalog() async {
    LabCatalog catalog;

    if (!FirebaseBootstrap.isReady) {
      catalog = LabCatalog.defaults();
    } else {
      final ref = FirebaseFirestore.instance
          .collection(FirestorePaths.labCatalog)
          .doc(_docId);
      final snap = await FirestoreReadHelper.getDocument(
          reference: ref, preferCache: true);
      if (!snap.exists || snap.data() == null) {
        catalog = LabCatalog.defaults();
      } else {
        catalog = LabCatalog.fromMap(snap.data()!);
      }
    }

    return _withRegisteredPartnerLabs(_withMergedTests(catalog));
  }

  LabCatalog _withMergedTests(LabCatalog catalog) {
    return LabCatalog(
      tests: PatientLabCatalogBuilder.mergeTests(catalog.tests),
      packages: catalog.packages,
      partnerLabs: catalog.partnerLabs,
      slotPeriods: catalog.slotPeriods,
    );
  }

  Future<LabCatalog> _withRegisteredPartnerLabs(LabCatalog catalog) async {
    if (!FirebaseBootstrap.isReady) return catalog;

    final registered = await LabRepository.instance.fetchVerifiedLabs();
    if (registered.isEmpty) return catalog;

    final partnerLabs = registered
        .map(
          (lab) => PartnerLab(
            id: lab.id,
            name: lab.labName,
            rating: lab.rating > 0 ? lab.rating : 4.5,
            area: lab.area.isNotEmpty ? lab.area : lab.address,
          ),
        )
        .toList();

    return LabCatalog(
      tests: catalog.tests,
      packages: catalog.packages,
      partnerLabs: partnerLabs,
      slotPeriods: catalog.slotPeriods,
    );
  }

  Future<LabTestItem?> testById(String id) async {
    final catalog = await fetchCatalog();

    try {
      return catalog.tests.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DateTime> nextBookableDays({int count = 7}) {
    final now = DateTime.now();

    return List.generate(
        count, (i) => DateTime(now.year, now.month, now.day + i));
  }
}

class LabCatalog {
  const LabCatalog({
    required this.tests,
    required this.packages,
    required this.partnerLabs,
    required this.slotPeriods,
  });

  final List<LabTestItem> tests;

  final List<LabHealthPackage> packages;

  final List<PartnerLab> partnerLabs;

  final Map<String, List<String>> slotPeriods;

  List<LabTestItem> get popularTests => tests.where((t) => t.popular).toList();

  Map<String, dynamic> toMap() => {
        'tests': tests.map(_testToMap).toList(),
        'packages': packages.map(_packageToMap).toList(),
        'partnerLabs': partnerLabs.map(_labToMap).toList(),
        'slotPeriods': slotPeriods,
      };

  static LabCatalog fromMap(Map<String, dynamic> data) {
    try {
      return LabCatalog(
        tests: (data['tests'] as List<dynamic>? ?? const [])
            .map((item) => _testFromMap(item as Map<String, dynamic>))
            .toList(),
        packages: (data['packages'] as List<dynamic>? ?? const [])
            .map((item) => _packageFromMap(item as Map<String, dynamic>))
            .toList(),
        partnerLabs: (data['partnerLabs'] as List<dynamic>? ?? const [])
            .map((item) => _labFromMap(item as Map<String, dynamic>))
            .toList(),
        slotPeriods:
            (data['slotPeriods'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) =>
              MapEntry(key, (value as List<dynamic>).cast<String>()),
        ),
      );
    } catch (_) {
      return LabCatalog.defaults();
    }
  }

  static LabCatalog defaults() => LabCatalog(
        tests: PatientLabCatalogBuilder.allTests(),
        packages: const [],
        partnerLabs: const [
          PartnerLab(name: 'Thyrocare', rating: 4.8, area: 'Bandra'),
          PartnerLab(
              name: 'Metropolis Healthcare', rating: 4.7, area: 'Andheri'),
          PartnerLab(name: 'Dr. Lal PathLabs', rating: 4.6, area: 'Powai'),
        ],
        slotPeriods: const {
          'Morning': ['7:00 AM', '8:00 AM', '9:00 AM', '10:00 AM'],
          'Afternoon': ['12:00 PM', '1:00 PM', '2:00 PM', '3:00 PM'],
          'Evening': ['5:00 PM', '6:00 PM', '7:00 PM'],
        },
      );

  static Map<String, dynamic> _testToMap(LabTestItem t) => {
        'id': t.id,
        'name': t.name,
        'parameters': t.parameters,
        'fastingRequired': t.fastingRequired,
        'sampleType': t.sampleType.name,
        'reportHours': t.reportHours,
        'popular': t.popular,
        if (t.category != null) 'category': t.category,
      };

  static LabTestItem _testFromMap(Map<String, dynamic> data) => LabTestItem(
        id: data['id'] as String,
        name: data['name'] as String,
        parameters: (data['parameters'] as List<dynamic>).cast<String>(),
        fastingRequired: data['fastingRequired'] as bool? ?? false,
        sampleType:
            SampleType.values.byName(data['sampleType'] as String? ?? 'blood'),
        reportHours: (data['reportHours'] as num?)?.toInt() ?? 24,
        popular: data['popular'] as bool? ?? false,
        category: data['category'] as String?,
      );

  static Map<String, dynamic> _packageToMap(LabHealthPackage p) => {
        'id': p.id,
        'name': p.name,
        'testCount': p.testCount,
        'description': p.description,
      };

  static LabHealthPackage _packageFromMap(Map<String, dynamic> data) =>
      LabHealthPackage(
        id: data['id'] as String,
        name: data['name'] as String,
        testCount: (data['testCount'] as num?)?.toInt() ?? 0,
        description: data['description'] as String? ?? '',
      );

  static Map<String, dynamic> _labToMap(PartnerLab l) => {
        'name': l.name,
        'rating': l.rating,
        'area': l.area,
        if (l.id != null) 'id': l.id, // FIXED: round-trip registered lab id
      };

  static PartnerLab _labFromMap(Map<String, dynamic> data) => PartnerLab(
        id: data['id']
            as String?, // FIXED: restore registered lab id when present
        name: data['name'] as String,
        rating: (data['rating'] as num?)?.toDouble() ?? 0,
        area: data['area'] as String? ?? '',
      );
}
