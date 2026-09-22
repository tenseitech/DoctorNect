import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/notifications/app_notification.dart';
import '../../../core/notifications/widgets/notification_bell_button.dart';
import '../../../core/session/patient_session.dart';
import '../../../features/ambulance/ambulance_booking_screen.dart';
import '../../../features/ambulance/models/ambulance_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/enums/user_type.dart';
import '../../../widgets/digital_health_card_sheet.dart';
import '../../../widgets/emergency_sos_sheet.dart';
import '../../../widgets/theme_toggle_button.dart';
import '../data/patient_mock_data.dart';
import '../data/registered_doctors_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../profile/data/patient_profile_mock.dart';
import '../profile/models/patient_profile_models.dart';
import '../booking/booking_flow_screen.dart';
import '../doctor_profile/patient_doctor_profile_screen.dart';
import '../lab/my_labs_screen.dart';
import '../lab/lab_home_screen.dart';
import '../records/patient_records_screen.dart';
import '../search/doctor_search_screen.dart';
import '../../../widgets/home_banner_carousel.dart';
import '../widgets/patient_favorites_sheets.dart';
import '../../../core/models/promoted_ad_model.dart';
import '../../../core/services/promoted_ads_service.dart';
import 'widgets/my_doctor_section.dart';
import 'widgets/appointments_section.dart';
import 'widgets/explore_section.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/services_section.dart';
import 'widgets/patient_address_sheet.dart';
import '../../../core/theme/app_typography.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({
    super.key,
    this.onSelectTab,
    this.onOpenAppointments,
  });

  /// Switches the patient shell tab (0=Home, 1=Visits, 2=Labs, 3=Ambulance, 4=Profile).
  final ValueChanged<int>? onSelectTab;

  @Deprecated('Use onSelectTab')
  final VoidCallback? onOpenAppointments;

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final _doctorsStore = RegisteredDoctorsStore.instance;

  @override
  void initState() {
    super.initState();
    PatientProfileMock.listenable.addListener(_onProfileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doctorsStore.startListening();
    });
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openAddressForm() async {
    await PatientAddressSheet.show(context);
  }

  void _openSearch({
    String query = '',
    String? category,
    String? locationFilter,
    bool nearYouMode = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorSearchScreen(
          initialQuery: query,
          initialCategory: category,
          initialLocationFilter: locationFilter,
          nearYouMode: nearYouMode,
          autofocus:
              query.isEmpty && category == null && locationFilter == null,
          onSelectPatientTab: widget.onSelectTab,
        ),
      ),
    );
  }

  String _patientCity() {
    final address = PatientProfileMock.profileAddress;
    if (address.city.trim().isNotEmpty) return address.city.trim();
    return PatientProfileMock.profileCity.trim();
  }

  Future<void> _openNearYou() async {
    var city = _patientCity();
    if (city.isEmpty) {
      final saved = await PatientAddressSheet.show(context);
      if (!mounted || saved != true) return;
      city = _patientCity();
      if (city.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add your city to see citywide doctors'),
          ),
        );
        return;
      }
    }
    _openSearch(locationFilter: city, nearYouMode: true);
  }

  @override
  void dispose() {
    PatientProfileMock.listenable.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _openLab() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LabHomeScreen()));
  }

  void _openMyLabs() {
    if (widget.onSelectTab != null) {
      widget.onSelectTab!(2);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyLabsScreen()),
    );
  }

  void _handleServiceTap(ServiceItem service) {
    final route = service.route;
    if (route == 'records') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PatientRecordsScreen()),
      );
      return;
    }
    if (route == 'sos') {
      EmergencySosSheet.show(context);
      return;
    }
    if (route == 'digital-pass' || route == 'pass') {
      DigitalHealthCardSheet.show(context, userType: UserType.patient);
      return;
    }
    if (route == 'near-you') {
      unawaited(_openNearYou());
      return;
    }
    if (route == 'my-lab') {
      _openMyLabs();
      return;
    }
    if (route == 'search') {
      _openSearch();
      return;
    }
    if (route == 'appointments') {
      if (widget.onSelectTab != null) {
        widget.onSelectTab!(1);
      } else {
        widget.onOpenAppointments?.call();
      }
      return;
    }
    if (route == 'lab') {
      _openLab();
      return;
    }
    if (route == 'ambulance') {
      if (widget.onSelectTab != null) {
        widget.onSelectTab!(3);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AmbulanceBookingScreen(
              bookedByRole: AmbulanceBookedByRole.patient,
            ),
          ),
        );
      }
      return;
    }
    AppToast.info(context, '${service.label} — coming soon');
  }

  @override
  Widget build(BuildContext context) {
    final name = PatientProfileMock.profile.name.isNotEmpty
        ? PatientProfileMock.profile.name
        : PatientSession.loggedInPatientName;
    final address = PatientProfileMock.profileAddress;
    final p = PatientContext(
      name: name,
      city: address.shortLabel.isNotEmpty
          ? address.shortLabel
          : PatientProfileMock.profileCity,
    );
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, compact ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Hi, ${p.name.trim().isEmpty ? "Patient" : p.name.trim()}',
                                maxLines: compact ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: compact ? 18 : 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: compact ? 2 : 4),
                              _PatientLocationRow(
                                address: address,
                                onTap: () => unawaited(_openAddressForm()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const ThemeToggleButton(),
                        const SizedBox(width: 4),
                        const NotificationBellButton(
                            audience: NotificationAudience.patient),
                      ],
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    HomeSearchBar(
                      onTap: () => _openSearch(),
                      onSubmitted: (query) => _openSearch(query: query),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, _) {
                  return StreamBuilder<List<PromotedAdModel>>(
                    stream: PromotedAdsService.streamActiveAds(),
                    builder: (context, snapshot) {
                      final activeAds = snapshot.data ?? [];
                      final carouselItems = _buildCarouselItems(activeAds,
                          patientCity: _patientCity());
                      if (carouselItems.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return HomeBannerCarousel(
                        items: carouselItems,
                        dotActiveColor: AppColors.patientTeal,
                        interactive: false,
                        cardHorizontalInsetFraction: 0.09,
                      );
                    },
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExploreSection(),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25)),
                  ServicesSection(onServiceTap: _handleServiceTap),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25)),
                  MyDoctorSection(
                    onAdd: () =>
                        PatientFavoritesSheets.showAddDoctorSheet(context),
                    onDoctorTap: (d) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PatientDoctorProfileScreen(doctorId: d.id),
                        ),
                      );
                    },
                    onBook: (d) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingFlowScreen(doctorId: d.id),
                        ),
                      );
                    },
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color:
                          AppColors.borderOf(context).withValues(alpha: 0.25)),
                  AppointmentsSection(
                    onViewAll: () {
                      if (widget.onSelectTab != null) {
                        widget.onSelectTab!(1);
                      } else {
                        widget.onOpenAppointments?.call();
                      }
                    },
                    onFindDoctor: _openSearch,
                  ),
                  SizedBox(height: compact ? 88 : 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientLocationRow extends StatelessWidget {
  const _PatientLocationRow({
    required this.address,
    required this.onTap,
  });

  final PatientAddress address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAddress = address.hasContent;
    final label = hasAddress ? address.shortLabel : 'Change location';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 15, color: AppColors.patientTeal),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: hasAddress ? FontWeight.w500 : FontWeight.w600,
                    height: 1.2,
                    color: hasAddress
                        ? AppColors.textSecondaryOf(context)
                        : AppColors.patientTeal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<HomeCarouselItem> _buildCarouselItems(List<PromotedAdModel> activeAds,
    {String? patientCity}) {
  final baseItems = PatientMockData.carouselItems
      .where((item) => item.banner.kind != HomeCarouselKind.healthTip)
      .toList();
  if (activeAds.isEmpty) return baseItems;

  final filteredAds = activeAds.where((ad) {
    final city = ad.targetCity?.trim().toLowerCase();
    if (city == null || city.isEmpty || city == 'all') return true;
    if (patientCity == null || patientCity.trim().isEmpty) return true;
    return city == patientCity.trim().toLowerCase();
  }).toList();

  if (filteredAds.isEmpty) return baseItems;

  final promotedItems = filteredAds.map((ad) {
    final providerLabel = switch (ad.providerType.toLowerCase()) {
      'lab' => 'Lab',
      'pharmacy' => 'Pharmacy',
      'ambulance' => 'Ambulance',
      _ => 'Doctor',
    };
    final icon = switch (ad.providerType.toLowerCase()) {
      'lab' => Icons.science_outlined,
      'pharmacy' => Icons.local_pharmacy_outlined,
      'ambulance' => Icons.emergency_outlined,
      _ => Icons.medical_services_outlined,
    };
    return HomeCarouselItem(
      banner: PromoBanner(
        title: ad.title,
        subtitle: ad.description,
        kind: HomeCarouselKind.productAd,
        gradientColors: const [Color(0xFF0F766E), Color(0xFF0D9488)],
        badgeLabelOverride: 'Sponsored • $providerLabel',
        icon: icon,
        imageUrl: ad.imageUrl,
      ),
      ctaLabel: ad.ctaLabel.isNotEmpty ? ad.ctaLabel : 'View Details',
      ctaRoute: 'promotedAd:${ad.adId}:${ad.providerType}:${ad.providerId}',
    );
  }).toList();

  final combined = <HomeCarouselItem>[];
  int promotedIdx = 0;
  for (var i = 0; i < baseItems.length; i++) {
    combined.add(baseItems[i]);
    if (promotedIdx < promotedItems.length && (i % 2 == 0)) {
      combined.add(promotedItems[promotedIdx]);
      promotedIdx++;
    }
  }
  while (promotedIdx < promotedItems.length) {
    combined.add(promotedItems[promotedIdx]);
    promotedIdx++;
  }

  return combined;
}
