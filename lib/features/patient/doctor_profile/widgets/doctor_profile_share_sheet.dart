import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/external_launcher.dart';
import '../models/doctor_profile_detail.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'doctor_poster_widget.dart';
import '../../../../core/theme/app_typography.dart';

abstract final class DoctorProfileShareSheet {
  DoctorProfileShareSheet._();

  static String shareMessage(DoctorProfileDetail doctor) {
    final lines = <String>[];

    lines.add('Doctor: Dr. ${doctor.name}');
    lines.add('Specialization: ${doctor.specialization}');
    lines.add(
        'Rating: ${doctor.rating.toStringAsFixed(1)}/5.0 (${doctor.reviewCount} reviews)');
    lines.add('');

    if (doctor.clinicName.trim().isNotEmpty) {
      lines.add('Clinic: ${doctor.clinicName}');
    }
    if (doctor.area.trim().isNotEmpty) {
      lines.add('Area: ${doctor.area}');
    }
    lines.add('');

    if (doctor.about.isNotEmpty) {
      lines.add('About:');
      lines.add(doctor.about);
      lines.add('');
    }

    if (doctor.awards.isNotEmpty) {
      lines.add('Achievements:');
      for (final award in doctor.awards) {
        lines.add('- $award');
      }
      lines.add('');
    }

    if (doctor.phone.trim().isNotEmpty &&
        !doctor.phone.toLowerCase().contains('contact via')) {
      lines.add('Contact: ${doctor.phone}');
    }
    if (doctor.mapsUrl.trim().isNotEmpty) {
      lines.add('Map: ${doctor.mapsUrl.trim()}');
    }

    if (doctor.photoUrl != null && doctor.photoUrl!.trim().isNotEmpty) {
      lines.add('');
      lines.add('Photo: ${doctor.photoUrl!.trim()}');
    }

    return lines.join('\n');
  }

  static Future<void> show(BuildContext context, DoctorProfileDetail doctor) {
    final message = shareMessage(doctor);

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Share doctor profile',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image, color: AppColors.doctorBlue),
                  title: Text('Share as Image Poster',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Generate a beautiful image card',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);

                    try {
                      final screenshotController = ScreenshotController();
                      final bytes =
                          await screenshotController.captureFromWidget(
                        DoctorPosterWidget(doctor: doctor),
                        delay: const Duration(milliseconds: 100),
                        context: context,
                      );

                      final xFile = XFile.fromData(bytes,
                          mimeType: 'image/png', name: 'doctor_poster.png');
                      await Share.shareXFiles([xFile],
                          text: 'Check out Dr. ${doctor.name} on DoctorNect!');
                    } catch (e) {
                      if (!context.mounted) return;
                      AppToast.info(context, 'Failed to generate poster');
                    }
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.whatsapp,
                      color: Color(0xFF25D366)),
                  title: Text('WhatsApp',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Share via WhatsApp',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ExternalLauncher.shareViaWhatsApp(
                      text: message,
                      context: context,
                    );
                    if (!context.mounted || ok) return;
                    AppToast.info(context, 'Could not open WhatsApp');
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.sms_outlined, color: AppColors.patientTeal),
                  title: Text('SMS',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Share via text message',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ExternalLauncher.shareSmsBody(
                      body: message,
                      context: context,
                    );
                    if (!context.mounted || ok) return;
                    AppToast.info(context, 'Could not open SMS app');
                  },
                ),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.telegram,
                      color: Color(0xFF0088CC)),
                  title: Text('Telegram',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Share via Telegram',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ExternalLauncher.shareViaTelegram(
                      text: message,
                      url: doctor.mapsUrl,
                      context: context,
                    );
                    if (!context.mounted || ok) return;
                    AppToast.info(context, 'Could not open Telegram');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.more_horiz,
                      color: AppColors.textPrimaryOf(context)),
                  title: Text('More options...',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Share using other apps',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ExternalLauncher.shareText(message, context: context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
