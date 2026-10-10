import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Shared icons used across DoctorNect (Web Awesome / Font Awesome equivalents).
abstract final class AppIcons {
  static const IconData prescription = Icons.receipt_long_rounded;

  /// `fa-solid fa-alarm-plus`
  static const IconData reschedule = Icons.add_alarm_rounded;

  /// `fa-solid fa-hands-holding-child`
  static const FaIconData childCare = FontAwesomeIcons.handsHoldingChild;

  /// Bone & joint specialty (`fa-solid fa-bone`)
  static const FaIconData boneAndJoint = FontAwesomeIcons.bone;
}
