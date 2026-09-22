import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({
    super.key,
    this.onTap,
    this.onSubmitted,
  });

  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;

  static const List<String> rotatingPlaceholders = [
    'Search for doctor',
    'Search for lab',
    'Search for language or location',
    'Search for ambulance',
  ];

  static String placeholder({required bool compact}) {
    return compact
        ? 'Search doctors, lab, specialities…'
        : 'Doctor, lab, speciality, location, language…';
  }

  static String placeholderFor(BuildContext context) {
    return placeholder(compact: ResponsiveLayout.isCompact(context));
  }

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _rotationTimer;
  int _currentIndex = 0;
  bool _hovered = false;

  bool get _isFieldEmpty => _controller.text.isEmpty;
  bool get _isFocused => _focusNode.hasFocus;
  bool get _shouldShowOverlay => _isFieldEmpty && !_isFocused;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    _controller.addListener(_onFieldChanged);
    _focusNode.addListener(_onFieldChanged);

    _startTimer();
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
    if (_shouldShowOverlay) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _stopTimer();
    if (!_shouldShowOverlay) return;
    _rotationTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (_shouldShowOverlay) {
        setState(() {
          _currentIndex =
              (_currentIndex + 1) % HomeSearchBar.rotatingPlaceholders.length;
        });
        _startTimer();
      }
    });
  }

  void _stopTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _controller.removeListener(_onFieldChanged);
    _focusNode.removeListener(_onFieldChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit(String value) {
    final query = value.trim();
    if (query.isNotEmpty) {
      if (widget.onSubmitted != null) {
        widget.onSubmitted!(query);
      } else if (widget.onTap != null) {
        widget.onTap!();
      }
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final active = _hovered || _isFocused;

    return _SearchField(
      compact: compact,
      controller: _controller,
      focusNode: _focusNode,
      active: active,
      currentIndex: _currentIndex,
      showOverlay: _shouldShowOverlay,
      onSubmitted: _handleSubmit,
      onHoverChanged: (value) => setState(() => _hovered = value),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.compact,
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.currentIndex,
    required this.showOverlay,
    required this.onSubmitted,
    required this.onHoverChanged,
  });

  final bool compact;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
  final int currentIndex;
  final bool showOverlay;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final placeholderStyle = GoogleFonts.inter(
      fontSize: compact ? 14 : 15,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondaryOf(context),
      height: 1.2,
    );

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => focusNode.requestFocus(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: compact ? 50 : 54,
          padding: EdgeInsets.only(
            left: compact ? 14 : 16,
            right: compact ? 6 : 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? AppColors.patientTeal.withValues(alpha: 0.55)
                  : AppColors.borderOf(context),
              width: active ? 1.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.patientTeal.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.textPrimaryOf(context)
                          .withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: active
                    ? AppColors.patientTeal
                    : AppColors.textSecondaryOf(context),
                size: 22,
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: onSubmitted,
                      textAlignVertical: TextAlignVertical.center,
                      cursorColor: AppColors.patientTeal,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textPrimaryOf(context),
                        height: 1.2,
                      ),
                      decoration: const InputDecoration(
                        hintText: null,
                        isDense: true,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    if (showOverlay)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ClipRect(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                transitionBuilder: (Widget child,
                                    Animation<double> animation) {
                                  final isIncoming = child.key ==
                                      ValueKey<int>(currentIndex);
                                  final offsetTween = isIncoming
                                      ? Tween<Offset>(
                                          begin: const Offset(0.0, 0.8),
                                          end: Offset.zero,
                                        )
                                      : Tween<Offset>(
                                          begin: const Offset(0.0, -0.8),
                                          end: Offset.zero,
                                        );

                                  return SlideTransition(
                                    position: offsetTween.animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeInOutCubic,
                                      ),
                                    ),
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  );
                                },
                                layoutBuilder: (Widget? currentChild,
                                    List<Widget> previousChildren) {
                                  return Stack(
                                    alignment: Alignment.centerLeft,
                                    children: <Widget>[
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  );
                                },
                                child: Text(
                                  HomeSearchBar
                                      .rotatingPlaceholders[currentIndex],
                                  key: ValueKey<int>(currentIndex),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: placeholderStyle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (compact)
                _MobileSearchAction(
                  active: active,
                  onTap: () => onSubmitted(controller.text),
                )
              else
                _DesktopSearchAction(
                  onTap: () => onSubmitted(controller.text),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSearchAction extends StatelessWidget {
  const _MobileSearchAction({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active
            ? AppColors.patientTeal
            : AppColors.patientTeal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color:
                  active ? AppColors.surfaceOf(context) : AppColors.patientTeal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSearchAction extends StatefulWidget {
  const _DesktopSearchAction({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DesktopSearchAction> createState() => _DesktopSearchActionState();
}

class _DesktopSearchActionState extends State<_DesktopSearchAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF0D5C47) : AppColors.patientTeal,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            'Search',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w600,
              color: AppColors.surfaceOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
