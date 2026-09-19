import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/utils/external_launcher.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../../../../widgets/overflow_safe_layout.dart';
import '../../../../widgets/phone_number_field.dart';
import '../data/medical_directory_store.dart';
import '../../../../core/firebase/models/doctor_medical_directory_entry.dart';

class MedicalDirectorySection extends StatefulWidget {
  const MedicalDirectorySection({super.key});

  @override
  State<MedicalDirectorySection> createState() =>
      _MedicalDirectorySectionState();
}

class _MedicalDirectorySectionState extends State<MedicalDirectorySection> {
  final _store = MedicalDirectoryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    if (_store.forDoctor(DoctorSession.loggedInDoctorId).isEmpty &&
        !_store.isLoading) {
      _store.refreshForDoctor();
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  List<DoctorMedicalDirectoryEntry> get _entries =>
      _store.forDoctor(DoctorSession.loggedInDoctorId);

  Future<void> _saveEntry({
    DoctorMedicalDirectoryEntry? existing,
    required String name,
    required String type,
    required String phone,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'Name and phone are required');
      return;
    }

    final doctorId = DoctorSession.loggedInDoctorId;
    if (existing == null) {
      _store.add(
        DoctorMedicalDirectoryEntry(
          entryId: 'dir_${DateTime.now().microsecondsSinceEpoch}',
          doctorId: doctorId,
          name: trimmedName,
          type: type.trim(),
          phone: trimmedPhone,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      _store.update(
        DoctorMedicalDirectoryEntry(
          entryId: existing.entryId,
          doctorId: doctorId,
          name: trimmedName,
          type: type.trim(),
          phone: trimmedPhone,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  void _addEntry() {
    _showEntryDialog();
  }

  void _editEntry(DoctorMedicalDirectoryEntry entry) {
    _showEntryDialog(existing: entry);
  }

  void _showEntryDialog({DoctorMedicalDirectoryEntry? existing}) {
    final name = TextEditingController(text: existing?.name ?? '');
    final type = TextEditingController(text: existing?.type ?? '');
    final parsedPhone = FormValidators.parsePhone(existing?.phone);
    final phone = TextEditingController(text: parsedPhone.localNumber);
    var phoneDialCode = parsedPhone.dialCode;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(existing == null ? 'Add Directory Entry' : 'Edit Entry'),
              content: scrollableDialogContent(
                context: context,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                          labelText: 'Name (Lab/Specialist)'),
                    ),
                    TextField(
                      controller: type,
                      decoration: const InputDecoration(
                          labelText: 'Type (e.g. Ambulance)'),
                    ),
                    PhoneNumberField(
                      controller: phone,
                      initialDialCode: phoneDialCode,
                      onDialCodeChanged: (code) => phoneDialCode = code,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () async {
                    await _saveEntry(
                      existing: existing,
                      name: name.text,
                      type: type.text,
                      phone: FormValidators.formatFullPhone(
                          phoneDialCode, phone.text),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteEntry(DoctorMedicalDirectoryEntry entry) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Delete entry?',
      message: 'Remove ${entry.name} from your directory?',
    );
    if (confirmed) {
      _store.remove(entry.entryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _store.isLoading && _entries.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Medical Directory')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No entries added yet.'))
              : Align(
                  alignment: Alignment.topCenter,
                  child: RefreshIndicator(
                    onRefresh: () =>
                        _store.refreshForDoctor(preferCache: false),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: _entries.map((entry) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                title: Text(entry.name),
                                subtitle:
                                    Text('${entry.type} • ${entry.phone}'),
                                onTap: () => ExternalLauncher.callPhone(
                                    entry.phone,
                                    context: context),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.phone, size: 20),
                                      onPressed: () =>
                                          ExternalLauncher.callPhone(
                                              entry.phone,
                                              context: context),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () => _editEntry(entry),
                                    ),
                                    LabeledRemoveButton(
                                      label: 'Delete',
                                      onPressed: () => _deleteEntry(entry),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}
