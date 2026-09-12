import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';

/// Invite control: Invite → Invite Sent (brief) → Revoke Invite.
class DoctorInviteActionButton extends StatefulWidget {
  const DoctorInviteActionButton({
    super.key,
    required this.isPending,
    required this.onInvite,
    required this.onRevoke,
    required this.accentColor,
    this.inviteSentDuration = const Duration(seconds: 2),
    this.fullWidth = false,
  });

  final bool isPending;
  final VoidCallback onInvite;
  final VoidCallback onRevoke;
  final Color accentColor;
  final Duration inviteSentDuration;
  final bool fullWidth;

  @override
  State<DoctorInviteActionButton> createState() => _DoctorInviteActionButtonState();
}

class _DoctorInviteActionButtonState extends State<DoctorInviteActionButton> {
  Timer? _timer;
  DateTime? _inviteSentAt;
  bool _wasPending = false;

  @override
  void didUpdateWidget(DoctorInviteActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isPending) {
      _clearInviteSentPhase();
    } else if (!_wasPending && widget.isPending && _inviteSentAt == null) {
      // Existing pending invite — show Revoke immediately.
      _wasPending = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _wasPending = widget.isPending;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _clearInviteSentPhase() {
    _timer?.cancel();
    _timer = null;
    _inviteSentAt = null;
    _wasPending = false;
  }

  void _startInviteSentPhase() {
    _inviteSentAt = DateTime.now();
    _wasPending = true;
    _timer?.cancel();
    _timer = Timer(widget.inviteSentDuration, () {
      if (mounted) setState(() => _inviteSentAt = null);
    });
    setState(() {});
  }

  bool get _pendingOrSending =>
      widget.isPending || _inviteSentAt != null;

  bool get _showInviteSentBrief =>
      _pendingOrSending &&
      _inviteSentAt != null &&
      DateTime.now().difference(_inviteSentAt!) < widget.inviteSentDuration;

  void _handleInvite() {
    widget.onInvite();
    _startInviteSentPhase();
  }

  ButtonStyle _buttonStyle({Color? foreground, Color? side, bool disabled = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: disabled ? AppColors.textSecondaryOf(context) : null,
      side: side != null ? BorderSide(color: side) : null,
      padding: widget.fullWidth
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: widget.fullWidth ? const Size(double.infinity, 44) : const Size(0, 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_pendingOrSending) {
      return OutlinedButton(
        onPressed: _handleInvite,
        style: _buttonStyle(foreground: widget.accentColor),
        child: const Text('Invite'),
      );
    }

    if (_showInviteSentBrief) {
      return OutlinedButton(
        onPressed: null,
        style: _buttonStyle(disabled: true),
        child: Text(
          'Invite Sent',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      );
    }

    return OutlinedButton(
      onPressed: widget.onRevoke,
      style: _buttonStyle(foreground: AppColors.error, side: AppColors.error),
      child: const Text('Revoke Invite'),
    );
  }
}
