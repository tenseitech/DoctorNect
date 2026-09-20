import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/specialty_categories.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/stomach_icon.dart';
import '../../search/doctor_search_screen.dart';
import '../../../../core/theme/app_typography.dart';

class ExploreSection extends StatelessWidget {
  const ExploreSection({super.key});

  static const _mobileBreakpoint = 600.0;
  static const _homePreviewCount = 5;
  static const _tileSpacing = 8.0;

  @override
  Widget build(BuildContext context) {
    final allCategories = specialtyCategories.keys.toList();
    final isWide = MediaQuery.sizeOf(context).width >= _mobileBreakpoint;
    final previewCategories = allCategories.take(_homePreviewCount).toList();

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide ? 20 : 16,
          isWide ? 20 : 12,
          isWide ? 20 : 16,
          isWide ? 20 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Specialities',
                    style: GoogleFonts.inter(
                      fontSize: isWide ? 17 : 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                if (!isWide)
                  TextButton(
                    onPressed: () => _showAllSpecialitiesSheet(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.patientTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'View all',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            SizedBox(height: isWide ? 16 : 12),
            if (isWide)
              _ExploreWideGrid(
                categories: allCategories,
                onCategoryTap: (category) =>
                    _openDoctorSearchForCategory(context, category),
              )
            else
              Row(
                children: [
                  for (var i = 0; i < previewCategories.length; i++) ...[
                    if (i > 0) const SizedBox(width: _tileSpacing),
                    Expanded(
                      child: _ExploreCategoryTile(
                        label: previewCategories[i],
                        onTap: () => _openDoctorSearchForCategory(
                            context, previewCategories[i]),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  static void _openDoctorSearchForCategory(
      BuildContext context, String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorSearchScreen(initialCategory: category),
      ),
    );
  }

  static void _showAllSpecialitiesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ExploreAllSheet(
        onCategoryTap: (category) {
          Navigator.pop(sheetContext);
          _openDoctorSearchForCategory(context, category);
        },
      ),
    );
  }
}

class _ExploreWideGrid extends StatelessWidget {
  const _ExploreWideGrid({
    required this.categories,
    required this.onCategoryTap,
  });

  final List<String> categories;
  final ValueChanged<String> onCategoryTap;

  static const _tileWidth = 88.0;
  static const _spacing = 18.0;
  static const _rowHeight = 116.0;

  static int _columnCount(double width, int itemCount) {
    final maxFit = ((width + _spacing) / (_tileWidth + _spacing)).floor();
    final maxCols = maxFit.clamp(6, 8);

    var bestCols = maxCols;
    var bestScore = -1.0;

    for (var cols = 6; cols <= maxCols; cols++) {
      final lastRowCount = itemCount % cols == 0 ? cols : itemCount % cols;
      final rowCount = (itemCount / cols).ceil();
      final fillRatio = lastRowCount / cols;
      final score = fillRatio - rowCount * 0.02;
      if (score > bestScore) {
        bestScore = score;
        bestCols = cols;
      }
    }

    return bestCols;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth, categories.length);
        final textScale =
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
        final rowExtent = _rowHeight * textScale;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categories.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _spacing,
            mainAxisSpacing: 24,
            mainAxisExtent: rowExtent,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _tileWidth,
                child: _ExploreCategoryTile(
                  label: category,
                  fixedWidth: _tileWidth,
                  onTap: () => onCategoryTap(category),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ExploreAllSheet extends StatefulWidget {
  const _ExploreAllSheet({required this.onCategoryTap});

  final ValueChanged<String> onCategoryTap;

  @override
  State<_ExploreAllSheet> createState() => _ExploreAllSheetState();
}

class _ExploreAllSheetState extends State<_ExploreAllSheet> {
  final _searchController = TextEditingController();
  late final List<String> _categories = specialtyCategories.keys.toList();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _categories;
    return _categories
        .where((category) => category.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filtered = _filtered;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'All specialities',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.headlineSmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search speciality',
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.patientTeal),
                      filled: true,
                      fillColor: AppColors.cardBgOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No specialities found',
                            style: GoogleFonts.inter(
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        )
                      : GridView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 108 * textScale,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, index) {
                            final category = filtered[index];
                            return _ExploreCategoryTile(
                              label: category,
                              onTap: () => widget.onCategoryTap(category),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExploreCategoryTile extends StatelessWidget {
  const _ExploreCategoryTile({
    required this.label,
    required this.onTap,
    this.fixedWidth,
  });

  final String label;
  final VoidCallback onTap;
  final double? fixedWidth;

  Widget _buildFallback(BuildContext context, double iconSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: label == 'Stomach & Digestion'
          ? StomachIcon(
              size: iconSize * 1.15,
              color: isDark ? Colors.white : AppColors.patientTeal,
            )
          : Icon(
              _ExploreIcons.forCategory(label),
              size: iconSize,
              color: isDark ? Colors.white : AppColors.patientTeal,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useWideTile = fixedWidth != null && fixedWidth! >= 84;

    Widget buildContent(double width) {
      final iconBox = useWideTile ? 56.0 : (width * 0.78).clamp(42.0, 60.0);
      final fontSize = useWideTile ? 11.0 : (width * 0.132).clamp(9.0, 11.0);
      final assetPath = _ExploreSpecialtyAssets.forCategory(label);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF27272A) : const Color(0xFFE2E8F0),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Padding(
                padding: const EdgeInsets.all(7.0),
                child: assetPath != null
                    ? Image.asset(
                        assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            _buildFallback(context, iconBox * 0.45),
                      )
                    : _buildFallback(context, iconBox * 0.45),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      );
    }

    final child = fixedWidth != null
        ? buildContent(fixedWidth!)
        : LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                      ? constraints.maxWidth
                      : 92.0;
              return buildContent(width);
            },
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

abstract final class _ExploreSpecialtyAssets {
  static const Map<String, String> _assetPaths = {
    'General Physician': 'assets/images/specialties/general_physician.png',
    "Women's Health": 'assets/images/specialties/womens_health.png',
    'Child Care': 'assets/images/specialties/child_care.png',
    'Eye Specialist': 'assets/images/specialties/eye_specialist.png',
    'Ear, Nose & Throat': 'assets/images/specialties/ear_nose_throat.png',
    // 'Dentist' will be used once dentist.png is provided
    'Heart Specialist': 'assets/images/specialties/heart_specialist.png',
    'Mental Wellness': 'assets/images/specialties/mental_wellness.png',
    'Skin Specialist': 'assets/images/specialties/skin_specialist.png',
    'Bone & Joint': 'assets/images/specialties/bone_joint.png',
    'Diabetes': 'assets/images/specialties/diabetes.png',
    'Stomach & Digestion': 'assets/images/specialties/stomach_digestion.png',
    'Urinary Problems': 'assets/images/specialties/urinary_problems.png',
    'Physiotherapist': 'assets/images/specialties/physiotherapist.png',
    'Lung & Respiratory': 'assets/images/specialties/lung_respiratory.png',
    'Dietitian': 'assets/images/specialties/dietitian.png',
    'Cancer Specialist': 'assets/images/specialties/cancer_specialist.png',
    'Neurologist': 'assets/images/specialties/neurologist.png',
    'General Surgeon': 'assets/images/specialties/general_surgeon.png',
    'Sexual Health': 'assets/images/specialties/sexual_health.png',
    'Ayurveda': 'assets/images/specialties/ayurveda.png',
    'Homeopathy': 'assets/images/specialties/homeopathy.png',
    'Veterinary': 'assets/images/specialties/veterinary.png',
  };

  static String? forCategory(String category) => _assetPaths[category];
}

abstract final class _ExploreIcons {
  static const Map<String, IconData> _icons = {
    'General Physician': TablerIcons.stethoscope,
    "Women's Health": TablerIcons.gender_female,
    'Child Care': TablerIcons.baby_carriage,
    'Eye Specialist': TablerIcons.eye,
    'Ear, Nose & Throat': TablerIcons.ear,
    'Dentist': TablerIcons.dental,
    'Heart Specialist': TablerIcons.heart,
    'Mental Wellness': TablerIcons.brain,
    'Skin Specialist': TablerIcons.hand_stop,
    'Bone & Joint': TablerIcons.bone,
    'Diabetes': TablerIcons.needle,
    'Stomach & Digestion': TablerIcons.pill,
    'Urinary Problems': TablerIcons.droplet,
    'Physiotherapist': TablerIcons.run,
    'Lung & Respiratory': TablerIcons.lungs,
    'Dietitian': TablerIcons.apple,
    'Cancer Specialist': TablerIcons.ribbon_health,
    'Neurologist': TablerIcons.brain,
    'General Surgeon': TablerIcons.scissors,
    'Sexual Health': TablerIcons.venus,
    'Ayurveda': TablerIcons.leaf,
    'Homeopathy': TablerIcons.flask,
    'Veterinary': TablerIcons.paw,
  };

  static IconData forCategory(String category) {
    return _icons[category] ?? TablerIcons.stethoscope;
  }
}
