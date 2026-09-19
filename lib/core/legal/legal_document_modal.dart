import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'medibond_legal_content.dart';
import '../../core/theme/app_typography.dart';

Future<void> showLegalDocumentModal(
  BuildContext context, {
  required LegalDocumentType type,
  required LegalAudience audience,
  Color accentColor = AppColors.patientTeal,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _LegalDocumentModal(
      type: type,
      audience: audience,
      accentColor: accentColor,
    ),
  );
}

class _LegalDocumentModal extends StatefulWidget {
  const _LegalDocumentModal({
    required this.type,
    required this.audience,
    required this.accentColor,
  });

  final LegalDocumentType type;
  final LegalAudience audience;
  final Color accentColor;

  @override
  State<_LegalDocumentModal> createState() => _LegalDocumentModalState();
}

class _LegalDocumentModalState extends State<_LegalDocumentModal> {
  final _scrollController = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if (atBottom && !_reachedBottom) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = DoctorNectLegalContent.title(widget.type);
    final sections = DoctorNectLegalContent.sections(
        type: widget.type, audience: widget.audience);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DoctorNect',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: widget.accentColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DoctorNectLegalContent.lastUpdated,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final section in sections) ...[
                    Text(
                      section.title,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final paragraph in section.paragraphs) ...[
                      Text(
                        paragraph,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyMedium,
                          height: 1.55,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: AppColors.borderOf(context))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_reachedBottom)
                    Text(
                      'Scroll to the bottom to continue',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  if (!_reachedBottom) const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _reachedBottom
                        ? () => Navigator.of(context).pop()
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      disabledBackgroundColor:
                          widget.accentColor.withValues(alpha: 0.35),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('I Agree'),
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
