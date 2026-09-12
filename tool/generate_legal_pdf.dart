// Generates a single PDF with all Medibond Terms of Service and Privacy Policy
// documents for lawyer review. Run from project root:
//   dart run tool/generate_legal_pdf.dart

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:medibond/core/legal/medibond_legal_content.dart';

const _audiences = <(LegalAudience audience, String label)>[
  (LegalAudience.patient, 'Patient'),
  (LegalAudience.doctor, 'Doctor / Healthcare Provider'),
  (LegalAudience.pharmacy, 'Pharmacy / Medical Store'),
  (LegalAudience.lab, 'Diagnostic Laboratory'),
  (LegalAudience.ambulance, 'Ambulance / Medical Transport'),
];

Future<void> main() async {
  final doc = pw.Document(
    title: 'Medibond Legal Documents',
    author: 'Medibond',
    subject: 'Terms of Service and Privacy Policy — all user roles',
    keywords: 'Medibond, Terms of Service, Privacy Policy, legal',
    creator: 'Medibond legal PDF generator',
  );

  final bodyStyle = pw.TextStyle(fontSize: 10.5, lineSpacing: 1.45);
  final sectionTitleStyle = pw.TextStyle(
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
    lineSpacing: 1.3,
  );
  final docTitleStyle = pw.TextStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
  );
  final roleTitleStyle = pw.TextStyle(
    fontSize: 15,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.indigo900,
  );
  final subtitleStyle = pw.TextStyle(
    fontSize: 11,
    color: PdfColors.grey700,
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Medibond', style: docTitleStyle.copyWith(fontSize: 26)),
          pw.SizedBox(height: 8),
          pw.Text(
            'Terms of Service & Privacy Policy',
            style: docTitleStyle,
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Complete legal documentation for all platform user roles',
            style: subtitleStyle,
          ),
          pw.SizedBox(height: 8),
          pw.Text(DoctorNectLegalContent.lastUpdated, style: subtitleStyle),
          pw.SizedBox(height: 28),
          pw.Text(
            'This document is prepared for legal review. It consolidates role-specific '
            'Terms of Service and Privacy Policy text shown in the Medibond application.',
            style: bodyStyle,
          ),
          pw.SizedBox(height: 20),
          pw.Text('Contents', style: sectionTitleStyle.copyWith(fontSize: 14)),
          pw.SizedBox(height: 10),
          for (final entry in _audiences) ...[
            pw.Text(entry.$2, style: sectionTitleStyle),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12, bottom: 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• Terms of Service', style: bodyStyle),
                  pw.Text('• Privacy Policy', style: bodyStyle),
                ],
              ),
            ),
          ],
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 8),
          pw.Text(
            'Contact: support@medibond.com',
            style: subtitleStyle,
          ),
          pw.Text(
            'Confidential — for legal review purposes',
            style: subtitleStyle.copyWith(fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    ),
  );

  for (final entry in _audiences) {
    for (final type in LegalDocumentType.values) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Medibond', style: subtitleStyle.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    'Page ${context.pageNumber}',
                    style: subtitleStyle,
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(color: PdfColors.grey300, height: 1),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(DoctorNectLegalContent.lastUpdated, style: subtitleStyle.copyWith(fontSize: 9)),
              pw.Text(entry.$2, style: subtitleStyle.copyWith(fontSize: 9)),
            ],
          ),
          build: (context) {
            final sections = DoctorNectLegalContent.sections(
              type: type,
              audience: entry.$1,
            );

            return [
              pw.Text(entry.$2, style: roleTitleStyle),
              pw.SizedBox(height: 4),
              pw.Text(
                DoctorNectLegalContent.title(type),
                style: docTitleStyle.copyWith(fontSize: 16),
              ),
              pw.SizedBox(height: 16),
              for (final section in sections) ...[
                pw.Text(section.title, style: sectionTitleStyle),
                pw.SizedBox(height: 6),
                for (final paragraph in section.paragraphs) ...[
                  pw.Text(paragraph, style: bodyStyle),
                  pw.SizedBox(height: 8),
                ],
                pw.SizedBox(height: 10),
              ],
            ];
          },
        ),
      );
    }
  }

  final outDir = Directory('docs');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final outFile = File('docs/Medibond_Legal_Review.pdf');
  final bytes = await doc.save();
  await outFile.writeAsBytes(bytes);

  // ignore: avoid_print
  print('Generated: ${outFile.absolute.path} (${(bytes.length / 1024).toStringAsFixed(1)} KB)');
}
