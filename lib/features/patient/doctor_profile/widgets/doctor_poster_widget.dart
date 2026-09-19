import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/widgets/resampled_network_image.dart';
import '../models/doctor_profile_detail.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorPosterWidget extends StatelessWidget {
  const DoctorPosterWidget({super.key, required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    final awards = doctor.awards.isNotEmpty 
        ? doctor.awards 
        : ['Highly Rated Practitioner on DoctorNect', 'Dedicated to Patient Care'];
        
    final aboutText = doctor.about.isNotEmpty 
        ? doctor.about 
        : 'Experienced ${doctor.specialization} providing excellent medical care and consultation.';

    return Container(
      width: 600,
      height: 800,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(40),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2), 
              blurRadius: 20, 
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Avatar
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0F766E), width: 4),
                color: Colors.grey.shade100,
              ),
              clipBehavior: Clip.antiAlias,
              child: doctor.photoUrl != null && doctor.photoUrl!.isNotEmpty
                  ? ResampledNetworkImageWidget(
                      url: doctor.photoUrl!,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person, size: 80, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // Name
            Text(
              'Dr. ${doctor.name}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: AppTypography.headlineLarge, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            // Specialization & Rating
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    doctor.specialization,
                    style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w600, color: const Color(0xFF0F766E)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('•', style: TextStyle(color: Color(0xFF0F766E))),
                  ),
                  const Icon(Icons.star, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 4),
                  Text(
                    doctor.rating.toStringAsFixed(1),
                    style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // About
            Text(
              'About',
              style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            Text(
              aboutText,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, height: 1.5, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 32),
            // Achievements
            Text(
              'Achievements',
              style: GoogleFonts.inter(fontSize: AppTypography.headlineSmall, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            ...awards.take(3).map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF0F766E), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a,
                      style: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )),
            const Spacer(),
            // Footer
            Container(
              padding: const EdgeInsets.only(top: 24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_hospital, color: Color(0xFF0F766E), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'DoctorNect',
                    style: GoogleFonts.outfit(fontSize: AppTypography.headlineLarge, fontWeight: FontWeight.w800, color: const Color(0xFF0F766E)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
