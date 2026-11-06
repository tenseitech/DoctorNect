import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Minimal emergency sheet: hotline call only (no in-app ambulance booking).
class EmergencyHotlineSheet extends StatelessWidget {
  const EmergencyHotlineSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EmergencyHotlineSheet(),
    );
  }

  Future<void> _callHotline(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emergency_rounded,
                    color: Color(0xFFDC2626),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency assistance',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        'Call the national emergency hotline',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _callHotline('108'),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone_in_talk_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Call 108 Emergency Hotline',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.headlineSmall,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Toll-free immediate trauma & cardiac response',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.labelMedium,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
