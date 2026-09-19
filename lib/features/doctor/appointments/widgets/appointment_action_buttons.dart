import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/doctor_models.dart';
import '../appointment_utils.dart';

/// Compact doctor appointment actions — fixed-size pills, never full-width stretch.
class AppointmentActionButtons extends StatelessWidget {
  const AppointmentActionButtons({
    super.key,
    required this.appointment,
    this.onAccept,
    this.onDecline,
    this.onStart,
    this.onCancel,
    this.onView,
    this.compact = false,
  });

  final Appointment appointment;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onView;
  final bool compact;

  static const _gap = 8.0;
  static const _radius = 8.0;

  @override
  Widget build(BuildContext context) {
    final status = appointment.status;
    final height = compact ? 32.0 : 34.0;
    final fontSize = compact ? 11.5 : 12.0;

    if (status == AppointmentStatus.completed) {
      return _actionRow([
        _outlineButton(
          label: 'View details',
          onPressed: onView,
          color: const Color(0xFF185FA5),
          height: height,
          fontSize: fontSize,
        ),
      ]);
    }

    if (AppointmentStatusStyle.isPendingRequest(status)) {
      return _actionRow([
        _primaryButton(
          label: 'Accept',
          onPressed: onAccept,
          color: const Color(0xFF16A34A),
          height: height,
          fontSize: fontSize,
        ),
        _outlineButton(
          label: 'Decline',
          onPressed: onDecline,
          color: const Color(0xFFDC2626),
          height: height,
          fontSize: fontSize,
        ),
      ]);
    }

    if (AppointmentStatusStyle.canStartConsultation(appointment)) {
      return _actionRow([
        _primaryButton(
          label: status == AppointmentStatus.inProgress ? 'Continue' : 'Start',
          onPressed: onStart,
          color: const Color(0xFF16A34A),
          height: height,
          fontSize: fontSize,
        ),
        _outlineButton(
          label: 'Cancel',
          onPressed: onCancel,
          color: const Color(0xFFDC2626),
          height: height,
          fontSize: fontSize,
        ),
      ]);
    }

    if (status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.waiting ||
        status == AppointmentStatus.inProgress) {
      return _actionRow([
        _outlineButton(
          label: 'View',
          onPressed: onView,
          color: const Color(0xFF185FA5),
          height: height,
          fontSize: fontSize,
        ),
        _outlineButton(
          label: 'Cancel',
          onPressed: onCancel,
          color: const Color(0xFFDC2626),
          height: height,
          fontSize: fontSize,
        ),
      ]);
    }

    return const SizedBox.shrink();
  }

  Widget _actionRow(List<Widget> children) {
    return Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: children,
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    required double height,
    required double fontSize,
  }) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: Size.zero,
          fixedSize: Size(_buttonWidth(label, fontSize), height),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius)),
          textStyle: GoogleFonts.inter(
              fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    required double height,
    required double fontSize,
  }) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.55)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: Size.zero,
          fixedSize: Size(_buttonWidth(label, fontSize), height),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius)),
          textStyle: GoogleFonts.inter(
              fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  double _buttonWidth(String label, double fontSize) {
    final textWidth = label.length * (fontSize * 0.58);
    return (textWidth + 28).clamp(72.0, 108.0);
  }
}
