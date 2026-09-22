import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/auth/contact_change_otp_service.dart';
import '../core/theme/app_colors.dart';
import 'otp_input.dart';
import 'overflow_safe_layout.dart';
import '../core/theme/app_typography.dart';

/// Verifies a new contact via OTP before saving profile contact changes.
abstract final class ContactChangeOtpDialog {
  static Future<bool?> show(
    BuildContext context, {
    required ContactVerificationChannel channel,
    required String destination,
    required String purpose,
    Color accentColor = AppColors.patientTeal,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContactChangeOtpDialog(
        channel: channel,
        destination: destination,
        purpose: purpose,
        accentColor: accentColor,
      ),
    );
  }
}

class _ContactChangeOtpDialog extends StatefulWidget {
  const _ContactChangeOtpDialog({
    required this.channel,
    required this.destination,
    required this.purpose,
    required this.accentColor,
  });

  final ContactVerificationChannel channel;
  final String destination;
  final String purpose;
  final Color accentColor;

  @override
  State<_ContactChangeOtpDialog> createState() =>
      _ContactChangeOtpDialogState();
}

class _ContactChangeOtpDialogState extends State<_ContactChangeOtpDialog> {
  bool _otpSent = false;
  bool _sending = false;
  String _otp = '';
  String? _error;

  String get _codeTypeLabel => switch (widget.channel) {
        ContactVerificationChannel.mobile => 'OTP',
        ContactVerificationChannel.email => 'Verification Code',
      };

  String get _channelLabel => switch (widget.channel) {
        ContactVerificationChannel.mobile => 'Mobile Number',
        ContactVerificationChannel.email => 'Email Address',
      };

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });

    final error = await ContactChangeOtpService.sendOtp(
      channel: widget.channel,
      target: widget.destination,
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      _otpSent = error == null;
      _error = error;
    });
  }

  Future<void> _verify() async {
    setState(() => _error = null);
    final error = await ContactChangeOtpService.verify(
      channel: widget.channel,
      target: widget.destination,
      otp: _otp,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final masked =
        ContactChangeOtpService.maskTarget(widget.channel, widget.destination);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Verify $_channelLabel',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      ),
      content: scrollableDialogContent(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.channel == ContactVerificationChannel.email
                  ? 'To ${widget.purpose}, enter the 6-digit verification code sent to your new email ($masked).'
                  : 'To ${widget.purpose}, enter the 6-digit OTP sent to your new mobile number ($masked).',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.45),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _sending ? null : _sendOtp,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_otpSent
                      ? 'Resend $_codeTypeLabel'
                      : 'Send $_codeTypeLabel'),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Enter $_codeTypeLabel',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OtpInput(
                initialValue: _otp,
                accentColor: widget.accentColor,
                onChanged: (value) => setState(() {
                  _otp = value;
                  _error = null;
                }),
                onCompleted: (value) {
                  _otp = value;
                  _error = null;
                  setState(() {});
                  _verify();
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (_otpSent)
          FilledButton(
            onPressed: _otp.length == 6 ? _verify : null,
            style: FilledButton.styleFrom(backgroundColor: widget.accentColor),
            child: const Text('Verify'),
          ),
      ],
    );
  }
}
