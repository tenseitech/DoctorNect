import 'package:flutter/material.dart';

import '../../booking/models/booking_models.dart';

enum SampleType { blood, urine, stool }

enum LabCollectionType { home, walkIn }

class LabTestItem {
  const LabTestItem({
    required this.id,
    required this.name,
    required this.parameters,
    required this.fastingRequired,
    required this.sampleType,
    required this.reportHours,
    this.popular = false,
    this.category,
  });

  final String id;
  final String name;
  final List<String> parameters;
  final bool fastingRequired;
  final SampleType sampleType;
  final int reportHours;
  final bool popular;
  final String? category;
}

class LabHealthPackage {
  const LabHealthPackage({
    required this.id,
    required this.name,
    required this.testCount,
    required this.description,
  });

  final String id;
  final String name;
  final int testCount;
  final String description;
}

class PartnerLab {
  const PartnerLab({
    this.id, // FIXED: optional registered lab id when sourced from labs/{labId}
    required this.name,
    required this.rating,
    required this.area,
  });

  final String? id;
  final String name;
  final double rating;
  final String area;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PartnerLab) return false;
    final thisId = id?.trim();
    final otherId = other.id?.trim();
    if (thisId != null &&
        thisId.isNotEmpty &&
        otherId != null &&
        otherId.isNotEmpty) {
      return thisId == otherId;
    }
    return name.trim().toLowerCase() == other.name.trim().toLowerCase();
  }

  @override
  int get hashCode {
    final labId = id?.trim();
    if (labId != null && labId.isNotEmpty) return labId.hashCode;
    return name.trim().toLowerCase().hashCode;
  }
}

class LabBookingDraft {
  LabBookingDraft({
    required this.test,
    this.patientName = 'Ananya Iyer',
    this.patientAge = 32,
    this.bookingForSelf = true,
    List<String>? familyMemberIds,
    this.collectionType = LabCollectionType.home,
    this.selectedLab,
    this.address,
    this.selectedDate,
    this.selectedSlotLabel,
  }) : familyMemberIds = List<String>.from(familyMemberIds ?? const []);

  final LabTestItem test;
  String patientName;
  int patientAge;
  bool bookingForSelf;
  List<String> familyMemberIds;
  LabCollectionType collectionType;
  PartnerLab? selectedLab;
  String? address;
  DateTime? selectedDate;
  String? selectedSlotLabel;
}

class ConfirmedLabBooking {
  const ConfirmedLabBooking({
    required this.bookingId,
    required this.testName,
    required this.date,
    required this.slotLabel,
    required this.isHomeCollection,
    required this.address,
    this.awaitingLabApproval = false,
    this.labName,
  });

  final String bookingId;
  final String testName;
  final DateTime date;
  final String slotLabel;
  final bool isHomeCollection;
  final String address;
  final bool awaitingLabApproval;
  final String? labName;
}

/// 12-hour lab collection / walk-in time labels (e.g. `9:30 AM`).
abstract final class LabSlotTime {
  static String format(TimeOfDay time) => formatSlotTimeLabel(time);

  static TimeOfDay? parse(String? label) => parseSlotTimeLabel(label);

  static bool isInPast(DateTime date, String slotLabel,
          [DateTime? referenceTime]) =>
      isSlotTimeInPast(date, slotLabel, referenceTime);

  static DateTime combine(DateTime date, String slotLabel) {
    final time = parse(slotLabel);
    if (time == null) {
      return DateTime(date.year, date.month, date.day);
    }
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
