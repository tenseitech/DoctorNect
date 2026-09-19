import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

class QuickRxTemplate {
  const QuickRxTemplate({
    required this.title,
    required this.category,
    required this.diagnosis,
    required this.medicines,
    required this.advice,
  });

  final String title;
  final String category;
  final String diagnosis;
  final List<String> medicines;
  final String advice;
}

const List<QuickRxTemplate> kRxTemplates = [
  QuickRxTemplate(
    title: 'Acute Viral Fever & Cold',
    category: 'General Medicine',
    diagnosis: 'Acute Upper Respiratory Tract Infection (J06.9)',
    medicines: [
      'Tab. Paracetamol 650 mg (1-1-1 after food x 3 days)',
      'Tab. Cetirizine 10 mg (0-0-1 at bedtime x 5 days)',
      'Tab. Vitamin C 500 mg (1-0-0 x 7 days)',
    ],
    advice: 'Drink warm fluids, steam inhalation twice daily, rest for 48 hours.',
  ),
  QuickRxTemplate(
    title: 'Hypertension & Cardiac Follow-Up',
    category: 'Cardiology',
    diagnosis: 'Essential Primary Hypertension (I10)',
    medicines: [
      'Tab. Telmisartan 40 mg (1-0-0 before breakfast x 30 days)',
      'Tab. Amlodipine 5 mg (0-0-1 after dinner x 30 days)',
    ],
    advice: 'Low salt diet (<3g/day), daily morning blood pressure tracking, 30 mins brisk walking.',
  ),
  QuickRxTemplate(
    title: 'Type 2 Diabetes Routine Check',
    category: 'Endocrinology',
    diagnosis: 'Type 2 Diabetes Mellitus without complications (E11.9)',
    medicines: [
      'Tab. Metformin 500 mg SR (1-0-1 after meals x 30 days)',
      'Tab. Teneligliptin 20 mg (1-0-0 before breakfast x 30 days)',
    ],
    advice: 'Fasting & PP Blood Sugar test after 15 days, avoid refined sugars and carbs.',
  ),
  QuickRxTemplate(
    title: 'Acidity, Gastritis & GERD',
    category: 'Gastroenterology',
    diagnosis: 'Gastro-esophageal Reflux Disease (K21.9)',
    medicines: [
      'Cap. Pantoprazole 40 mg + Domperidone 30 mg (1-0-0 30 mins before breakfast x 14 days)',
      'Syr. Sucralfate 10 mL (1-1-1 before meals x 7 days)',
    ],
    advice: 'Avoid spicy/oily food, do not lie down immediately after meals.',
  ),
];

/// Sheet enabling doctors to select 1-click clinical prescription templates.
class QuickRxTemplateSheet extends StatelessWidget {
  const QuickRxTemplateSheet({super.key, required this.onSelectTemplate});

  final ValueChanged<QuickRxTemplate> onSelectTemplate;

  static void show(
    BuildContext context, {
    required ValueChanged<QuickRxTemplate> onSelectTemplate,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickRxTemplateSheet(onSelectTemplate: onSelectTemplate),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.doctorBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.note_alt_outlined,
                      color: AppColors.doctorBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '1-Click Clinical Rx Templates',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Select a standard template to instantly pre-fill diagnosis, medicines, dosage, and dietary advice:',
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final t in kRxTemplates) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          onSelectTemplate(t);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cardBgOf(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.borderOf(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    t.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimaryOf(context),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.doctorBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      t.category,
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.labelSmall,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.doctorBlue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t.diagnosis,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: t.medicines
                                    .map(
                                      (m) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceOf(context),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.borderOf(context)),
                                        ),
                                        child: Text(
                                          m,
                                          style: GoogleFonts.inter(
                                            fontSize: AppTypography.labelSmall,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimaryOf(context),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
