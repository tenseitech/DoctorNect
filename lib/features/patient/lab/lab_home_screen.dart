import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../doctor/clinical/data/community_investigations_repository.dart';
import '../../doctor/clinical/models/clinical_models.dart' hide LabTestItem;
import '../../doctor/clinical/prescription/widgets/prescription_form_sections.dart';
import '../profile/data/patient_profile_mock.dart';
import '../records/data/patient_lab_booking_store.dart';
import '../widgets/patient_flat_section.dart';
import '../widgets/patient_screen_title_bar.dart';
import 'my_labs_screen.dart';
import 'data/patient_lab_booking_filters.dart';
import 'data/patient_lab_catalog_builder.dart';
import 'lab_booking_flow_screen.dart';
import 'lab_test_detail_screen.dart';
import 'models/lab_models.dart';
import 'patient_lab_bookings_screen.dart';
import 'utils/patient_lab_age_guard.dart';
import 'utils/patient_selected_investigations_mapper.dart';
import 'widgets/lab_category_accordion.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import '../../../core/theme/app_typography.dart';

class LabHomeScreen extends StatefulWidget {
  const LabHomeScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  State<LabHomeScreen> createState() => _LabHomeScreenState();
}

class _LabHomeScreenState extends State<LabHomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _expandedCategories = {};
  bool _seededExpandedCategory = false;
  late Future<LabCatalog> _catalogFuture;
  late final PrescriptionDraft _investigationsDraft;

  @override
  void initState() {
    super.initState();
    final profile = PatientProfileMock.profile;
    _investigationsDraft = PrescriptionDraft(
      patient: PatientClinicalContext(
        patientName: profile.name.isNotEmpty
            ? profile.name
            : PatientSession.loggedInPatientName,
        age: profile.age,
        gender: profile.gender,
        patientId: PatientSession.loggedInPatientId,
      ),
    );
    _catalogFuture = FirestoreService.instance.labCatalog.fetchCatalog();
    unawaited(CommunityInvestigationsRepository.instance.fetchAll());
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isNotEmpty) {
      unawaited(
        PatientLabBookingStore.instance
            .refreshForPatient(patientId, preferCache: true),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showPackagesComingSoon() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.labPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_offer_outlined,
                  color: AppColors.labPurple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Packages',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTypography.headlineSmall),
              ),
            ),
          ],
        ),
        content: Text(
          'Health packages are coming soon. You will be able to book bundled checkups at better value.',
          style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              color: AppColors.textSecondaryOf(context),
              height: 1.45),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.labPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Got it',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  bool _matchesSearch(LabTestItem test, String query) {
    if (query.isEmpty) return true;
    final name = test.name.toLowerCase();
    final category = test.category?.toLowerCase() ?? '';
    return name.contains(query) || category.contains(query);
  }

  List<LabTestItem> _filteredTests(LabCatalog catalog) {
    final query = _searchController.text.trim().toLowerCase();
    return catalog.tests.where((test) => _matchesSearch(test, query)).toList();
  }

  void _openTestDetail(
      BuildContext context, LabCatalog catalog, LabTestItem test) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabTestDetailScreen(
          test: test,
          partnerLabs: catalog.partnerLabs,
        ),
      ),
    );
  }

  void _openMyLabs() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MyLabsScreen()));
  }

  void _openBookings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientLabBookingsScreen()),
    );
  }

  Widget _bookingsHeaderButton() {
    return ListenableBuilder(
      listenable: PatientLabBookingStore.instance,
      builder: (context, _) {
        final upcomingCount = PatientLabBookingFilters.upcoming(
          PatientLabBookingStore.instance
              .forPatient(PatientSession.loggedInPatientId),
        ).length;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openBookings,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6D5BD0), AppColors.labPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.labPurple.withValues(alpha: 0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_note_rounded,
                      size: 18, color: AppColors.white),
                  const SizedBox(width: 7),
                  Text(
                    'Bookings',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w700,
                      color: AppColors.surfaceOf(context),
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (upcomingCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context)
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: AppColors.surfaceOf(context)
                                .withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '$upcomingCount',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w800,
                          color: AppColors.surfaceOf(context),
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _selectedInvestigationCount() {
    return _investigationsDraft.validInvestigations.length +
        _investigationsDraft.bodyParts.length;
  }

  void _clearSelectedInvestigations() {
    if (!mounted) return;
    setState(() {
      _investigationsDraft.investigations.clear();
      _investigationsDraft.bodyParts.clear();
      _investigationsDraft.bodyPartNotes.clear();
    });
  }

  void _proceedWithSelectedTests() {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      AppToast.info(context, 'Please sign in as a patient to book lab tests.');
      return;
    }

    final tests =
        PatientSelectedInvestigationsMapper.toLabTests(_investigationsDraft);
    if (tests.isEmpty) {
      AppToast.info(context, 'Select at least one test to continue.');
      return;
    }

    if (!PatientLabAgeGuard.profileAgeValid()) {
      AppToast.info(context, PatientLabAgeGuard.missingAgeSnackbarMessage);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabBookingFlowScreen(
          tests: tests,
          submitAsRequest: true,
          onBookingCompleted: _clearSelectedInvestigations,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final compact = ResponsiveLayout.isCompact(context);

    return Row(
      children: [
        Expanded(
          child: _LabQuickAction(
            icon: Icons.assignment_outlined,
            label: 'My labs',
            onTap: _openMyLabs,
          ),
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: _LabQuickAction(
            icon: Icons.local_offer_outlined,
            label: 'Packages',
            onTap: _showPackagesComingSoon,
          ),
        ),
      ],
    );
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_expandedCategories.contains(category)) {
        _expandedCategories.remove(category);
      } else {
        _expandedCategories.add(category);
      }
    });
  }

  String? _firstCategoryName;

  void _restoreDefaultExpandedCategory() {
    final first = _firstCategoryName;
    if (first == null) return;
    _expandedCategories
      ..clear()
      ..add(first);
  }

  void _scheduleDefaultExpandedCategory(List<String> categoryOrder) {
    if (_seededExpandedCategory || categoryOrder.isEmpty) return;
    final first = categoryOrder.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seededExpandedCategory) return;
      setState(() {
        _firstCategoryName = first;
        _expandedCategories.add(first);
        _seededExpandedCategory = true;
      });
    });
  }

  Widget _buildSearchField(List<String> categoryOrder) {
    final isWide = !ResponsiveLayout.isCompact(context);

    return TextField(
      controller: _searchController,
      onChanged: (_) {
        final q = _searchController.text.trim().toLowerCase();
        setState(() {
          if (q.isEmpty) {
            _restoreDefaultExpandedCategory();
          } else {
            _expandedCategories
              ..clear()
              ..addAll(categoryOrder);
          }
        });
      },
      style: GoogleFonts.inter(
          fontSize: isWide ? 15 : 14, color: AppColors.textPrimaryOf(context)),
      decoration: InputDecoration(
        hintText: 'Search tests, health packages…',
        hintStyle: GoogleFonts.inter(
            fontSize: isWide ? 15 : 14,
            color: AppColors.textSecondaryOf(context)),
        prefixIcon: Icon(Icons.search_rounded, color: AppColors.labPurple),
        filled: true,
        fillColor: AppColors.cardBgOf(context),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16, vertical: isWide ? 14 : 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: AppColors.labPurple.withValues(alpha: 0.55), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildTestsSection(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final selectedCount = _selectedInvestigationCount();
    final profileAgeValid = PatientLabAgeGuard.profileAgeValid();

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 20,
          compact ? 14 : 16,
          compact ? 16 : 20,
          compact ? 14 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!profileAgeValid) ...[
              Text(
                'Booking for ${PatientLabAgeGuard.selfAgeLabel()}',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 8),
              Text(
                PatientLabAgeGuard.missingAgeHint,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.error,
                    height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            PrescriptionInvestigationsSection(
              draft: _investigationsDraft,
              allowCustomTests: false,
              allowClinicalNotes: false,
              onChanged: () => setState(() {}),
              collapsible: true,
              initiallyExpanded: true,
            ),
            if (selectedCount > 0) ...[
              const SizedBox(height: 16),
              LabPrimaryButton(
                label: 'Proceed with selected tests ($selectedCount)',
                enabled: profileAgeValid,
                onPressed: _proceedWithSelectedTests,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogBody(LabCatalog catalog) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredTests = _filteredTests(catalog);
    final groupedTests = PatientLabCatalogBuilder.grouped(filteredTests);
    final categoryOrder = groupedTests.keys.toList();
    if (categoryOrder.isNotEmpty) {
      _firstCategoryName ??= categoryOrder.first;
      _scheduleDefaultExpandedCategory(categoryOrder);
    }
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);

    final sections = <Widget>[
      ColoredBox(
        color: AppColors.surfaceOf(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveLayout.isCompact(context) ? 16 : 20,
            ResponsiveLayout.isCompact(context) ? 14 : 18,
            ResponsiveLayout.isCompact(context) ? 16 : 20,
            ResponsiveLayout.isCompact(context) ? 10 : 12,
          ),
          child: _buildSearchField(categoryOrder),
        ),
      ),
      ColoredBox(
        color: AppColors.surfaceOf(context),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveLayout.isCompact(context) ? 16 : 20,
            0,
            ResponsiveLayout.isCompact(context) ? 16 : 20,
            ResponsiveLayout.isCompact(context) ? 14 : 16,
          ),
          child: _buildQuickActions(),
        ),
      ),
      _buildTestsSection(context),
      Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
    ];

    if (query.isNotEmpty) {
      sections.addAll([
        PatientFlatSection(
          shaded: true,
          title: 'Search results',
          subtitle:
              '${filteredTests.length} test${filteredTests.length == 1 ? '' : 's'} found',
          child: filteredTests.isEmpty
              ? Text(
                  'No tests found',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondaryOf(context)),
                )
              : LabCategoryAccordionSection(
                  groupedTests: groupedTests,
                  categoryOrder: categoryOrder,
                  expandedCategories: _expandedCategories,
                  onToggleCategory: _toggleCategory,
                  onTestTap: (test) => _openTestDetail(context, catalog, test),
                  emptyMessage: 'No tests found',
                ),
        ),
      ]);
    }

    final scroll = ListView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      children: sections,
    );

    if (widget.embeddedInShell) {
      return ColoredBox(
        color: AppColors.cardBgOf(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PatientScreenTitleBar(
              title: 'Lab',
              subtitle: 'Book tests & health packages',
              trailing: Align(
                alignment: Alignment.center,
                child: _bookingsHeaderButton(),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: scroll,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text('My Lab',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _bookingsHeaderButton()),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: scroll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LabCatalog>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          final loading = const Center(
            child: CircularProgressIndicator(color: AppColors.labPurple),
          );
          if (widget.embeddedInShell) {
            return ColoredBox(
              color: AppColors.cardBgOf(context),
              child: Column(
                children: [
                  PatientScreenTitleBar(
                    title: 'Lab',
                    subtitle: 'Book tests & health packages',
                    trailing: Align(
                      alignment: Alignment.center,
                      child: _bookingsHeaderButton(),
                    ),
                  ),
                  Expanded(child: loading),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.cardBgOf(context),
            appBar: AppBar(
              title: Text('My Lab',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              backgroundColor: AppColors.surfaceOf(context),
              foregroundColor: AppColors.textPrimaryOf(context),
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: _bookingsHeaderButton()),
                ),
              ],
            ),
            body: loading,
          );
        }

        return _buildCatalogBody(snapshot.data!);
      },
    );
  }
}

class _LabQuickAction extends StatelessWidget {
  const _LabQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.labPurple.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.labPurple.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.labPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color:
                    AppColors.textSecondaryOf(context).withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
