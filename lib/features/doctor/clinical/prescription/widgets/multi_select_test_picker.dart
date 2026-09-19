import '../../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../data/medical_tests_catalog.dart';
import '../../../../../core/theme/app_typography.dart';

class TestPickerResult {
  TestPickerResult({required this.selectedIds, required this.customNames});

  final Set<String> selectedIds;
  final List<String> customNames;
}

/// Reusable searchable multi-select for [TestCatalogItem] lists.
/// Returns a [TestPickerResult] with catalog IDs + any custom test names.
class MultiSelectTestPicker {
  static Future<TestPickerResult?> show(
    BuildContext context, {
    required String title,
    required List<TestCatalogItem> catalog,
    required Set<String> initiallySelectedIds,
    List<String> initiallyCustomNames = const [],
    Future<String?> Function(String name)? onPersistCustom,
    String customAddLabel = '+ Add Lab Test',
    bool allowCustomAdd = true,
  }) {
    return showModalBottomSheet<TestPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TestPickerSheet(
        title: title,
        catalog: catalog,
        initiallySelectedIds: initiallySelectedIds,
        initiallyCustomNames: initiallyCustomNames,
        onPersistCustom: onPersistCustom,
        allowCustomAdd: allowCustomAdd,
      ),
    );
  }
}

class _TestPickerSheet extends StatefulWidget {
  const _TestPickerSheet({
    required this.title,
    required this.catalog,
    required this.initiallySelectedIds,
    required this.initiallyCustomNames,
    this.onPersistCustom,
    this.allowCustomAdd = true,
  });

  final String title;
  final List<TestCatalogItem> catalog;
  final Set<String> initiallySelectedIds;
  final List<String> initiallyCustomNames;
  final Future<String?> Function(String name)? onPersistCustom;
  final bool allowCustomAdd;

  @override
  State<_TestPickerSheet> createState() => _TestPickerSheetState();
}

