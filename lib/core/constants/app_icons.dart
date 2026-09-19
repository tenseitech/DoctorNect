import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Shared icons used across DoctorNect (Web Awesome / Font Awesome equivalents).
abstract final class AppIcons {
  static const IconData prescription = TablerIcons.prescription;

  /// `fa-solid fa-alarm-plus`
  static const IconData reschedule = TablerIcons.alarm_plus;

  /// `fa-solid fa-hands-holding-child`
  static const FaIconData childCare = FontAwesomeIcons.handsHoldingChild;

  /// Bone & joint specialty (`fa-solid fa-bone`)
  static const FaIconData boneAndJoint = FontAwesomeIcons.bone;
}
