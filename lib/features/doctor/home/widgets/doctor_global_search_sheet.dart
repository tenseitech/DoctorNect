import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/location/location_match.dart';
import '../../../ambulance/ambulance_booking_screen.dart';
import '../../../ambulance/models/ambulance_models.dart';
import '../../../lab/data/lab_connection_store.dart';
import '../../../pharmacy/data/pharmacy_connection_store.dart';
import '../../../pharmacy/models/pharmacy_models.dart';
import '../../models/doctor_models.dart';
import '../../patients/data/doctor_patients_service.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorGlobalSearchScreen extends StatefulWidget {
  const DoctorGlobalSearchScreen({
    super.key,
    required this.onPatientSelected,
  });

  final void Function(Appointment patient) onPatientSelected;

  static Future<void> show(
    BuildContext context, {
    required void Function(Appointment patient) onPatientSelected,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorGlobalSearchScreen(
          onPatientSelected: onPatientSelected,
        ),
      ),
    );
  }

  @override
  State<DoctorGlobalSearchScreen> createState() => _DoctorGlobalSearchScreenState();
}

class _DoctorGlobalSearchScreenState extends State<DoctorGlobalSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Appointment> get _filteredPatients {
    if (_query.trim().isEmpty) return [];
    final q = _query.trim().toLowerCase();
    
    final summaries = DoctorPatientsService.summariesForDoctor(DoctorSession.loggedInDoctorId);
    return summaries
        .where((s) => s.name.toLowerCase().contains(q))
        .map((s) => Appointment(
              id: s.id,
              tokenNumber: 0,
              patientName: s.name,
              age: s.age,
              gender: s.gender,
              appointmentDate: s.lastVisitDate,
              timeSlot: '',
              status: AppointmentStatus.confirmed,
              type: AppointmentType.newVisit,
            ))
        .toList();
  }

  List<MedicalStoreProfile> get _filteredStores {
    if (_query.trim().isEmpty) return [];
    final q = _query.trim().toLowerCase();
    final doctorCity = pharmacyCityFilter(
      city: DoctorProfileStore.instance.profile.city,
      address: DoctorProfileStore.instance.profile.addressLine1,
    );
    
    // If user types 'medical', 'pharmacy' etc, show all stores (filtered by city)
    final isCategorySearch = q == 'medical' || q == 'medical store' || q == 'pharmacy';
    final stores = PharmacyConnectionStore.instance.searchStores(
      isCategorySearch ? '' : q,
      cityFilter: doctorCity,
    );
    
    return stores;
  }

  List<RegisteredLabProfile> get _filteredLabs {
    if (_query.trim().isEmpty) return [];
    final q = _query.trim().toLowerCase();
    final doctorCity = pharmacyCityFilter(
      city: DoctorProfileStore.instance.profile.city,
      address: DoctorProfileStore.instance.profile.addressLine1,
    );
    
    // If user types 'lab', 'labs', 'pathology', show all labs (filtered by city)
    final isCategorySearch = q == 'lab' || q == 'labs' || q == 'pathology';
    final labs = LabConnectionStore.instance.searchLabs(
      isCategorySearch ? '' : q,
      cityFilter: doctorCity,
    );
    
    return labs;
  }

  bool get _showAmbulance {
    if (_query.trim().isEmpty) return false;
    return 'ambulance'.contains(_query.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final patients = _filteredPatients;
    final stores = _filteredStores;
    final labs = _filteredLabs;
    final hasResults = patients.isNotEmpty || stores.isNotEmpty || labs.isNotEmpty || _showAmbulance;

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, color: AppColors.textPrimaryOf(context)),
          decoration: InputDecoration(
            hintText: 'Search for patient, medical, lab...',
            hintStyle: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              color: AppColors.textSecondaryOf(context),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondaryOf(context),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.borderOf(context), height: 1),
        ),
      ),
      body: _query.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 64,
                    color: AppColors.textSecondaryOf(context).withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Type to start searching',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            )
          : !hasResults
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: AppColors.textSecondaryOf(context).withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No results found for "$_query"',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  children: [
                    if (patients.isNotEmpty) ...[
                      _SectionHeader(title: 'Patients', count: patients.length),
                      ...patients.map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PatientRow(
                              appointment: a,
                              onTap: () {
                                Navigator.pop(context);
                                widget.onPatientSelected(a);
                              },
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (stores.isNotEmpty) ...[
                      _SectionHeader(title: 'Medical Stores', count: stores.length, color: AppColors.pharmacyGreen),
                      ...stores.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MedicalStoreRow(store: s),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (labs.isNotEmpty) ...[
                      _SectionHeader(title: 'Labs', count: labs.length, color: Color(0xFF8B5CF6)),
                      ...labs.map((l) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _LabRow(lab: l),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (_showAmbulance) ...[
                      const _SectionHeader(title: 'Services', count: 1, color: Colors.red),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AmbulanceRow(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AmbulanceBookingScreen(
                                  bookedByRole: AmbulanceBookedByRole.doctor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.color = AppColors.doctorBlue});

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: color),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('($count)', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context))),
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.appointment,
    required this.onTap,
  });

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = '${appointment.age} yrs · ${AppConstants.patientGenderLabel(appointment.gender)} · Last visit: ${DateFormat('dd MMM').format(appointment.appointmentDate)}';

    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              PatientAvatar(name: appointment.patientName, gender: appointment.gender),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.patientName,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicalStoreRow extends StatelessWidget {
  const _MedicalStoreRow({required this.store});

  final MedicalStoreProfile store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.pharmacyGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_pharmacy_outlined, color: AppColors.pharmacyGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.storeName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodyMedium)),
                const SizedBox(height: 2),
                Text(
                  store.address,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabRow extends StatelessWidget {
  const _LabRow({required this.lab});

  final RegisteredLabProfile lab;

  static const _labPurple = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _labPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.biotech_outlined, color: _labPurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lab.labName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodyMedium)),
                const SizedBox(height: 2),
                Text(
                  lab.address,
                  style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbulanceRow extends StatelessWidget {
  const _AmbulanceRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emergency_outlined, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ambulance Service', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.bodyMedium)),
                    const SizedBox(height: 2),
                    Text(
                      'Book an emergency ambulance',
                      style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
