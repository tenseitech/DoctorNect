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


  static const List<String> words = [
    'Doctors',
    'Labs',
    'Speciality',
    'Location',
    'Language',
  ];

  static const List<String> placeholders = [
    'Search for Doctors',
    'Search for Labs',
    'Search for Speciality',
    'Search for Location',
    'Search for Language',
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
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
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
    required this.showOverlay,
    required this.onSubmitted,
    required this.onHoverChanged,
  });

  final bool compact;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
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
                            child: _TypewriterPlaceholder(
                              words: HomeSearchBar.words,
                              style: placeholderStyle,
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

class _TypewriterPlaceholder extends StatefulWidget {
  const _TypewriterPlaceholder({
    required this.words,
    required this.style,
    this.prefix = 'Search for ',
  });

  final List<String> words;
  final TextStyle style;
  final String prefix;

  @override
  State<_TypewriterPlaceholder> createState() => _TypewriterPlaceholderState();
}

class _TypewriterPlaceholderState extends State<_TypewriterPlaceholder> {
  Timer? _timer;
  int _wordIndex = 0;
  int _charIndex = 0;
  bool _isDeleting = false;

  static const Duration _typingDelay = Duration(milliseconds: 90);
  static const Duration _deletingDelay = Duration(milliseconds: 45);
  static const Duration _pauseFull = Duration(milliseconds: 1800);
  static const Duration _pauseEmpty = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(covariant _TypewriterPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words != widget.words) {
      _wordIndex = 0;
      _charIndex = 0;
      _isDeleting = false;
      _startAnimation();
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    if (!mounted || widget.words.isEmpty) return;

    final currentWord = widget.words[_wordIndex];

    if (!_isDeleting) {
      if (_charIndex < currentWord.length) {
        _timer = Timer(_typingDelay, () {
          if (!mounted) return;
          setState(() {
            _charIndex++;
          });
          _startAnimation();
        });
      } else {
        _timer = Timer(_pauseFull, () {
          if (!mounted) return;
          setState(() {
            _isDeleting = true;
          });
          _startAnimation();
        });
      }
    } else {
      if (_charIndex > 0) {
        _timer = Timer(_deletingDelay, () {
          if (!mounted) return;
          setState(() {
            _charIndex--;
          });
          _startAnimation();
        });
      } else {
        _timer = Timer(_pauseEmpty, () {
          if (!mounted) return;
          setState(() {
            _isDeleting = false;
            _wordIndex = (_wordIndex + 1) % widget.words.length;
          });
          _startAnimation();
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) {
      return Text(
        widget.prefix,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }

    final currentWord = widget.words[_wordIndex];
    final visibleCount = _charIndex.clamp(0, currentWord.length);
    final typedWord = currentWord.substring(0, visibleCount);

    return Text.rich(
      TextSpan(
        text: widget.prefix,
        style: widget.style,
        children: [
          TextSpan(
            text: typedWord,
            style: widget.style,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
