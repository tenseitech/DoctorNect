import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../data/patient_favorites_store.dart';
import '../data/registered_doctors_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';

abstract final class PatientFavoritesSheets {
  static Future<void> showAddDoctorSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _AddDoctorSheet(),
    );
  }

  static Future<void> showAddLabSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const _AddLabSheet(),
    );
  }

  static Future<bool> confirmRemoveDoctor(BuildContext context, MyDoc doctor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove doctor?'),
        content: Text('Remove Dr. ${doctor.name} from your list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}

class _AddDoctorSheet extends StatefulWidget {
  const _AddDoctorSheet();

  @override
  State<_AddDoctorSheet> createState() => _AddDoctorSheetState();
}

class _AddDoctorSheetState extends State<_AddDoctorSheet> {
  final _searchController = TextEditingController();
  final _favorites = PatientFavoritesStore.instance;
  final _doctorsStore = RegisteredDoctorsStore.instance;

  @override
  void initState() {
    super.initState();
    _favorites.addListener(_onChanged);
    _doctorsStore.addListener(_onChanged);
  }

  @override
  void dispose() {
    _favorites.removeListener(_onChanged);
    _doctorsStore.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<DoctorListing> _filteredDoctors() {
    final query = _searchController.text.trim().toLowerCase();
    final doctors = _doctorsStore.searchableDoctors;
    if (query.isEmpty) return doctors;
    return doctors.where((doctor) {
      return doctor.name.toLowerCase().contains(query) ||
          doctor.specialization.toLowerCase().contains(query) ||
          doctor.area.toLowerCase().contains(query) ||
          doctor.qualification.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final doctors = _filteredDoctors();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add to My Doctor',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Search registered doctors to add to your list.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search doctors by name, speciality, city...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.cardBgOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
            child: doctors.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No registered doctors found.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: doctors.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.borderOf(context)),
                    itemBuilder: (context, index) {
                      final doctor = doctors[index];
                      final added = _favorites.isDoctorVisible(doctor.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Dr. ${doctor.name}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${doctor.specialization}${doctor.area.trim().isNotEmpty ? ' · ${doctor.area}' : ''}',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                        ),
                        trailing: FilledButton(
                          onPressed: added ? null : () => _favorites.addDoctor(doctor.id),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.patientTeal,
                            disabledBackgroundColor: AppColors.borderOf(context),
                            minimumSize: const Size(64, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: Text(added ? 'Added' : 'Add'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddLabSheet extends StatefulWidget {
  const _AddLabSheet();

  @override
  State<_AddLabSheet> createState() => _AddLabSheetState();
}

class _AddLabSheetState extends State<_AddLabSheet> {
  final _searchController = TextEditingController();
  final _favorites = PatientFavoritesStore.instance;
  late Future<List<SavedLabEntry>> _labsFuture;

  @override
  void initState() {
    super.initState();
    _labsFuture = _favorites.registeredLabsForSearch();
    _favorites.addListener(_onChanged);
  }

  @override
  void dispose() {
    _favorites.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<SavedLabEntry> _filteredLabs(List<SavedLabEntry> labs) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return labs;
    return labs.where((lab) {
      return lab.name.toLowerCase().contains(query) ||
          lab.area.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add to My Lab',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Search registered labs to add to your list.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search labs by name or area...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.cardBgOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
            child: FutureBuilder<List<SavedLabEntry>>(
              future: _labsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: AppColors.labPurple),
                    ),
                  );
                }

                final labs = _filteredLabs(snapshot.data ?? const []);
                if (labs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No registered labs found.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: labs.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.borderOf(context)),
                  itemBuilder: (context, index) {
                    final lab = labs[index];
                    final added = _favorites.isLabVisible(lab);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        lab.name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        lab.area.trim().isNotEmpty ? lab.area : 'Registered lab',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      ),
                      trailing: FilledButton(
                        onPressed: added ? null : () => _favorites.addLab(lab),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.labPurple,
                          disabledBackgroundColor: AppColors.borderOf(context),
                          minimumSize: const Size(64, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        child: Text(added ? 'Added' : 'Add'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
