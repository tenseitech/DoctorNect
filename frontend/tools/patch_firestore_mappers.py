import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "lib"


def patch_referral():
    p = root / "core/firebase/mappers/referral_firestore_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n\n",
        "import '../../util/map_date_time.dart';\n\n",
    )
    text = re.sub(
        r"static DateTime _parseDate\(dynamic value\) \{[^}]+\}",
        "static DateTime _parseDate(dynamic value) => parseMapDateTime(value) ?? DateTime.now();",
        text,
        flags=re.S,
    )
    p.write_text(text, encoding="utf-8")


def patch_lab_order():
    p = root / "core/firebase/mappers/lab_order_firestore_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n\n",
        "import '../../util/map_date_time.dart';\n\n",
    )
    text = re.sub(
        r"static DateTime _parseDate\(dynamic value\) \{[^}]+\}",
        "static DateTime _parseDate(dynamic value) => parseMapDateTime(value) ?? DateTime.now();",
        text,
        flags=re.S,
    )
    p.write_text(text, encoding="utf-8")


def patch_medical_directory():
    p = root / "core/firebase/mappers/medical_directory_firestore_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n\n",
        "import '../../util/map_date_time.dart';\n\n",
    )
    text = re.sub(
        r"static DateTime _parseDate\(dynamic value\) \{[^}]+\}",
        "static DateTime _parseDate(dynamic value) => parseMapDateTime(value) ?? DateTime.now();",
        text,
        flags=re.S,
    )
    p.write_text(text, encoding="utf-8")


def patch_in_app():
    p = root / "core/firebase/mappers/in_app_notification_firestore_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n",
        "import '../../util/map_date_time.dart';\n",
    )
    text = re.sub(
        r"DateTime _createdAt\(dynamic v\) \{[^}]+\}",
        "DateTime _createdAt(dynamic v) => parseMapDateTime(v) ?? DateTime.now();",
        text,
        flags=re.S,
    )
    p.write_text(text, encoding="utf-8")


def patch_appointment():
    p = root / "core/firebase/mappers/appointment_firestore_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n",
        "import '../../util/map_date_time.dart';\n",
    )
    text = text.replace(
        "Timestamp.fromDate(record.dateTime)", "record.dateTime.toUtc().toIso8601String()"
    )
    text = text.replace(
        "Timestamp.fromDate(record.reviewCreatedAt!)",
        "record.reviewCreatedAt!.toUtc().toIso8601String()",
    )
    text = text.replace(
        "'updatedAt': FieldValue.serverTimestamp(),",
        "'updatedAt': DateTime.now().toUtc().toIso8601String(),",
    )
    text = text.replace(
        "dateTime: (data['dateTime'] as Timestamp?)?.toDate() ?? DateTime.now(),",
        "dateTime: parseMapDateTime(data['dateTime']) ?? DateTime.now(),",
    )
    text = text.replace(
        "reviewCreatedAt: (data['reviewCreatedAt'] as Timestamp?)?.toDate(),",
        "reviewCreatedAt: parseMapDateTime(data['reviewCreatedAt']),",
    )
    p.write_text(text, encoding="utf-8")


def patch_availability():
    p = root / "core/firebase/mappers/doctor_availability_mapper.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n\n",
        "import '../../util/map_date_time.dart';\n\n",
    )
    text = text.replace(
        ".map((d) => Timestamp.fromDate(DateTime(d.year, d.month, d.day)))",
        ".map((d) => DateTime(d.year, d.month, d.day).toUtc().toIso8601String())",
    )
    text = text.replace(
        "'leaveStart': Timestamp.fromDate(schedule.leaveStart!)",
        "'leaveStart': schedule.leaveStart!.toUtc().toIso8601String()",
    )
    text = text.replace(
        "'leaveEnd': Timestamp.fromDate(schedule.leaveEnd!)",
        "'leaveEnd': schedule.leaveEnd!.toUtc().toIso8601String()",
    )
    text = text.replace(
        "'updatedAt': FieldValue.serverTimestamp(),",
        "'updatedAt': DateTime.now().toUtc().toIso8601String(),",
    )
    text = text.replace(
        "if (item is Timestamp) {\n          final d = item.toDate();\n          blocked.add(DateTime(d.year, d.month, d.day));\n        } else if (item is String) {",
        "if (item is String) {",
    )
    text = text.replace(
        "(data['leaveStart'] as Timestamp?)?.toDate()",
        "parseMapDateTime(data['leaveStart'])",
    )
    text = text.replace(
        "(data['leaveEnd'] as Timestamp?)?.toDate()",
        "parseMapDateTime(data['leaveEnd'])",
    )
    p.write_text(text, encoding="utf-8")


def patch_user_profile():
    p = root / "core/firebase/models/medibond_user_profile.dart"
    text = p.read_text(encoding="utf-8")
    text = text.replace(
        "import 'package:cloud_firestore/cloud_firestore.dart';\n\n",
        "import '../../util/map_date_time.dart';\n\n",
    )
    text = re.sub(
        r"    DateTime\? parseTimestamp\(dynamic val\) \{[^}]+\}\n\n",
        "",
        text,
        flags=re.S,
    )
    text = text.replace(
        "submittedAt: parseTimestamp(data['submittedAt']),",
        "submittedAt: parseMapDateTime(data['submittedAt']),",
    )
    text = text.replace(
        "'submittedAt': Timestamp.fromDate(submittedAt!),",
        "'submittedAt': submittedAt!.toUtc().toIso8601String(),",
    )
    text = text.replace(
        "'updatedAt': FieldValue.serverTimestamp(),",
        "'updatedAt': DateTime.now().toUtc().toIso8601String(),",
    )
    p.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    patch_referral()
    patch_lab_order()
    patch_medical_directory()
    patch_in_app()
    patch_appointment()
    patch_availability()
    patch_user_profile()
    print("done")