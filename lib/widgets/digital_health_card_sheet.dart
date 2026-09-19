import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../core/enums/user_type.dart';
import '../core/notifications/app_toast.dart';
import '../core/theme/app_colors.dart';
import '../features/doctor/profile/data/doctor_profile_store.dart';
import '../features/patient/profile/data/patient_profile_mock.dart';
import '../core/theme/app_typography.dart';

/// Modal sheet displaying a digital health ID card with scannable QR pass.
class DigitalHealthCardSheet extends StatefulWidget {
  const DigitalHealthCardSheet({super.key, required this.userType});

  final UserType userType;

  static void show(BuildContext context, {required UserType userType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DigitalHealthCardSheet(userType: userType),
    );
  }

  @override
  State<DigitalHealthCardSheet> createState() => _DigitalHealthCardSheetState();
}

class _DigitalHealthCardSheetState extends State<DigitalHealthCardSheet> {
  final GlobalKey _passCardBoundaryKey = GlobalKey();
  bool _sharingPass = false;

  Future<void> _sharePass({
    required bool isDoctor,
    required String name,
    required String subtitle,
    required String regNumber,
    required String stateCouncil,
  }) async {
    if (isDoctor) {
      await Share.share(
        'Dr. $name — Council Reg: $regNumber ($stateCouncil). Verified via DoctorNect.',
      );
      return;
    }

    if (_sharingPass) return;
    setState(() => _sharingPass = true);

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final renderObject = _passCardBoundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.attached) {
        throw StateError('Pass card is not ready to share');
      }

      final image = await renderObject.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Could not encode pass card image');
      }

      final xFile = XFile.fromData(
        byteData.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'doctornect_health_pass.png',
      );
      await Share.shareXFiles(
        [xFile],
        text: 'My DoctorNect Health Pass — Verified ✅',
      );
    } catch (_) {
      if (mounted) {
        AppToast.info(context, 'Could not share health pass image');
      }
    } finally {
      if (mounted) {
        setState(() => _sharingPass = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userType = widget.userType;
    final isDoctor = userType == UserType.doctor;
    final doctorProfile = DoctorProfileStore.instance.profile;
    final patientProfile = PatientProfileMock.profile;

    final name = isDoctor
        ? (doctorProfile.fullName.isEmpty ? 'Dr. Doctor' : 'Dr. ${doctorProfile.fullName}')
        : (patientProfile.name.isEmpty ? 'Patient' : patientProfile.name);

    final subtitle = isDoctor
        ? (doctorProfile.specialization.isEmpty ? 'Medical Practitioner' : doctorProfile.specialization)
        : 'Patient ID: P-884210';

    final regNumber = isDoctor
        ? (doctorProfile.councilNumber.isEmpty ? 'MCI-884210' : doctorProfile.councilNumber)
        : 'Blood Group: ${patientProfile.bloodGroup}';

    final stateCouncil = isDoctor
        ? (doctorProfile.stateCouncil.isEmpty ? 'State Medical Council' : doctorProfile.stateCouncil)
        : 'Gender/Age: ${patientProfile.gender}, ${patientProfile.age} yrs';

    final accent = isDoctor ? AppColors.doctorBlue : AppColors.patientTeal;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isDoctor ? 'Digital Doctor Credentials Pass' : 'Digital Health Card ID',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _passCardBoundaryKey,
            child: _DoctorNectPassCard(
              isDoctor: isDoctor,
              name: name,
              subtitle: subtitle,
              regNumber: regNumber,
              stateCouncil: stateCouncil,
              accent: accent,
            ),
          ),
          const SizedBox(height: 24),
          if (isDoctor) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Row(
                children: [
                  CustomPaint(
                    size: const Size(80, 80),
                    painter: _QrCanvasPainter(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan to Verify Pass',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Allows patients and pharmacies to quickly verify doctor registration & credentials.',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sharingPass
                      ? null
                      : () => _sharePass(
                            isDoctor: isDoctor,
                            name: name,
                            subtitle: subtitle,
                            regNumber: regNumber,
                            stateCouncil: stateCouncil,
                          ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: accent),
                    foregroundColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _sharingPass
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share Pass'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoctorNectPassCard extends StatelessWidget {
  const _DoctorNectPassCard({
    required this.isDoctor,
    required this.name,
    required this.subtitle,
    required this.regNumber,
    required this.stateCouncil,
    required this.accent,
  });

  final bool isDoctor;
  final String name;
  final String subtitle;
  final String regNumber;
  final String stateCouncil;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDoctor
              ? [const Color(0xFF1E40AF), const Color(0xFF1D4ED8)]
              : [const Color(0xFF0F766E), const Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.medical_services_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'DoctorNect PASS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'VERIFIED',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDoctor ? 'REGISTRATION NO.' : 'DETAILS',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.65),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          regNumber,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isDoctor ? 'COUNCIL' : 'GENDER/AGE',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.65),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stateCouncil,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCanvasPainter extends CustomPainter {
  _QrCanvasPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final tileSize = size.width / 7;

    // Corner Finder Patterns
    void drawFinder(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, tileSize * 2, tileSize * 2), paint);
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(x + tileSize * 0.5, y + tileSize * 0.5, tileSize, tileSize),
        whitePaint,
      );
    }

    drawFinder(0, 0);
    drawFinder(size.width - tileSize * 2, 0);
    drawFinder(0, size.height - tileSize * 2);

    // Random Data Pixels for QR simulation
    final positions = [
      Offset(tileSize * 3, tileSize * 1),
      Offset(tileSize * 4, tileSize * 2),
      Offset(tileSize * 2, tileSize * 4),
      Offset(tileSize * 5, tileSize * 5),
      Offset(tileSize * 3, tileSize * 3),
      Offset(tileSize * 6, tileSize * 4),
      Offset(tileSize * 4, tileSize * 6),
      Offset(tileSize * 5, tileSize * 3),
    ];

    for (final pos in positions) {
      canvas.drawRect(Rect.fromLTWH(pos.dx, pos.dy, tileSize * 0.8, tileSize * 0.8), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
