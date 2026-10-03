import 'package:flutter/foundation.dart';

class SpecialistEntry {
  SpecialistEntry({required this.name, required this.specialization});

  final String name;
  final String specialization;

  String get displayTitle => 'Dr. $name ($specialization)';
}

/// In-memory store for specialist referral entries.
/// Entries survive navigation (singleton) but reset on full app restart.
class ReferralStore extends ChangeNotifier {
  ReferralStore._();
  static final ReferralStore instance = ReferralStore._();

  final List<SpecialistEntry> _specialists = [
    SpecialistEntry(name: 'Ramesh', specialization: 'Cardiology'),
    SpecialistEntry(name: 'Suresh', specialization: 'Neurology'),
  ];

  List<SpecialistEntry> get specialists => List.unmodifiable(_specialists);

  void addSpecialist(String name, String specialization) {
    if (name.trim().isEmpty || specialization.trim().isEmpty) return;
    _specialists.add(
      SpecialistEntry(name: name.trim(), specialization: specialization.trim()),
    );
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _specialists.length) return;
    _specialists.removeAt(index);
    notifyListeners();
  }
}
