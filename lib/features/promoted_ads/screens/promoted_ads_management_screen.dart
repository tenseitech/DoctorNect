import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/promoted_ad_model.dart';
import '../../../core/services/promoted_ads_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';
import 'create_promoted_ad_screen.dart';

class PromotedAdsManagementScreen extends StatelessWidget {
  const PromotedAdsManagementScreen({
    super.key,
    required this.providerType,
    required this.providerId,
    required this.providerEmail,
    required this.providerContact,
    required this.isVerified,
  });

  final String providerType;
  final String providerId;
  final String providerEmail;
  final String providerContact;
  final bool isVerified;

  static void showPromotionsPausedDialog(BuildContext context, {String? notice}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.pause_circle_outline_rounded,
            color: Color(0xFFDC2626),
            size: 36,
          ),
        ),
        title: Text(
          'Promotional Ads Paused',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        content: scrollableDialogContent(
          context: ctx,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notice != null && notice.trim().isNotEmpty
                    ? notice.trim()
                    : 'Promotional ads and banner placements are currently paused by the Super Administrator. Please check back later or contact admin support.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondaryOf(ctx),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Status: Paused by Super Admin',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD97706),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Understood',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> open(
    BuildContext context, {
    required String providerType,
    required String providerId,
    required String providerEmail,
    required String providerContact,
    bool isVerified = true,
  }) async {
    try {
      final config = await BannerConfigService.fetchConfig();
      if (!config.enabled) {
        if (context.mounted) {
          showPromotionsPausedDialog(context, notice: config.bannerNotice);
        }
        return;
      }
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PromotedAdsManagementScreen(
          providerType: providerType,
          providerId: providerId,
          providerEmail: providerEmail,
          providerContact: providerContact,
          isVerified: isVerified,
        ),
      ),
    );
  }

  Future<void> _openCreateScreen(BuildContext context) async {
    try {
      final config = await BannerConfigService.fetchConfig();
      if (!config.enabled) {
        if (context.mounted) {
          showPromotionsPausedDialog(context, notice: config.bannerNotice);
        }
        return;
      }
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePromotedAdScreen(
          providerType: providerType,
          providerId: providerId,
          providerEmail: providerEmail,
          providerContact: providerContact,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<BannerConfigModel>(
      stream: BannerConfigService.streamConfig(),
      builder: (context, configSnap) {
        final config = configSnap.data ?? const BannerConfigModel();
        final isBannerEnabled = config.enabled;

        return Scaffold(
          backgroundColor: AppColors.surfaceOf(context),
          appBar: AppBar(
            title: Text(
              'My Banner Ads',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            elevation: 0,
          ),
          floatingActionButton: isBannerEnabled
              ? FloatingActionButton.extended(
                  onPressed: () => _openCreateScreen(context),
                  backgroundColor: AppColors.doctorBlue,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text(
                    'Create New Ad',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                )
              : null,
          body: Column(
            children: [
              if (!isBannerEnabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      const Icon(Icons.pause_circle_outline, color: Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          config.bannerNotice.isNotEmpty
                              ? config.bannerNotice
                              : 'Banner promotion system is currently paused by administrator.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<List<PromotedAdModel>>(
                  stream: PromotedAdsService.streamProviderAds(providerId),
                  builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.doctorBlue));
          }

          final ads = snapshot.data ?? [];

          if (ads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF312E81) : const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF6366F1) : AppColors.doctorBlue).withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          TablerIcons.speakerphone,
                          size: 44,
                          color: isDark ? const Color(0xFFC7D2FE) : AppColors.doctorBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Promotional Ads Yet',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Promote your medical practice on the Patient Home screen banner carousel to gain maximum visibility.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _openCreateScreen(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create Promotional Ad'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.doctorBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: ads.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final ad = ads[index];
                return _PromotedAdCard(ad: ad);
              },
            );
          },
        ),
      ),
    ],
  ),
);
      },
    );
  }
}

class _PromotedAdCard extends StatelessWidget {
  const _PromotedAdCard({required this.ad});

  final PromotedAdModel ad;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (ad.status) {
      'active' => const Color(0xFF16A34A),
      'pending_payment' => const Color(0xFFEA580C),
      'expired' => Colors.grey.shade600,
      'rejected' => Colors.red.shade700,
      _ => Colors.blue.shade700,
    };

    final statusLabel = switch (ad.status) {
      'active' => 'ACTIVE',
      'pending_payment' => 'PENDING PAYMENT',
      'expired' => 'EXPIRED',
      'rejected' => 'FAILED / REJECTED',
      _ => 'DRAFT',
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image & Status Overlay
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: ad.imageUrl.isNotEmpty
                      ? Image.network(ad.imageUrl, fit: BoxFit.cover)
                      : Container(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (ad.isActive)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          ad.remainingTimeString,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Content Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ad.title,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    Text(
                      '₹${ad.amountPaid}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.doctorBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  ad.description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: AppColors.borderOf(context)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Duration: ${_formatDuration(ad.durationHours)}',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      ad.paymentStatus == 'verified' ? 'Payment Verified' : 'Payment Pending',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ad.paymentStatus == 'verified' ? const Color(0xFF16A34A) : Colors.orange,
                      ),
                    ),
                  ],
                ),
                if (ad.isActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Active paid ads are read-only to ensure ad integrity.',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int hours) => switch (hours) {
        24 => '1 Day',
        72 => '3 Days',
        168 => '1 Week',
        720 => '1 Month',
        _ => '$hours Hours',
      };
}
