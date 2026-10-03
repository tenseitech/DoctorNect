/// Standard medicine strength / dosage units (from clinical measurement catalog).
const kDosageUnits = <String>[
  'mg',
  'g',
  'mcg',
  'μg',
  'kg',
  'mL',
  'L',
  'cc',
  'IU',
  'mEq',
  'mmol',
  'mol',
  'U',
  '%',
  'mg/mL',
  'g/mL',
  'mg/kg',
  'mcg/kg/min',
  'mg/day',
  'mg/dose',
  'gtt',
  'drops',
  'tsp',
  'tbsp',
  'oz',
  'pt',
  'qt',
  'gal',
];

/// Ensures a custom unit from saved prescriptions remains selectable.
List<String> dosageUnitsIncluding(String? current) {
  final unit = current?.trim() ?? '';
  if (unit.isEmpty || kDosageUnits.contains(unit)) {
    return List<String>.from(kDosageUnits);
  }
  return [unit, ...kDosageUnits];
}
