import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../data/patient_favorites_store.dart';
import 'my_lab_booking_launcher.dart';
import '../records/data/patient_lab_booking_store.dart';
import '../widgets/patient_favorites_sheets.dart';
import '../../../core/theme/app_typography.dart';

class MyLabsScreen extends StatefulWidget {
  const MyLabsScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  State<MyLabsScreen> createState() => _MyLabsScreenState();
}

class _MyLabsScreenState extends State<MyLabsScreen> {
  final _favoritesStore = PatientFavoritesStore.instance;
  final _labBookingStore = PatientLabBookingStore.instance;

  @override
  void initState() {
    super.initState();
    _favoritesStore.addListener(_onChanged);
    _labBookingStore.addListener(_onChanged);
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isNotEmpty) {
      unawaited(
          _labBookingStore.refreshForPatient(patientId, preferCache: true));
    }
  }

  @override
  void dispose() {
    _favoritesStore.removeListener(_onChanged);
    _labBookingStore.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _bookLab(SavedLabEntry lab) {
    unawaited(showMyLabTestPickerAndBook(context, lab));
  }

  @override
  Widget build(BuildContext context) {
    final labs = _favoritesStore.visibleLabs();

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !widget.embeddedInShell,
        title: Text('My Lab',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.cardBgOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => PatientFavoritesSheets.showAddLabSheet(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.labPurple,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveLayout.contentMaxWidth(context).clamp(0, 560),
          ),
          child: labs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                  child: Text(
                    'No labs in your list yet. Tap Add to search registered labs or book a lab test.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: AppTypography.bodyMedium),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: labs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final lab = labs[index];
                    return _MyLabManageTile(
                      lab: lab,
                      onRemove: () => _favoritesStore.removeLab(lab.key),
                      onBook: () => _bookLab(lab),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MyLabManageTile extends StatelessWidget {
  const _MyLabManageTile({
    required this.lab,
    required this.onRemove,
    required this.onBook,
  });

  final SavedLabEntry lab;
  final VoidCallback onRemove;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(10);
    final buttonTextStyle = GoogleFonts.inter(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w600,
    );

    final removeButton = FilledButton(
      onPressed: onRemove,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.error,
        foregroundColor: AppColors.white,
        minimumSize: const Size(72, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: buttonTextStyle,
      ),
      child: const Text('Remove', textAlign: TextAlign.center),
    );

    final bookButton = FilledButton(
      onPressed: onBook,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.labPurple,
        foregroundColor: AppColors.white,
        minimumSize: const Size(72, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: buttonTextStyle,
      ),
      child: const Text('Book', textAlign: TextAlign.center),
    );

    Widget buildLabInfo() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.labPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.biotech_outlined,
              color: AppColors.labPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lab.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (lab.area.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lab.area,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 460;
            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildLabInfo(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: removeButton),
                      const SizedBox(width: 12),
                      Expanded(child: bookButton),
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: buildLabInfo()),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    removeButton,
                    const SizedBox(width: 10),
                    bookButton,
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
