import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/firebase/models/doctor_referral.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../appointments/widgets/referred_patient_card.dart';
import '../../clinical/referral_consult_service.dart';
import '../../widgets/doctor_screen_title_bar.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorReferredPatientsScreen extends StatefulWidget {
  const DoctorReferredPatientsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DoctorReferredPatientsScreen()),
    );
  }

  @override
  State<DoctorReferredPatientsScreen> createState() =>
      _DoctorReferredPatientsScreenState();
}

class _DoctorReferredPatientsScreenState extends State<DoctorReferredPatientsScreen> {
  List<DoctorReferral> _sent = [];
  List<DoctorReferral> _received = [];
  bool _loading = true;
  final _searchController = TextEditingController();

  static const _tabLabels = ['Referred by me', 'Referred to me'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final doctorId = DoctorSession.loggedInDoctorId;
      final results = await Future.wait([
        FirestoreService.instance.referral.fetchSentByDoctor(doctorId, preferCache: false),
        FirestoreService.instance.referral.fetchReceivedByDoctor(doctorId, preferCache: false),
      ]);
      if (!mounted) return;
      setState(() {
        _sent = results[0];
        _received = results[1];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DoctorReferral> _filter(List<DoctorReferral> source) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where(
          (r) =>
              r.patientName.toLowerCase().contains(q) ||
              r.toDoctorName.toLowerCase().contains(q) ||
              r.fromDoctorName.toLowerCase().contains(q),
        )
        .toList();
  }

  Widget _buildTabList({
    required List<DoctorReferral> items,
    required bool incoming,
    required String emptyMessage,
    required double padding,
    required double maxWidth,
  }) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final referral = items[index];
            return ReferredPatientCard(
              referral: referral,
              incoming: incoming,
              onOpenConsult: incoming
                  ? () => ReferralConsultService.openIncomingConsult(context, referral)
                  : null,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sent = _filter(_sent);
    final received = _filter(_received);
    final wide = !ResponsiveLayout.isCompact(context);
    final padding = wide ? 24.0 : 16.0;
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: wide ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SafeArea(
              bottom: false,
              child: DoctorScreenTitleBar(
                title: 'Referred Patients',
                showBackButton: true,
              ),
            ),
            Material(
              color: AppColors.surfaceOf(context),
              child: TabBar(
                labelColor: AppColors.doctorBlue,
                unselectedLabelColor: AppColors.textSecondaryOf(context),
                indicatorColor: AppColors.doctorBlue,
                labelStyle: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
                tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
              child: Material(
                color: AppColors.surfaceOf(context),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search patient or doctor',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTabList(
                    items: sent,
                    incoming: false,
                    emptyMessage: 'No patients referred by you yet.',
                    padding: padding,
                    maxWidth: maxWidth,
                  ),
                  _buildTabList(
                    items: received,
                    incoming: true,
                    emptyMessage: 'No patients referred to you by other doctors yet.',
                    padding: padding,
                    maxWidth: maxWidth,
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
