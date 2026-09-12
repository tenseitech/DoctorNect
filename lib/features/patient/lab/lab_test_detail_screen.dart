import '../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../data/patient_favorites_store.dart';
import '../profile/data/patient_profile_mock.dart';
import 'lab_booking_flow_screen.dart';
import 'lab_city_filter.dart';
import 'models/lab_models.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';

class LabTestDetailScreen extends StatefulWidget {
  const LabTestDetailScreen({
    super.key,
    required this.test,
    required this.partnerLabs,
  });

  final LabTestItem test;
  final List<PartnerLab> partnerLabs;

  @override
  State<LabTestDetailScreen> createState() => _LabTestDetailScreenState();
}

class _LabTestDetailScreenState extends State<LabTestDetailScreen> {
  final _favoritesStore = PatientFavoritesStore.instance;
  Map<String, RegisteredLabProfile> _registryById = const {};
  bool _loadingRegistry = true;
  PartnerLab? _selectedLab;

  @override
  void initState() {
    super.initState();
    _favoritesStore.addListener(_onStoreChanged);
    PatientProfileMock.listenable.addListener(_onStoreChanged);
    unawaited(_loadRegistry());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSelectedLab();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _favoritesStore.removeListener(_onStoreChanged);
    PatientProfileMock.listenable.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _syncSelectedLab();
    setState(() {});
  }

  Future<void> _loadRegistry() async {
    final labs = await FirestoreService.instance.lab.fetchVerifiedLabs();
    if (!mounted) return;
    setState(() {
      _registryById = {for (final lab in labs) lab.id: lab};
      _loadingRegistry = false;
    });
    _syncSelectedLab();
    if (mounted) setState(() {});
  }

  void _selectLab(PartnerLab lab) {
    setState(() => _selectedLab = lab);
  }

  void _syncSelectedLab() {
    final bookableLabs = _bookableLabs(_myLabs(), _availableLabs());
    if (bookableLabs.isEmpty) {
      _selectedLab = null;
      return;
    }

    if (_selectedLab != null) {
      final selectedKey = LabCityFilter.partnerLabKey(_selectedLab!);
      final match = bookableLabs.where(
        (lab) => LabCityFilter.partnerLabKey(lab) == selectedKey,
      );
      if (match.isNotEmpty) {
        _selectedLab = match.first;
        return;
      }
    }

    _selectedLab = bookableLabs.first;
  }

  List<PartnerLab> _myLabs() {
    final hidden = _favoritesStore.hiddenLabKeys;
    return _favoritesStore.addedLabs
        .where((lab) => !hidden.contains(lab.key))
        .map((lab) => lab.toPartnerLab())
        .toList(growable: false);
  }

  List<PartnerLab> _availableLabs() {
    final city = LabCityFilter.patientCity();
    if (city.isEmpty) return const [];

    final excludedKeys = <String>{
      ..._favoritesStore.addedLabs.map((lab) => lab.key),
      ..._favoritesStore.hiddenLabKeys,
    };

    return widget.partnerLabs
        .where((lab) {
          final key = LabCityFilter.partnerLabKey(lab);
          if (excludedKeys.contains(key)) return false;
          return LabCityFilter.partnerLabInCity(lab, city, _registryById);
        })
        .toList(growable: false);
  }

  List<PartnerLab> _bookableLabs(List<PartnerLab> myLabs, List<PartnerLab> availableLabs) {
    final seen = <String>{};
    final combined = <PartnerLab>[];

    void addLab(PartnerLab lab) {
      final key = LabCityFilter.partnerLabKey(lab);
      if (!seen.add(key)) return;
      combined.add(lab);
    }

    for (final lab in myLabs) {
      addLab(lab);
    }
    for (final lab in availableLabs) {
      addLab(lab);
    }

    if (combined.isNotEmpty) return combined;
    return widget.partnerLabs;
  }

  @override
  Widget build(BuildContext context) {
    final sampleLabel = switch (widget.test.sampleType) {
      SampleType.blood => 'Blood',
      SampleType.urine => 'Urine',
      SampleType.stool => 'Stool',
    };
    final myLabs = _myLabs();
    final availableLabs = _availableLabs();
    final bookableLabs = _bookableLabs(myLabs, availableLabs);
    final patientCity = LabCityFilter.patientCity();
    final selectedLab = _selectedLab;

    bool isSelected(PartnerLab lab) {
      if (selectedLab == null) return false;
      return LabCityFilter.partnerLabKey(lab) == LabCityFilter.partnerLabKey(selectedLab);
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: LabPageLayout.appBar(
        context,
        title: 'Test Details',
        onBack: () => Navigator.pop(context),
      ),
      body: LabPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabContentCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.test.name,
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  const LabSectionHeader(icon: Icons.checklist_outlined, title: 'Includes'),
                  const SizedBox(height: 8),
                  ...widget.test.parameters.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check, size: 18, color: AppColors.labPurple),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(p, style: GoogleFonts.inter(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Divider(height: 1, color: AppColors.borderOf(context)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        label: widget.test.fastingRequired ? 'Fasting required' : 'No fasting',
                      ),
                      _InfoChip(label: sampleLabel),
                      _InfoChip(label: 'Report in ${widget.test.reportHours} hrs'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const LabSectionHeader(
                    icon: Icons.local_hospital_outlined,
                    title: 'My Labs',
                  ),
                  const SizedBox(height: 12),
                  if (myLabs.isEmpty)
                    _LabsEmptyNote(
                      message: 'No labs added yet. Add labs from search or choose one below.',
                    )
                  else
                    ...myLabs.map(
                      (lab) => _LabPartnerTile(
                        lab: lab,
                        selected: isSelected(lab),
                        onTap: () => _selectLab(lab),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const LabSectionHeader(
                    icon: Icons.location_city_outlined,
                    title: 'Available Labs',
                  ),
                  const SizedBox(height: 12),
                  if (_loadingRegistry)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (patientCity.isEmpty)
                    const _LabsEmptyNote(
                      message: 'Add your city in profile to see nearby labs.',
                    )
                  else if (availableLabs.isEmpty)
                    _LabsEmptyNote(
                      message: 'No labs found in $patientCity right now.',
                    )
                  else
                    ...availableLabs.map(
                      (lab) => _LabPartnerTile(
                        lab: lab,
                        selected: isSelected(lab),
                        onTap: () => _selectLab(lab),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LabPrimaryButton(
              label: 'Book This Test',
              onPressed: selectedLab == null
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LabBookingFlowScreen(
                            tests: [widget.test],
                            partnerLabs: bookableLabs,
                            preselectedLab: selectedLab,
                            lockSelectedLab: true,
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.labPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.labPurple),
      ),
    );
  }
}

class _LabsEmptyNote extends StatelessWidget {
  const _LabsEmptyNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        message,
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context), height: 1.35),
      ),
    );
  }
}

class _LabPartnerTile extends StatelessWidget {
  const _LabPartnerTile({
    required this.lab,
    required this.selected,
    required this.onTap,
  });

  final PartnerLab lab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.labPurple.withValues(alpha: 0.06)
                  : AppColors.cardBgOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.labPurple : AppColors.borderOf(context),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.labPurple.withValues(alpha: selected ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.local_hospital_outlined,
                    color: AppColors.labPurple,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lab.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(
                        lab.area,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppColors.labPurple : AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
