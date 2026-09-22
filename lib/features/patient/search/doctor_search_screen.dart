import '../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/speciality_mapper.dart';
import '../../../core/constants/specialty_categories.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/location/location_match.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../ambulance/ambulance_booking_screen.dart';
import '../../ambulance/data/ambulance_store.dart';
import '../../ambulance/models/ambulance_models.dart';
import '../data/patient_favorites_store.dart';
import '../data/registered_doctors_store.dart';
import '../home/widgets/home_search_bar.dart';
import '../lab/lab_home_screen.dart';
import '../lab/lab_test_detail_screen.dart';
import '../lab/models/lab_models.dart';
import '../profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../booking/booking_flow_screen.dart';
import '../doctor_profile/patient_doctor_profile_screen.dart';
import '../widgets/doctor_listing_card.dart';
import '../widgets/patient_screen_title_bar.dart';
import 'doctor_search_matcher.dart';
import 'lab_search_matcher.dart';
import 'specialty_search_suggestions.dart';
import 'widgets/lab_search_result_tile.dart';
import 'widgets/patient_doctor_search_bar.dart';
import 'widgets/search_filters_sheet.dart';
import 'widgets/search_specialty_suggestions_panel.dart';
import '../../../core/theme/app_typography.dart';

class DoctorSearchScreen extends StatefulWidget {
  const DoctorSearchScreen({
    super.key,
    this.initialQuery = '',
    this.autofocus = false,
    this.initialSpeciality,
    this.initialCategory,
    this.initialLocationFilter,
    this.nearYouMode = false,
    this.embeddedInShell = false,
    this.onSelectPatientTab,
  });

  final String initialQuery;
  final bool autofocus;
  final String? initialSpeciality;
  final String? initialCategory;
  final String? initialLocationFilter;
  final bool nearYouMode;
  final bool embeddedInShell;

  /// Switches patient shell tabs (2=Labs, 3=Ambulance) without losing bottom nav.
  final ValueChanged<int>? onSelectPatientTab;

  @override
  State<DoctorSearchScreen> createState() => _DoctorSearchScreenState();
}

class _DoctorSearchScreenState extends State<DoctorSearchScreen> {
  late final _searchController =
      TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();
  final _doctorsStore = RegisteredDoctorsStore.instance;
  late final Future<LabCatalog> _catalogFuture =
      FirestoreService.instance.labCatalog.fetchCatalog();
  SearchSort _sort = SearchSort.relevance;
  bool _searchFocused = false;

  String? _specialityCategory;
  String? _locationFilter;
  bool _availableToday = false;
  double? _minRating;
  String? _language;

  String _resolvedCity = '';
  String _resolvedPincode = '';
  bool _resolvingLocation = false;

