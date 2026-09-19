import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Unified animation and card layout for Doctor appointment and Lab test booking confirmation.
class PatientBookingConfirmedBase extends StatefulWidget {
  const PatientBookingConfirmedBase({
    super.key,
    required this.isPending,
    required this.title,
    required this.idLabel,
    required this.primaryAccent,
    required this.mainDetails,
    required this.onPrimaryAction,
    required this.primaryActionLabel,
    this.subMessage,
    this.headerIcon,
    this.onSecondaryAction,
    this.secondaryActionLabel,
    this.onCalendarAction,
    this.centerCard = false,
  });

  final bool isPending;
  final String title;
  final String idLabel;
  final String? subMessage;
  final Color primaryAccent;
  final IconData? headerIcon;
  final Widget mainDetails;
  final VoidCallback onPrimaryAction;
  final String primaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onCalendarAction;
  final bool centerCard;

  @override
  State<PatientBookingConfirmedBase> createState() => _PatientBookingConfirmedBaseState();
}

class _PatientBookingConfirmedBaseState extends State<PatientBookingConfirmedBase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconData = widget.headerIcon ??
        (widget.isPending ? Icons.schedule_send_outlined : Icons.check);

    final content = Column(
      mainAxisSize: widget.centerCard ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.centerCard) const Spacer(),
        Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: widget.primaryAccent.withValues(alpha: widget.centerCard ? 0.12 : 1.0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                color: widget.centerCard ? widget.primaryAccent : AppColors.surfaceOf(context),
                size: 44,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          widget.title,
          style: GoogleFonts.inter(fontSize: AppTypography.headlineLarge, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          widget.idLabel,
          style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
          textAlign: TextAlign.center,
        ),
        if (widget.subMessage != null && widget.subMessage!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.subMessage!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context), height: 1.45),
          ),
        ],
        const SizedBox(height: 20),
        widget.mainDetails,
        if (!widget.centerCard) const Spacer(),
        const SizedBox(height: 24),
        if (widget.onCalendarAction != null && !widget.isPending) ...[
          OutlinedButton.icon(
            onPressed: widget.onCalendarAction,
            icon: const Icon(Icons.calendar_month),
            label: const Text('Add to Calendar'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: widget.primaryAccent,
              side: BorderSide(color: widget.primaryAccent),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ElevatedButton(
          onPressed: widget.onPrimaryAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryAccent,
            foregroundColor: AppColors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            widget.primaryActionLabel,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
        if (widget.onSecondaryAction != null && widget.secondaryActionLabel != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onSecondaryAction,
            child: Text(
              widget.secondaryActionLabel!,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ],
      ],
    );

    if (widget.centerCard) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: content,
        ),
      ),
    );
  }
}