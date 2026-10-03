import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';

import 'package:flutter/material.dart';
import '../../../core/auth/profile_action_guard.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/firebase/ambulance_auth_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../data/ambulance_store.dart';
import '../../../core/theme/app_typography.dart';

class AmbulanceAvailabilityToggle extends StatefulWidget {
  const AmbulanceAvailabilityToggle({super.key, required this.ambulanceId});

  final String ambulanceId;

  @override
  State<AmbulanceAvailabilityToggle> createState() =>
      _AmbulanceAvailabilityToggleState();
}

class _AmbulanceAvailabilityToggleState
    extends State<AmbulanceAvailabilityToggle> {
  bool _saving = false;
  bool? _localValue;

  Future<void> _onChanged(bool value) async {
    if (!ProfileActionGuard.isAllowed(UserType.ambulance)) {
      ProfileActionGuard.showPopup(context, UserType.ambulance);
      return;
    }
    setState(() {
      _localValue = value;
      _saving = true;
    });

    final signedIn = await AmbulanceAuthHelper.ensureSignedIn();
    if (!signedIn) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _localValue = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect. Please try again.')),
      );
      return;
    }

    final ok = await FirestoreService.instance.ambulance.updateAvailability(
      widget.ambulanceId,
      value,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) {
        _localValue = null; // revert to store value
      }
    });
    if (!ok) {
      AppToast.info(
        context,
        'Could not update availability. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AmbulanceStore.instance,
      builder: (context, _) {
        final live = AmbulanceStore.instance.findAmbulance(widget.ambulanceId);
        final isOnline = _localValue ?? live?.available ?? true;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isOnline
                  ? const Color(0xFF16A34A)
                      .withValues(alpha: isDark ? 0.25 : 0.45)
                  : AppColors.borderOf(context)
                      .withValues(alpha: isDark ? 0.2 : 0.6),
            ),
          ),
          color: isOnline
              ? (isDark
                  ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                  : const Color(0xFFF0FDF4))
              : AppColors.surfaceOf(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isOnline ? Icons.circle : Icons.circle_outlined,
                  size: 12,
                  color: isOnline
                      ? (isDark
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFF16A34A))
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnline ? 'Online for patient requests' : 'Offline',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w700,
                          color: isOnline
                              ? (isDark
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF16A34A))
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Stays on even after logout or closing the app',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Switch(
                    value: isOnline,
                    onChanged: _onChanged,
                    activeThumbColor: const Color(0xFF16A34A),
                    activeTrackColor:
                        const Color(0xFF16A34A).withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
