import 'package:flutter/material.dart';

enum PatientBmiCategory {
  underweight,
  healthy,
  overweight,
  obeseClassI,
  obeseClassII,
  obeseClassIII,
}

abstract final class PatientBmiUtils {
  static double? calculate(
      {required double heightCm, required double weightKg}) {
    if (heightCm <= 0 || weightKg <= 0) return null;
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  static PatientBmiCategory? categoryFor(double? bmi) {
    if (bmi == null || bmi <= 0) return null;
    if (bmi < 18.5) return PatientBmiCategory.underweight;
    if (bmi < 25) return PatientBmiCategory.healthy;
    if (bmi < 30) return PatientBmiCategory.overweight;
    if (bmi < 35) return PatientBmiCategory.obeseClassI;
    if (bmi < 40) return PatientBmiCategory.obeseClassII;
    return PatientBmiCategory.obeseClassIII;
  }

  static String labelFor(PatientBmiCategory category) {
    return switch (category) {
      PatientBmiCategory.underweight => 'Underweight',
      PatientBmiCategory.healthy => 'Healthy',
      PatientBmiCategory.overweight => 'Overweight',
      PatientBmiCategory.obeseClassI => 'Obese Class I',
      PatientBmiCategory.obeseClassII => 'Obese Class II',
      PatientBmiCategory.obeseClassIII => 'Obese Class III',
    };
  }

  static String messageFor(PatientBmiCategory category) {
    return switch (category) {
      PatientBmiCategory.underweight =>
        'Your body needs more nourishment — let\'s fix that.',
      PatientBmiCategory.healthy => 'Perfect balance — keep up the great work!',
      PatientBmiCategory.overweight =>
        'Small changes now will make a big difference.',
      PatientBmiCategory.obeseClassI =>
        'Your health needs attention — let\'s take action.',
      PatientBmiCategory.obeseClassII =>
        'Please consult a doctor for a healthier you.',
      PatientBmiCategory.obeseClassIII =>
        'See a doctor right away — your health matters.',
    };
  }

  static Color colorFor(PatientBmiCategory category) {
    return switch (category) {
      PatientBmiCategory.healthy => const Color(0xFF0D9488),
      PatientBmiCategory.underweight => const Color(0xFF2563EB),
      PatientBmiCategory.overweight => const Color(0xFFEA580C),
      PatientBmiCategory.obeseClassI => const Color(0xFFDC2626),
      PatientBmiCategory.obeseClassII => const Color(0xFFB91C1C),
      PatientBmiCategory.obeseClassIII => const Color(0xFF991B1B),
    };
  }
}