  @override
  void initState() {
    super.initState();
    _specialityCategory = widget.initialCategory ??
        (widget.initialSpeciality != null &&
                specialtyCategories.containsKey(widget.initialSpeciality)
            ? widget.initialSpeciality
            : null);
    _locationFilter = widget.initialLocationFilter?.trim().isNotEmpty == true
        ? widget.initialLocationFilter!.trim()
        : (widget.nearYouMode ? _defaultPatientCityFilter() : null);
    if (_locationFilter != null) {
      _sort = SearchSort.distance;
    }
    _focusNode.addListener(_onSearchFocusChanged);
    final savedCity = PatientProfileMock.profileAddress.city.trim().isNotEmpty
        ? PatientProfileMock.profileAddress.city.trim()
        : PatientProfileMock.profileCity.trim();
    final savedPin = PatientProfileMock.profileAddress.pincode.trim();
    if (savedCity.isNotEmpty || savedPin.isNotEmpty) {
      _resolvedCity = savedCity;
      _resolvedPincode = savedPin;
    } else {
      _resolvingLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchDeviceLocation();
      });
    }
    AmbulanceStore.instance.addListener(_onAmbulanceStoreChanged);
    FirestoreService.instance.ambulance.fetchRegisteredAmbulances();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doctorsStore.startListening();
      if (widget.autofocus) _focusNode.requestFocus();
    });
  }

  void _onAmbulanceStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchDeviceLocation() async {
    try {
      final loc = await LocationService.getCurrentLocation(
        context: context,
        showToast: false,
      );
      if (mounted && loc != null) {
        setState(() {
          _resolvedCity = loc.city?.trim() ?? '';
          _resolvedPincode = loc.pincode?.trim() ?? '';
          _resolvingLocation = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _resolvingLocation = false;
      });
    }
  }

  void _openAmbulanceBooking() {
    if (widget.onSelectPatientTab != null) {
      widget.onSelectPatientTab!(3);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AmbulanceBookingScreen(
          bookedByRole: AmbulanceBookedByRole.patient,
        ),
      ),
    );
  }

  void _onSearchFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (_searchFocused == focused) return;
    setState(() => _searchFocused = focused);
  }

  List<SpecialtySearchSuggestion> get _specialtySuggestions {
    return SpecialtySearchSuggestions.forQuery(_searchController.text);
  }

  bool get _showSpecialtySuggestions {
    final query = _searchController.text.trim();
    return _searchFocused &&
        query.isNotEmpty &&
        _specialtySuggestions.isNotEmpty;
  }

  bool get _showResults {
    final q = _searchController.text.trim();
    return q.isNotEmpty ||
        _specialityCategory != null ||
        (_locationFilter != null && _locationFilter!.trim().isNotEmpty);
  }

  String get _doctorsSectionTitle {
    final city = _locationFilter?.trim();
    if (city != null && city.isNotEmpty) {
      if (widget.nearYouMode && _searchController.text.trim().isEmpty) {
        return 'Citywide · $city';
      }
      return 'Doctors in $city';
    }
    return 'Doctors';
  }

  @override
  void dispose() {
    AmbulanceStore.instance.removeListener(_onAmbulanceStoreChanged);
    _focusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<LabTestItem> _filteredLabTests(LabCatalog catalog) {
    final q = _searchController.text.trim();
    if (q.isEmpty) return const [];

    final list =
        catalog.tests.where((t) => LabSearchMatcher.matchesTest(t, q)).toList();
    list.sort(
      (a, b) => LabSearchMatcher.relevanceScoreTest(b, q)
          .compareTo(LabSearchMatcher.relevanceScoreTest(a, q)),
    );
    return list;
  }

  List<LabHealthPackage> _filteredLabPackages(LabCatalog catalog) {
    final q = _searchController.text.trim();
    if (q.isEmpty) return const [];

    final list = catalog.packages
        .where((p) => LabSearchMatcher.matchesPackage(p, q))
        .toList();
    list.sort(
      (a, b) => LabSearchMatcher.relevanceScorePackage(b, q)
          .compareTo(LabSearchMatcher.relevanceScorePackage(a, q)),
    );
    return list;
  }

  List<PartnerLab> _filteredPartnerLabs(LabCatalog catalog) {
    final q = _searchController.text.trim();
    if (q.isEmpty) return const [];

    final list = catalog.partnerLabs
        .where((l) => LabSearchMatcher.matchesPartnerLab(l, q))
        .toList();
    list.sort(
      (a, b) => LabSearchMatcher.relevanceScorePartnerLab(b, q)
          .compareTo(LabSearchMatcher.relevanceScorePartnerLab(a, q)),
    );
    return list;
  }

  LabTestItem _testFromPackage(LabHealthPackage pkg) {
    return LabTestItem(
      id: pkg.id,
      name: pkg.name,
      parameters: [pkg.description],
      fastingRequired: true,
      sampleType: SampleType.blood,
      reportHours: 48,
    );
  }

  void _openLabTest(LabCatalog catalog, LabTestItem test) {
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

  void _openLabHome() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LabHomeScreen()),
    );
  }

  String? _defaultPatientCityFilter() {
    final addressCity = PatientProfileMock.profileAddress.city.trim();
    if (addressCity.isNotEmpty) return addressCity;
    final profileCity = PatientProfileMock.profileCity.trim();
    return profileCity.isEmpty ? null : profileCity;
  }

  Future<void> _openFilters() async {
    final allCities = _doctorsStore.searchableDoctors
        .map((d) => d.city)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final specOptions = specialtyCategories.entries.map((e) {
      return (label: e.key, categoryKey: e.key);
    }).toList();

    final langOptions = _doctorsStore.searchableDoctors
        .expand((d) => d.languages)
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final result = await SearchFiltersSheet.show(
      context,
      specialityCategory: _specialityCategory,
      locationFilter: _locationFilter,
      availableToday: _availableToday,
      minRating: _minRating,
      language: _language,
      specialityOptions: specOptions,
      locationOptions: allCities,
      languageOptions: langOptions,
    );

    if (result != null) {
      setState(() {
        _specialityCategory = result.specialityCategory;
        _locationFilter = result.locationFilter;
        _availableToday = result.availableToday;
        _minRating = result.minRating;
        _language = result.language;
      });
    }
  }

  List<DoctorListing> get _filtered {
    final q = _searchController.text.trim();
    var list = _doctorsStore.searchableDoctors.where((d) {
      if (q.isNotEmpty && !DoctorSearchMatcher.matches(d, q)) return false;
      if (!_matchesSpecialityFilter(d.specialization)) return false;
      if (!_matchesLocationFilter(d)) return false;
      if (_availableToday && d.availability != DoctorAvailability.today)
        return false;
      if (_minRating != null && d.rating < _minRating!) return false;
      if (_language != null &&
          !d.languages
              .any((l) => l.toLowerCase() == _language!.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      return switch (_sort) {
        SearchSort.relevance => q.isEmpty
            ? a.distanceKm.compareTo(b.distanceKm)
            : DoctorSearchMatcher.relevanceScore(b, q)
                .compareTo(DoctorSearchMatcher.relevanceScore(a, q)),
        SearchSort.rating => b.rating.compareTo(a.rating),
        SearchSort.experience => b.experienceYears.compareTo(a.experienceYears),
        SearchSort.distance => a.distanceKm.compareTo(b.distanceKm),
      };
    });
    return list;
  }

  void _onSearchChanged(String value) {
    setState(() {});
  }

  void _onSearchSubmitted(String value) {
    setState(() {});
    _focusNode.unfocus();
  }

  void _onSpecialtySuggestionSelected(SpecialtySearchSuggestion suggestion) {
    setState(() {
      _searchController.text = suggestion.label;
      _specialityCategory = suggestion.categoryKey;
    });
    _focusNode.unfocus();
  }

  bool _matchesSpecialityFilter(String doctorSpec) {
    if (_specialityCategory == null) return true;
    final specs = specialtyCategories[_specialityCategory!];
    if (specs == null) return true;
    for (final spec in specs) {
      if (_doctorMatchesSpec(doctorSpec, spec)) return true;
    }
    return false;
  }

  bool _doctorMatchesSpec(String doctorSpec, String filterSpec) {
    final backend = SpecialityMapper.toBackendSpeciality(filterSpec);
    return doctorSpec == backend ||
        doctorSpec == filterSpec ||
        SpecialityMapper.toBackendSpeciality(doctorSpec) == backend;
  }

  bool _matchesLocationFilter(DoctorListing doctor) {
    final filter = _locationFilter?.trim();
    if (filter == null || filter.isEmpty) return true;
    return doctorMatchesCity(doctor, filter);
  }

  Widget _buildSearchSection() {
    if (widget.nearYouMode) return const SizedBox.shrink();

    final isWide = !ResponsiveLayout.isCompact(context);
    final hPad = isWide ? 24.0 : 16.0;

    final hasActiveFilters =
        (_locationFilter != null && _locationFilter!.isNotEmpty) ||
            _specialityCategory != null ||
            _availableToday ||
            _minRating != null ||
            _language != null;

    final searchBar = PatientDoctorSearchBar(
      controller: _searchController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      hintText: HomeSearchBar.placeholder(compact: !isWide),
      onChanged: _onSearchChanged,
      onSubmitted: _onSearchSubmitted,
      trailing: Container(
        margin: const EdgeInsets.only(left: 8),
        child: Material(
          color: hasActiveFilters
              ? AppColors.patientTeal
              : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _openFilters,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: isWide ? 54 : 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasActiveFilters
                      ? AppColors.patientTeal
                      : AppColors.borderOf(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: hasActiveFilters
                        ? Colors.white
                        : AppColors.textPrimaryOf(context),
                  ),
                  if (isWide) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Filter',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: hasActiveFilters
                            ? Colors.white
                            : AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(hPad, isWide ? 18 : 14, hPad, isWide ? 14 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchBar,
            if (hasActiveFilters) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_locationFilter != null && _locationFilter!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.location_on_rounded,
                              size: 14, color: AppColors.patientTeal),
                          label: Text(_locationFilter!),
                          selected: true,
                          selectedColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          onDeleted: () =>
                              setState(() => _locationFilter = null),
                          deleteIconColor: AppColors.patientTeal,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.patientTeal,
                          ),
                        ),
                      ),
                    if (_specialityCategory != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.medical_services_outlined,
                              size: 14, color: AppColors.patientTeal),
                          label: Text(_specialityCategory!),
                          selected: true,
                          selectedColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          onDeleted: () =>
                              setState(() => _specialityCategory = null),
                          deleteIconColor: AppColors.patientTeal,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.patientTeal,
                          ),
                        ),
                      ),
                    if (_availableToday)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: const Text('Available Today'),
                          selected: true,
                          selectedColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          onDeleted: () =>
                              setState(() => _availableToday = false),
                          deleteIconColor: AppColors.patientTeal,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.patientTeal,
                          ),
                        ),
                      ),
                    if (_minRating != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFF59E0B)),
                          label:
                              Text('${_minRating!.toStringAsFixed(1)}+ Stars'),
                          selected: true,
                          selectedColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          onDeleted: () => setState(() => _minRating = null),
                          deleteIconColor: AppColors.patientTeal,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.patientTeal,
                          ),
                        ),
                      ),
                    if (_language != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.language_rounded,
                              size: 14, color: AppColors.patientTeal),
                          label: Text(_language!),
                          selected: true,
                          selectedColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          onDeleted: () => setState(() => _language = null),
                          deleteIconColor: AppColors.patientTeal,
                          labelStyle: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            fontWeight: FontWeight.w600,
                            color: AppColors.patientTeal,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_showSpecialtySuggestions) ...[
              const SizedBox(height: 8),
              SearchSpecialtySuggestionsPanel(
                suggestions: _specialtySuggestions,
                title: 'Speciality recommendations',
                onSelected: _onSpecialtySuggestionSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedResults(
      LabCatalog catalog, List<DoctorListing> doctors) {
    final tests = _filteredLabTests(catalog);
    final packages = _filteredLabPackages(catalog);
    final labs = _filteredPartnerLabs(catalog);

    if (tests.isEmpty && packages.isEmpty && labs.isEmpty && doctors.isEmpty) {
      return const _NoResultsState();
    }

    final rows = <Widget>[];

    void addSection({
      required String title,
      required Color accent,
      required List<Widget> items,
    }) {
      if (items.isEmpty) return;
      rows.add(LabSearchSectionHeader(
          title: title, count: items.length, accentColor: accent));
      rows.addAll(items);
    }

    addSection(
      title: 'Lab tests',
      accent: AppColors.labPurple,
      items: [
        for (var i = 0; i < tests.length; i++)
          LabSearchResultTile(
            title: tests[i].name,
            subtitle: [
              if (tests[i].fastingRequired) 'Fasting',
              '${tests[i].reportHours}h report',
              tests[i].sampleType.name,
            ].join(' · '),
            kind: LabSearchResultKind.test,
            showDivider: i < tests.length - 1,
            onTap: () => _openLabTest(catalog, tests[i]),
          ),
      ],
    );

    addSection(
      title: 'Health packages',
      accent: const Color(0xFF7C3AED),
      items: [
        for (var i = 0; i < packages.length; i++)
          LabSearchResultTile(
            title: packages[i].name,
            subtitle:
                '${packages[i].testCount} tests · ${packages[i].description}',
            kind: LabSearchResultKind.package,
            showDivider: i < packages.length - 1,
            onTap: () => _openLabTest(catalog, _testFromPackage(packages[i])),
          ),
      ],
    );

    addSection(
      title: 'Labs',
      accent: AppColors.patientTeal,
      items: [
        for (var i = 0; i < labs.length; i++)
          LabSearchResultTile(
            title: labs[i].name,
            subtitle: labs[i].area.trim(),
            kind: LabSearchResultKind.lab,
            showDivider: i < labs.length - 1,
            onTap: _openLabHome,
          ),
      ],
    );

    if (doctors.isNotEmpty) {
      if (rows.isNotEmpty) {
        rows.add(Divider(
            height: 1, thickness: 1, color: AppColors.borderOf(context)));
      }
      rows.add(LabSearchSectionHeader(
        title: _doctorsSectionTitle,
        count: doctors.length,
        accentColor: AppColors.patientTeal,
      ));
      for (var i = 0; i < doctors.length; i++) {
        final d = doctors[i];
        rows.add(
          DoctorListingCard(
            doctor: d,
            flat: true,
            showDivider: i < doctors.length - 1,
            onBook: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BookingFlowScreen(doctorId: d.id)),
              );
            },
            onViewProfile: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PatientDoctorProfileScreen(doctorId: d.id)),
              );
            },
          ),
        );
      }
    }

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: ListView(
        padding: EdgeInsets.zero,
        children: rows,
      ),
    );
  }

  Future<void> _addDoctorToMyList(
      BuildContext context, DoctorListing doctor) async {
    await PatientFavoritesStore.instance.addDoctor(doctor.id);
  }

  Widget _buildCitywideList(List<DoctorListing> doctors) {
    final city = _locationFilter?.trim() ?? '';
    if (doctors.isEmpty) {
      return _CitywideEmptyState(city: city);
    }

    return ListenableBuilder(
      listenable: PatientFavoritesStore.instance,
      builder: (context, _) {
        final favorites = PatientFavoritesStore.instance;

        return ColoredBox(
          color: AppColors.surfaceOf(context),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: doctors.length,
            itemBuilder: (context, index) {
              final d = doctors[index];
              final added = favorites.isDoctorVisible(d.id);

              return DoctorListingCard(
                doctor: d,
                flat: true,
                showDivider: index < doctors.length - 1,
                isInMyDoctors: added,
                onAddToMyDoctors: added
                    ? null
                    : () => unawaited(_addDoctorToMyList(context, d)),
                onBook: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BookingFlowScreen(doctorId: d.id)),
                  );
                },
                onViewProfile: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            PatientDoctorProfileScreen(doctorId: d.id)),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  static const _defaultAmbulances = [
    RegisteredAmbulance(
      id: 'amb_default_1',
      serviceName: 'Lifeline Critical Care Ambulance',
      driverName: 'Ramesh Sharma',
      phone: '+91 98765 43210',
      vehicleNumber: 'DL 01 AB 1234',
      city: 'New Delhi',
      ambulanceType: AmbulanceType.als,
      available: true,
      totalRating: 4.8,
      ratingCount: 24,
      ratePerKm: 25,
      hasOxygen: true,
      hasVentilator: true,
      is24x7: true,
    ),
    RegisteredAmbulance(
      id: 'amb_default_2',
      serviceName: 'City Express Emergency Service',
      driverName: 'Suresh Kumar',
      phone: '+91 98123 45678',
      vehicleNumber: 'DL 04 CD 5678',
      city: 'New Delhi',
      ambulanceType: AmbulanceType.bls,
      available: true,
      totalRating: 4.6,
      ratingCount: 18,
      ratePerKm: 18,
      hasOxygen: true,
      is24x7: true,
    ),
    RegisteredAmbulance(
      id: 'amb_default_3',
      serviceName: 'Apex Cardiac & ICU Ambulance',
      driverName: 'Vikram Singh',
      phone: '+91 99887 76655',
      vehicleNumber: 'HR 26 EF 9012',
      city: 'Gurugram',
      ambulanceType: AmbulanceType.icu,
      available: true,
      totalRating: 4.9,
      ratingCount: 31,
      ratePerKm: 35,
      hasOxygen: true,
      hasVentilator: true,
      hasStretcher: true,
      is24x7: true,
    ),
    RegisteredAmbulance(
      id: 'amb_default_4',
      serviceName: 'Red Cross Patient Transport',
      driverName: 'Mohit Verma',
      phone: '+91 97654 32109',
      vehicleNumber: 'UP 16 GH 3456',
      city: 'Noida',
      ambulanceType: AmbulanceType.patientTransport,
      available: true,
      totalRating: 4.5,
      ratingCount: 12,
      ratePerKm: 15,
      hasStretcher: true,
    ),
    RegisteredAmbulance(
      id: 'amb_default_5',
      serviceName: 'Metro 24x7 Rapid Response',
      driverName: 'Amit Patel',
      phone: '+91 96543 21098',
      vehicleNumber: 'MH 02 IJ 7890',
      city: 'Mumbai',
      ambulanceType: AmbulanceType.als,
      available: true,
      totalRating: 4.7,
      ratingCount: 20,
      ratePerKm: 22,
      hasOxygen: true,
      is24x7: true,
    ),
  ];

  Widget _buildNearbyFeed(LabCatalog? catalog, List<DoctorListing> allDoctors) {
    final userCity = _resolvedCity.trim().isNotEmpty
        ? _resolvedCity.trim()
        : _resolvedPincode.trim();
    final allDocs = _doctorsStore.searchableDoctors.isNotEmpty
        ? _doctorsStore.searchableDoctors
        : allDoctors;

    // 1. Doctors near you: top 5-10
    final nearbyDoctors = <DoctorListing>[];
    if (userCity.isNotEmpty) {
      final cityMatches =
          allDocs.where((d) => doctorMatchesCity(d, userCity)).toList();
      cityMatches.sort((a, b) {
        final dist = a.distanceKm.compareTo(b.distanceKm);
        if (dist != 0) return dist;
        return b.rating.compareTo(a.rating);
      });
      nearbyDoctors.addAll(cityMatches);
    }
    if (nearbyDoctors.length < 5) {
      final remaining =
          allDocs.where((d) => !nearbyDoctors.contains(d)).toList();
      remaining.sort((a, b) {
        final dist = a.distanceKm.compareTo(b.distanceKm);
        if (dist != 0) return dist;
        return b.rating.compareTo(a.rating);
      });
      for (final d in remaining) {
        if (nearbyDoctors.length >= 10) break;
        nearbyDoctors.add(d);
      }
    }
    if (nearbyDoctors.length > 10) {
      nearbyDoctors.removeRange(10, nearbyDoctors.length);
    }

    // 2. Labs near you: top 5-10
    final nearbyPartnerLabs = <PartnerLab>[];
    if (catalog != null) {
      if (userCity.isNotEmpty) {
        final cityMatches = catalog.partnerLabs
            .where((l) => locationsMatch(l.area, userCity))
            .toList();
        cityMatches.sort((a, b) => b.rating.compareTo(a.rating));
        nearbyPartnerLabs.addAll(cityMatches);
      }
      if (nearbyPartnerLabs.length < 5) {
        final remaining = catalog.partnerLabs
            .where((l) => !nearbyPartnerLabs.contains(l))
            .toList();
        remaining.sort((a, b) => b.rating.compareTo(a.rating));
        for (final l in remaining) {
          if (nearbyPartnerLabs.length >= 10) break;
          nearbyPartnerLabs.add(l);
        }
      }
      if (nearbyPartnerLabs.length > 10) {
        nearbyPartnerLabs.removeRange(10, nearbyPartnerLabs.length);
      }
    }

    // 3. Ambulances near you: top 5-10
    final sourceAmbulances =
        AmbulanceStore.instance.registeredAmbulances.isNotEmpty
            ? AmbulanceStore.instance.registeredAmbulances
            : _defaultAmbulances;
    final nearbyAmbulances = <RegisteredAmbulance>[];
    if (userCity.isNotEmpty) {
      final cityMatches = sourceAmbulances
          .where((a) => ambulanceMatchesRequestCity(
                requestCity: userCity,
                ambulanceCity: a.city,
                serviceAreas: a.serviceAreas,
                baseAddress: a.baseAddress,
              ))
          .toList();
      cityMatches.sort((a, b) {
        if (a.available != b.available) return a.available ? -1 : 1;
        return b.averageRating.compareTo(a.averageRating);
      });
      nearbyAmbulances.addAll(cityMatches);
    }
    if (nearbyAmbulances.length < 5) {
      final remaining =
          sourceAmbulances.where((a) => !nearbyAmbulances.contains(a)).toList();
      remaining.sort((a, b) {
        if (a.available != b.available) return a.available ? -1 : 1;
        return b.averageRating.compareTo(a.averageRating);
      });
      for (final a in remaining) {
        if (nearbyAmbulances.length >= 10) break;
        nearbyAmbulances.add(a);
      }
    }
    if (nearbyAmbulances.length > 10) {
      nearbyAmbulances.removeRange(10, nearbyAmbulances.length);
    }

    final rows = <Widget>[];

    if (userCity.isNotEmpty) {
      final locationLabel = _resolvedCity.trim().isNotEmpty &&
              _resolvedPincode.trim().isNotEmpty
          ? '${_resolvedCity.trim()} (${_resolvedPincode.trim()})'
          : userCity;
      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.patientTeal.withValues(alpha: 0.06),
          child: Row(
            children: [
              const Icon(Icons.near_me_rounded,
                  size: 15, color: AppColors.patientTeal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Showing nearby services in $locationLabel',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.patientTeal,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      rows.add(Divider(
          height: 1, thickness: 1, color: AppColors.borderOf(context)));
    }

    void addSection({
      required String title,
      required Color accent,
      required VoidCallback onViewAll,
      required int count,
      required List<Widget> items,
    }) {
      rows.add(
        LabSearchSectionHeader(
          title: title,
          count: count > 0 ? count : null,
          accentColor: accent,
          onViewAll: onViewAll,
        ),
      );
      if (items.isEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Nothing nearby yet',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      } else {
        rows.addAll(items);
      }
      rows.add(Divider(
        height: 1,
        thickness: 1,
        color: AppColors.borderOf(context),
      ));
    }

    // Section 1: Doctors near you
    addSection(
      title: 'Doctors near you',
      accent: AppColors.patientTeal,
      count: nearbyDoctors.length,
      onViewAll: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DoctorSearchScreen(
              initialLocationFilter: userCity.isNotEmpty ? userCity : null,
              nearYouMode: userCity.isNotEmpty,
            ),
          ),
        );
      },
      items: [
        for (var i = 0; i < nearbyDoctors.length; i++)
          DoctorListingCard(
            doctor: nearbyDoctors[i],
            flat: true,
            showDivider: i < nearbyDoctors.length - 1,
            onBook: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      BookingFlowScreen(doctorId: nearbyDoctors[i].id),
                ),
              );
            },
            onViewProfile: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientDoctorProfileScreen(
                      doctorId: nearbyDoctors[i].id),
                ),
              );
            },
          ),
      ],
    );

    // Section 2: Labs near you
    addSection(
      title: 'Labs near you',
      accent: AppColors.labPurple,
      count: nearbyPartnerLabs.length,
      onViewAll: _openLabHome,
      items: [
        for (var i = 0; i < nearbyPartnerLabs.length; i++)
          LabSearchResultTile(
            title: nearbyPartnerLabs[i].name,
            subtitle: nearbyPartnerLabs[i].area.trim().isNotEmpty
                ? nearbyPartnerLabs[i].area.trim()
                : 'Diagnostic Lab',
            kind: LabSearchResultKind.lab,
            showDivider: i < nearbyPartnerLabs.length - 1,
            onTap: _openLabHome,
          ),
      ],
    );

    // Section 3: Ambulances near you
    addSection(
      title: 'Ambulances near you',
      accent: const Color(0xFFEF4444),
      count: nearbyAmbulances.length,
      onViewAll: _openAmbulanceBooking,
      items: [
        for (var i = 0; i < nearbyAmbulances.length; i++)
          LabSearchResultTile(
            title: nearbyAmbulances[i].serviceName.isNotEmpty
                ? nearbyAmbulances[i].serviceName
                : 'Ambulance Service',
            subtitle: [
              if (nearbyAmbulances[i].city.isNotEmpty)
                nearbyAmbulances[i].city,
              nearbyAmbulances[i].driverName.isNotEmpty
                  ? nearbyAmbulances[i].driverName
                  : 'Emergency Driver',
              nearbyAmbulances[i].available ? 'Available' : 'On call',
            ].join(' · '),
            kind: LabSearchResultKind.ambulance,
            showDivider: i < nearbyAmbulances.length - 1,
            onTap: _openAmbulanceBooking,
          ),
      ],
    );

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: ListView(
        padding: EdgeInsets.zero,
        children: rows,
      ),
    );
  }

  Widget _buildResultsList(LabCatalog catalog, List<DoctorListing> doctors) {
    return _buildCombinedResults(catalog, doctors);
  }

  Widget _buildContentArea(LabCatalog? catalog, List<DoctorListing> doctors) {
    if (!_showResults) {
      if (catalog == null && _resolvingLocation) {
        return const _NearbyFeedSkeleton();
      }
      return _buildNearbyFeed(catalog, doctors);
    }

    if (catalog == null) {
      if (doctors.isEmpty) {
        return Center(
          child: CircularProgressIndicator(color: AppColors.labPurple),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          Expanded(
            child: ColoredBox(
              color: AppColors.surfaceOf(context),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: doctors.length,
                itemBuilder: (context, index) {
                  final d = doctors[index];
                  return DoctorListingCard(
                    doctor: d,
                    flat: true,
                    showDivider: index < doctors.length - 1,
                    onBook: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => BookingFlowScreen(doctorId: d.id)),
                      );
                    },
                    onViewProfile: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PatientDoctorProfileScreen(doctorId: d.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
        Expanded(child: _buildResultsList(catalog, doctors)),
      ],
    );
  }

  Widget _buildBody(List<DoctorListing> doctors) {
    if (widget.nearYouMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          Expanded(child: _buildCitywideList(doctors)),
        ],
      );
    }

    return FutureBuilder<LabCatalog>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchSection(),
            Expanded(child: _buildContentArea(snapshot.data, doctors)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);
    final isWide = !ResponsiveLayout.isCompact(context);

    return ListenableBuilder(
      listenable: _doctorsStore,
      builder: (context, _) {
        final doctors = _filtered;

        final content = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _buildBody(doctors),
          ),
        );

        if (widget.embeddedInShell) {
          return Scaffold(
            backgroundColor: AppColors.cardBgOf(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PatientScreenTitleBar(
                  title: 'Search',
                  subtitle: 'Find doctors, lab tests, packages & labs',
                ),
                SizedBox(height: isWide ? 8 : 4),
                Expanded(child: content),
              ],
            ),
          );
        }

        final nearYouCity = widget.nearYouMode ? _locationFilter?.trim() : null;
        final appBarTitle = nearYouCity != null && nearYouCity.isNotEmpty
            ? 'Citywide'
            : 'Search';
        final appBarSubtitle = nearYouCity != null && nearYouCity.isNotEmpty
            ? 'Doctors in $nearYouCity'
            : 'Find doctors, lab tests, packages & labs';

        return Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: AppBar(
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appBarTitle,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                Text(
                  appBarSubtitle,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          body: content,
        );
      },
    );
  }
}

