import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import 'ambulance_data_section.dart';
import 'lab_data_section.dart';
import 'patient_data_section.dart';
import 'pharmacy_data_section.dart';
import '../../../../core/theme/app_typography.dart';

class DataHubSection extends StatelessWidget {
  const DataHubSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DataHub')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Text(
                'Reports & Analytics',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.people_alt_outlined,
                color: AppColors.practoTeal,
                title: 'Patient Data',
                subtitle:
                    'Weekly · Monthly · Yearly · Custom reports, PDF export',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PatientDataSection()),
                ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.local_pharmacy_outlined,
                color: AppColors.pharmacyGreen,
                title: 'Pharmacy Data',
                subtitle: 'Connected stores, prescription deliveries & status',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PharmacyDataSection()),
                ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.biotech_outlined,
                color: AppColors.labPurple,
                title: 'Lab Data',
                subtitle: 'Lab reports ordered, patient-wise test history',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LabDataSection()),
                ),
              ),
              const SizedBox(height: 12),
              _HubCard(
                icon: Icons.emergency_outlined,
                color: Colors.red[600]!,
                title: 'Ambulance Data',
                subtitle: 'Registered providers & dispatch bookings',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AmbulanceDataSection()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