class _TestPickerSheetState extends State<_TestPickerSheet> {
  late final Set<String> _selectedIds;
  late final List<String> _customNames;
  final _searchController = TextEditingController();
  final List<TestCatalogItem> _extraItems = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.initiallySelectedIds};
    _customNames = [...widget.initiallyCustomNames];
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _queryRaw => _searchController.text.trim();

  List<TestCatalogItem> get _allCatalog => [...widget.catalog, ..._extraItems];

  List<TestCatalogItem> get _filtered {
    if (_query.isEmpty) return _allCatalog;
    return _allCatalog
        .where((t) => t.name.toLowerCase().contains(_query))
        .toList();
  }

  Map<String, List<TestCatalogItem>> get _grouped {
    final map = <String, List<TestCatalogItem>>{};
    for (final t in _filtered) {
      map.putIfAbsent(t.group, () => []).add(t);
    }
    return map;
  }

  bool get _canOfferAdd {
    if (!widget.allowCustomAdd) return false;
    if (_queryRaw.isEmpty) return false;
    final key = _queryRaw.toLowerCase();
    return !_allCatalog.any((t) => t.name.trim().toLowerCase() == key);
  }

  Future<void> _addCustomFromQuery(String name) async {
    if (name.isEmpty || !widget.allowCustomAdd) return;

    if (widget.onPersistCustom != null) {
      try {
        final id = await widget.onPersistCustom!(name);
        if (!mounted) return;
        if (id != null) {
          setState(() {
            _selectedIds.add(id);
            _extraItems
                .add(TestCatalogItem(id: id, name: name, group: 'Custom'));
          });
          return;
        }
      } catch (e) {
        if (mounted) {
          AppToast.info(context, '$e');
        }
        return;
      }
    }

    setState(() {
      if (!_customNames.contains(name)) _customNames.add(name);
    });
    if (mounted) {}
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final groupKeys = grouped.keys.toList();
    final filteredEmpty = _filtered.isEmpty;
    final showAddTop = _canOfferAdd && filteredEmpty;
    final showAddBottom = _canOfferAdd && !filteredEmpty;
    final totalSelected = _selectedIds.length + _customNames.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (totalSelected > 0)
                          Text(
                            '$totalSelected selected',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              color: AppColors.doctorBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      TestPickerResult(
                        selectedIds: _selectedIds,
                        customNames: _customNames,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.doctorBlue,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search tests',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _searchController.clear(),
                        ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (showAddTop)
                    _AddCustomSearchTile(
                      query: _queryRaw,
                      suffix: 'as custom test',
                      onTap: () => _addCustomFromQuery(_queryRaw),
                    ),
                  ...groupKeys.map((key) => _buildGroup(key, grouped[key]!)),
                  if (showAddBottom)
                    _AddCustomSearchTile(
                      query: _queryRaw,
                      onTap: () => _addCustomFromQuery(_queryRaw),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroup(String group, List<TestCatalogItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            group.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w700,
              color: AppColors.doctorBlue,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items.map((t) {
          final selected = _selectedIds.contains(t.id);
          return InkWell(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedIds.remove(t.id);
                } else {
                  _selectedIds.add(t.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: selected,
                    activeColor: AppColors.doctorBlue,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) {
                      setState(() {
                        if (selected) {
                          _selectedIds.remove(t.id);
                        } else {
                          _selectedIds.add(t.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      t.name,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textPrimaryOf(context),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Generic multi-select bottom sheet for plain string lists (e.g. body parts).
class MultiSelectStringPicker {
  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required List<String> options,
    required List<String> initiallySelected,
    Future<String?> Function(String name)? onPersistCustom,
    bool allowCustomAdd = true,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StringPickerSheet(
        title: title,
        options: options,
        initiallySelected: initiallySelected,
        onPersistCustom: onPersistCustom,
        allowCustomAdd: allowCustomAdd,
      ),
    );
  }
}

class _StringPickerSheet extends StatefulWidget {
  const _StringPickerSheet({
    required this.title,
    required this.options,
    required this.initiallySelected,
    this.onPersistCustom,
    this.allowCustomAdd = true,
  });

  final String title;
  final List<String> options;
  final List<String> initiallySelected;
  final Future<String?> Function(String name)? onPersistCustom;
  final bool allowCustomAdd;

  @override
  State<_StringPickerSheet> createState() => _StringPickerSheetState();
}

class _StringPickerSheetState extends State<_StringPickerSheet> {
  late final List<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';
  final List<String> _extraOptions = [];

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initiallySelected];
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _queryRaw => _searchController.text.trim();

  List<String> get _allOptions => [...widget.options, ..._extraOptions];

  List<String> get _filtered {
    if (_query.isEmpty) return _allOptions;
    return _allOptions.where((o) => o.toLowerCase().contains(_query)).toList();
  }

  bool get _canOfferAdd {
    if (!widget.allowCustomAdd) return false;
    if (_queryRaw.isEmpty) return false;
    final key = _queryRaw.toLowerCase();
    return !_allOptions.any((o) => o.trim().toLowerCase() == key);
  }

  Future<void> _addCustomFromQuery(String name) async {
    if (name.isEmpty || !widget.allowCustomAdd) return;

    if (widget.onPersistCustom != null) {
      try {
        final savedName = await widget.onPersistCustom!(name);
        if (!mounted) return;
        if (savedName != null) {
          setState(() {
            if (!_allOptions
                .any((o) => o.toLowerCase() == savedName.toLowerCase())) {
              _extraOptions.add(savedName);
            }
            if (!_selected.contains(savedName)) _selected.add(savedName);
          });
          return;
        }
      } catch (e) {
        if (mounted) {
          AppToast.info(context, '$e');
        }
        return;
      }
    }

    setState(() {
      if (!_selected.contains(name)) _selected.add(name);
    });
    if (mounted) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final showAddTop = _canOfferAdd && filtered.isEmpty;
    final showAddBottom = _canOfferAdd && filtered.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (_selected.isNotEmpty)
                          Text(
                            '${_selected.length} selected',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              color: AppColors.doctorBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.doctorBlue,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _searchController.clear(),
                        ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (showAddTop)
                    _AddCustomSearchTile(
                      query: _queryRaw,
                      suffix: 'as custom body part',
                      onTap: () => _addCustomFromQuery(_queryRaw),
                    ),
                  ...filtered.map((item) {
                    final selected = _selected.contains(item);
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selected.remove(item);
                          } else {
                            _selected.add(item);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              activeColor: AppColors.doctorBlue,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (_) {
                                setState(() {
                                  if (selected) {
                                    _selected.remove(item);
                                  } else {
                                    _selected.add(item);
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodySmall,
                                  color: AppColors.textPrimaryOf(context),
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (showAddBottom)
                    _AddCustomSearchTile(
                      query: _queryRaw,
                      onTap: () => _addCustomFromQuery(_queryRaw),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AddCustomSearchTile extends StatelessWidget {
  const _AddCustomSearchTile({
    required this.query,
    required this.onTap,
    this.suffix,
  });

  final String query;
  final VoidCallback onTap;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading:
          Icon(Icons.add_circle_outline, color: AppColors.doctorBlue, size: 22),
      title: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodySmall,
            color: AppColors.doctorBlue,
            fontWeight: FontWeight.w600,
          ),
          children: [
            const TextSpan(text: '+ Add '),
            TextSpan(
              text: "'$query'",
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.doctorBlue,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (suffix != null) TextSpan(text: ' $suffix'),
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}
