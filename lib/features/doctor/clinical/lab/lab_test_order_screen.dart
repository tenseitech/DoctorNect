import '../../../../core/firebase/firestore_service.dart';
import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/enums/user_type.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../lab/data/lab_connection_store.dart';
import '../../../patient/lab/models/lab_models.dart' as patient_lab;
import '../../lab/doctor_connected_labs_screen.dart';
import '../models/clinical_models.dart';
import '../widgets/clinical_widgets.dart';
import 'lab_order_service.dart';

class LabTestOrderScreen extends StatefulWidget {
  const LabTestOrderScreen({
    super.key,
    required this.patient,
    this.source = 'investigations',
  });

  final PatientClinicalContext patient;
  final String source;

  @override
  State<LabTestOrderScreen> createState() => _LabTestOrderScreenState();
}

class _LabTestOrderScreenState extends State<LabTestOrderScreen> {
  final _searchController = TextEditingController();
  final _indicationController = TextEditingController();
  final _labController = TextEditingController();

  final Set<String> _selectedTestIds = {};
  String _categoryFilter = 'All';
  String _urgency = 'Routine';
  bool _fastingRequired = false;
  bool _homeCollection = false;
  bool _loadingCatalog = true;
  bool _sending = false;

  LabCatalog? _catalog;
  String? _selectedLabId; // FIXED: registered lab id when available
  final List<_LabPickerOption> _labOptions = [];

  List<patient_lab.LabTestItem> get _allTests => _catalog?.tests ?? const [];

  List<String> get _categories {
    final cats = _allTests.map(_categoryFor).toSet().toList()..sort();
    return cats;
  }