class _CitywideEmptyState extends StatelessWidget {
  const _CitywideEmptyState({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);
    final locationLabel = city.isNotEmpty ? city : 'your city';

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isWide ? 88 : 72,
                height: isWide ? 88 : 72,
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_city_outlined,
                  size: isWide ? 40 : 34,
                  color: AppColors.patientTeal.withValues(alpha: 0.7),
                ),
              ),
              SizedBox(height: isWide ? 24 : 20),
              Text(
                'No doctors in $locationLabel yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 20 : 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We could not find any doctors listed in $locationLabel right now. Try again later or update your city in profile.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 15 : 14,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyFeedSkeleton extends StatefulWidget {
  const _NearbyFeedSkeleton();

  @override
  State<_NearbyFeedSkeleton> createState() => _NearbyFeedSkeletonState();
}

class _NearbyFeedSkeletonState extends State<_NearbyFeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);
    final highlightColor =
        isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.12);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final color = Color.lerp(baseColor, highlightColor, _anim.value)!;
        return ColoredBox(
          color: AppColors.surfaceOf(context),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              for (int s = 0; s < 3; s++) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    width: 150,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                for (int i = 0; i < 2; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 180,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (s < 2)
                  Divider(
                    height: 16,
                    thickness: 1,
                    color: AppColors.borderOf(context),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 52,
              color: AppColors.textSecondaryOf(context).withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different keyword for doctors or lab tests.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
