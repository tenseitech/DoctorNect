import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/prescription_clinical_assets.dart';
import '../data/community_medicine_repository.dart';
import '../models/clinical_models.dart';
import 'add_community_medicine_dialog.dart';
import 'prescription_rx_shared.dart';
import '../../../../core/theme/app_typography.dart';

/// Card-based Rx layout for mobile (isCompact == true).
class PrescriptionMobileRxSection extends StatefulWidget {
  const PrescriptionMobileRxSection({
    super.key,
    required this.medicines,
    required this.nameControllers,
    required this.onAddAfter,
    required this.onRemove,
    required this.onChanged,
    required this.onMedicineSelected,
  });

  final List<MedicineEntry> medicines;
  final Map<String, TextEditingController> nameControllers;
  final void Function(int index) onAddAfter;
  final void Function(int index) onRemove;
  final VoidCallback onChanged;
  final void Function(MedicineSearchSuggestion item) onMedicineSelected;

  @override
  State<PrescriptionMobileRxSection> createState() => _PrescriptionMobileRxSectionState();
}

class _PrescriptionMobileRxSectionState extends State<PrescriptionMobileRxSection> {
  final _searchController = TextEditingController();
  String? _expandedMedicineId;
  final Set<String> _expandedInstructionIds = {};
  String _searchQuery = '';
  List<MedicineSearchSuggestion> _searchResults = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runSearch(String raw) {
    final q = raw.trim();
    if (q.isNotEmpty) {
      unawaited(PrescriptionClinicalAssets.ensureLoaded());
    }
    setState(() {
      _searchQuery = q;
      _searchResults = q.isEmpty
          ? const []
          : CommunityMedicineRepository.instance.searchMerged(q, limit: 20);
    });
  }

  void _selectSearchResult(MedicineSearchSuggestion item) {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults = const [];
    });
    widget.onMedicineSelected(item);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final named = namedMedicineEntries(widget.medicines);
      if (named.isNotEmpty) {
        setState(() => _expandedMedicineId = named.last.id);
      }
    });
  }

  Future<void> _openAddCommunityDialog(BuildContext context, String initialName) async {
    final medicine = await AddCommunityMedicineDialog.show(context, initialName);
    if (!context.mounted || medicine == null) return;
    await CommunityMedicineRepository.instance.fetchAll();
    if (!context.mounted) return;
    _selectSearchResult(
      MedicineSearchSuggestion(
        name: medicine.name,
        isCommunity: true,
        dosageUnit: medicine.dosageUnit,
        form: medicine.form,
      ),
    );
  }

  void _toggleInstruction(String id) {
    setState(() {
      if (_expandedInstructionIds.contains(id)) {
        _expandedInstructionIds.remove(id);
      } else {
        _expandedInstructionIds.add(id);
      }
    });
  }

  void _toggleExpand(String id) {
    setState(() {
      _expandedMedicineId = _expandedMedicineId == id ? null : id;
    });
  }

  void _confirmMedicine(String id) {
    setState(() {
      _expandedMedicineId = null;
      _expandedInstructionIds.remove(id);
      _searchController.clear();
      _searchQuery = '';
      _searchResults = const [];
    });
    widget.onChanged();
  }

  int get _namedCount => namedMedicineEntries(widget.medicines).length;

  List<Widget> _buildMedicineCards(List<MedicineEntry> named) {
    return named.asMap().entries.map((e) {
      final entry = e.value;
      final listIndex = widget.medicines.indexOf(entry);
      final controller = widget.nameControllers[entry.id];
      if (controller == null) return const SizedBox.shrink();
      return RxMedicineCard(
        key: ValueKey(entry.id),
        index: e.key,
        entry: entry,
        nameController: controller,
        isExpanded: _expandedMedicineId == entry.id,
        showInstruction: _expandedInstructionIds.contains(entry.id),
        canDelete: true,
        onExpandToggle: () => _toggleExpand(entry.id),
        onToggleInstruction: () => _toggleInstruction(entry.id),
        onDelete: () => widget.onRemove(listIndex),
        onChanged: widget.onChanged,
        onConfirm: () => _confirmMedicine(entry.id),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final named = namedMedicineEntries(widget.medicines);
    final listHeight = rxWorkspaceHeight(context).clamp(220.0, 380.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RxMedicineSearchBar(
          controller: _searchController,
          searchQuery: _searchQuery,
          results: _searchResults,
          showResults: _searchQuery.isNotEmpty,
          maxWidth: 360,
          onChanged: _runSearch,
          onSelect: _selectSearchResult,
          trailing: IconButton.filledTonal(
            onPressed: () => _openAddCommunityDialog(
              context,
              _searchController.text.trim(),
            ),
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Add custom medicine',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.12),
              foregroundColor: AppColors.doctorBlue,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _namedCount > 0
                ? AppColors.doctorBlue.withValues(alpha: 0.1)
                : AppColors.borderOf(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _namedCount == 0 ? '0 medicines' : '$_namedCount in Rx',
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w700,
              color: _namedCount > 0 ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (named.isEmpty)
          const RxEmptyState()
        else
          RxMedicineList(
            maxHeight: listHeight,
            children: _buildMedicineCards(named),
          ),
      ],
    );
  }
}