  List<patient_lab.LabTestItem> get _filteredTests {
    final q = _searchController.text.toLowerCase();
    return _allTests.where((t) {
      final category = _categoryFor(t);
      final matchCategory = _categoryFilter == 'All' || category == _categoryFilter;
      final matchSearch = q.isEmpty || t.name.toLowerCase().contains(q);
      return matchCategory && matchSearch;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await FirestoreService.instance.labCatalog.fetchCatalog();
    final doctorId = DoctorSession.loggedInDoctorId;
    await LabConnectionStore.instance.refreshActiveConnections(
      role: UserType.doctor,
      profileId: doctorId,
      preferCache: true,
    );
    if (!mounted) return;

    final connections = LabConnectionStore.instance.activeForDoctor(doctorId);
    final options = connections
        .map((c) => _LabPickerOption(id: c.labId, name: c.labName))
        .toList();

    setState(() {
      _catalog = catalog;
      _labOptions
        ..clear()
        ..addAll(options);
      if (_labOptions.isNotEmpty) {
        _selectedLabId = _labOptions.first.id;
        _labController.text = _labOptions.first.name;
      } else {
        _selectedLabId = null;
        _labController.clear();
      }
      _loadingCatalog = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _indicationController.dispose();
    _labController.dispose();
    super.dispose();
  }

  Future<void> _sendOrder() async {
    if (_selectedTestIds.isEmpty) {
      AppToast.info(context, 'Select at least one lab test');
      return;
    }
    if (_labOptions.isEmpty || _selectedLabId == null || _selectedLabId!.isEmpty) {
      AppToast.info(context, 'Connect a lab first before sending orders');
      return;
    }

    final selectedTests = _allTests.where((t) => _selectedTestIds.contains(t.id)).toList();
    final selected = _labOptions.where((o) => o.name == _labController.text.trim()).firstOrNull;
    final lab = _labController.text.trim();

    setState(() => _sending = true);
    try {
      await LabOrderService.sendOrder(
        patient: widget.patient,
        testIds: selectedTests.map((t) => t.id).toList(),
        testNames: selectedTests.map((t) => t.name).toList(),
        labId: selected?.id ?? _selectedLabId, // FIXED: pass registered lab id when selected
        labName: lab.isNotEmpty ? lab : null,
        indication: _indicationController.text.trim(),
        urgency: _urgency,
        fastingRequired: _fastingRequired,
        homeCollection: _homeCollection,
        source: widget.source,
      );

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _LabOrderSentSheet(
          patientName: widget.patient.patientName,
          testNames: selectedTests.map((t) => t.name).toList(),
          labName: lab.isNotEmpty ? lab : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        AppToast.info(context, 'Failed to send lab order: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _categoryFor(patient_lab.LabTestItem test) {
    switch (test.sampleType) {
      case patient_lab.SampleType.blood:
        return 'Blood Tests';
      case patient_lab.SampleType.urine:
        return 'Urine Tests';
      case patient_lab.SampleType.stool:
        return 'Stool Tests';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClinicalSectionCard(
          title: 'Patient',
          child: Text(
            '${widget.patient.patientName} · ${widget.patient.age} yrs',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        ClinicalSectionCard(
          title: 'Select Tests',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search tests',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              if (_categories.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'All',
                      ..._categories,
                    ].map((cat) {
                      final selected = _categoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(cat, style: GoogleFonts.inter(fontSize: 11)),
                          selected: selected,
                          onSelected: (_) => setState(() => _categoryFilter = cat),
                          selectedColor: AppColors.doctorBlue.withValues(alpha: 0.15),
                          checkmarkColor: AppColors.doctorBlue,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 10),
              if (_filteredTests.isEmpty)
                Text(
                  'No tests found in catalog',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                )
              else
                ..._filteredTests.map((test) {
                  final selected = _selectedTestIds.contains(test.id);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: selected,
                    title: Text(test.name, style: GoogleFonts.inter(fontSize: 13)),
                    subtitle: Text(
                      _categoryFor(test),
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                    ),
                    activeColor: AppColors.doctorBlue,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedTestIds.add(test.id);
                      } else {
                        _selectedTestIds.remove(test.id);
                      }
                    }),
                  );
                }),
              if (_selectedTestIds.isNotEmpty)
                Text(
                  '${_selectedTestIds.length} test(s) selected',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.doctorBlue,
                  ),
                ),
            ],
          ),
        ),
        ClinicalSectionCard(
          title: 'Order Details',
          child: Column(
            children: [
              TextFormField(
                controller: _indicationController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Clinical indication',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _urgency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Urgency'),
                items: const [
                  DropdownMenuItem(value: 'Routine', child: Text('Routine')),
                  DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
                  DropdownMenuItem(value: 'STAT', child: Text('STAT')),
                ],
                onChanged: (v) => setState(() => _urgency = v!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fasting required'),
                value: _fastingRequired,
                activeTrackColor: AppColors.doctorBlue.withValues(alpha: 0.5),
                activeThumbColor: AppColors.doctorBlue,
                onChanged: (v) => setState(() => _fastingRequired = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Home collection'),
                value: _homeCollection,
                activeTrackColor: AppColors.doctorBlue.withValues(alpha: 0.5),
                activeThumbColor: AppColors.doctorBlue,
                onChanged: (v) => setState(() => _homeCollection = v),
              ),
              const SizedBox(height: 8),
              if (_labOptions.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Connected lab'),
                  initialValue: _labController.text.trim().isNotEmpty ? _labController.text.trim() : null,
                  items: _labOptions
                      .map((l) => DropdownMenuItem(value: l.name, child: Text(l.name)))
                      .toList(),
                  onChanged: (v) {
                    final picked = _labOptions.where((o) => o.name == v).firstOrNull;
                    setState(() {
                      _labController.text = v ?? '';
                      _selectedLabId = picked?.id;
                    });
                  },
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No connected labs yet',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Connect a diagnostic lab to send test orders.',
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DoctorConnectedLabsScreen()),
                          ).then((_) => _loadCatalog());
                        },
                        icon: const Icon(Icons.biotech_outlined, size: 18),
                        label: const Text('Connect Lab'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _sendOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.doctorBlue,
            minimumSize: const Size(double.infinity, 48),
          ),
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send Order'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LabOrderSentSheet extends StatelessWidget {
  const _LabOrderSentSheet({
    required this.patientName,
    required this.testNames,
    this.labName,
  });

  final String patientName;
  final List<String> testNames;
  final String? labName;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lab order sent successfully',
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SentTo(
                  icon: Icons.person_outline,
                  label: 'Patient notified',
                  name: patientName,
                  color: AppColors.patientTeal,
                ),
                const SizedBox(height: 12),
                _SentTo(
                  icon: Icons.biotech_outlined,
                  label: labName != null ? 'Lab order saved' : 'Lab (not selected)',
                  name: labName ?? 'No lab selected',
                  color: labName != null ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
                ),
                const SizedBox(height: 20),
                Text(
                  'Tests ordered (${testNames.length})',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondaryOf(context)),
                ),
                SizedBox(height: 8),
                ...testNames.map((t) => Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 6, color: AppColors.textSecondaryOf(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t,
                              style: GoogleFonts.inter(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.doctorBlue),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SentTo extends StatelessWidget {
  const _SentTo({
    required this.icon,
    required this.label,
    required this.name,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context))),
              Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
        Icon(Icons.check_circle_outline, size: 18, color: color),
      ],
    );
  }
}

class _LabPickerOption {
  const _LabPickerOption({this.id, required this.name});

  final String? id; // FIXED: registered lab id when available
  final String name;
}
