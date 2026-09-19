import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/media/gallery_image_picker.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/indian_cities.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/services/promoted_ads_service.dart';
import '../../../core/services/razorpay_payment_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/banner_config_model.dart';
import '../../../core/services/banner_config_service.dart';
import '../../../core/theme/app_typography.dart';

/// Multi-step Promotional Ad Creation and Payment Gateway Flow (Light & Dark Mode Enabled)
class CreatePromotedAdScreen extends StatefulWidget {
  const CreatePromotedAdScreen({
    super.key,
    required this.providerType, // 'doctor', 'lab', 'pharmacy', 'ambulance'
    required this.providerId,
    required this.providerEmail,
    required this.providerContact,
  });

  final String providerType;
  final String providerId;
  final String providerEmail;
  final String providerContact;

  @override
  State<CreatePromotedAdScreen> createState() => _CreatePromotedAdScreenState();
}

class _CreatePromotedAdScreenState extends State<CreatePromotedAdScreen> {
  int _currentStep = 0; // 0: Overview, 1: Banner Setup, 2: Campaign Plan

  // Real-time Super Admin Banner Config
  BannerConfigModel? _bannerConfig;
  StreamSubscription<BannerConfigModel>? _configSub;

  // Step 1: Promotion Type Selection
  String _selectedOption = 'banner';

  // Step 2: Form, City & Image Upload
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _linkController = TextEditingController();

  // Multi-City Selection
  Set<String> _selectedCities = {'Nagpur'};

  int get _combinedDailyRate {
    if (_selectedCities.isEmpty) return 100;
    return _selectedCities.fold<int>(
        0, (sum, city) => sum + IndianCities.dailyRate(city));
  }

  String get _rateSumFormulaString {
    if (_selectedCities.isEmpty) return '';
    final parts = _selectedCities
        .map((c) => '$c (₹${IndianCities.dailyRate(c)})')
        .join(' + ');
    return 'Rate Sum: $parts = ₹$_combinedDailyRate/day';
  }

  String get _rateSumPillFormulaString {
    if (_selectedCities.isEmpty) return '₹100';
    return _selectedCities
        .map((c) => '₹${IndianCities.dailyRate(c)}')
        .join(' + ');
  }

  String get _citiesSnippet {
    if (_selectedCities.isEmpty) return '';
    final list = _selectedCities.toList();
    if (list.length <= 2) return list.join(', ');
    return '${list.take(2).join(', ')}, +${list.length - 2} more';
  }

  int _calculatePlanPrice(int days) {
    final hours = days * 24;
    final basePrice =
        _bannerConfig?.pricingTiers[hours] ?? (_combinedDailyRate * days);
    if (_selectedCities.length <= 1) {
      return basePrice;
    }
    final multiplier = _combinedDailyRate / 100.0;
    return (basePrice * (multiplier > 1 ? multiplier : 1.0)).round();
  }

  Uint8List? _selectedImageBytes;
  late String _selectedCtaLabel;

  // Step 3: Plan Selection Carousel
  final PageController _planPageController =
      PageController(viewportFraction: 0.88);
  int _selectedPlanIndex = 1; // Default to "Most Popular" (3 Days / 72h)

  static const List<Map<String, dynamic>> _campaignPlans = [
    {
      'days': 1,
      'hours': 24,
      'title': '1 Day',
      'badge': 'Starter Reach',
      'subtitle': 'Starter campaign for quick local awareness',
    },
    {
      'days': 3,
      'hours': 72,
      'title': '3 Days',
      'badge': 'Most Popular',
      'subtitle': 'Most popular choice for steady patient flow',
    },
    {
      'days': 7,
      'hours': 168,
      'title': '7 Days (1 Week)',
      'badge': 'High Growth',
      'subtitle': 'Sustained campaign for maximum conversions',
    },
    {
      'days': 30,
      'hours': 720,
      'title': '30 Days (1 Month)',
      'badge': 'Maximum Reach',
      'subtitle': 'All perks of starter, growth, and premium positioning',
    },
  ];

  bool _submitting = false;
  String _loadingMessage = '';

  @override
  void initState() {
    super.initState();
    _selectedCtaLabel = _defaultCtaForProvider(widget.providerType);
    _configSub = BannerConfigService.streamConfig().listen((config) {
      if (mounted) setState(() => _bannerConfig = config);
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _titleController.dispose();
    _descController.dispose();
    _linkController.dispose();
    _planPageController.dispose();
    super.dispose();
  }

  String _defaultCtaForProvider(String type) {
    return switch (type.toLowerCase()) {
      'lab' => 'Order Lab Tests',
      'pharmacy' => 'Order Medicine',
      'ambulance' => 'Call Ambulance',
      _ => 'Book Appointment',
    };
  }

  String get _providerLabel => switch (widget.providerType.toLowerCase()) {
        'doctor' => 'Medical Practice & Clinic',
        'lab' => 'Diagnostic Lab & Tests',
        'pharmacy' => 'Medical Store & Pharmacy',
        'ambulance' => 'Ambulance Service',
        _ => 'Healthcare Service',
      };

  Future<void> _pickAdImage() async {
    try {
      final picked = await GalleryImagePicker.pickSingle();
      if (picked != null && mounted) {
        setState(() => _selectedImageBytes = picked.bytes);
      }
    } catch (e) {
      if (mounted)
        AppToast.error(context, 'Could not pick image. Please try again.');
    }
  }

  Future<void> _submitAndPay() async {
    if (_bannerConfig != null && !_bannerConfig!.enabled) {
      final notice = _bannerConfig!.bannerNotice.isNotEmpty
          ? _bannerConfig!.bannerNotice
          : 'Banner promotion system is currently paused by administrator.';
      AppToast.error(context, notice);
      return;
    }

    final plan = _campaignPlans[_selectedPlanIndex];
    final durationHours = plan['hours'] as int;
    final planDays = plan['days'] as int;
    final totalAmount = _calculatePlanPrice(planDays);

    setState(() {
      _submitting = true;
      _loadingMessage = 'Creating ad draft & uploading image...';
    });

    try {
      // 1. Create draft document & upload image to Firebase Storage
      final adModel = await PromotedAdsService.createDraftAd(
        providerType: widget.providerType,
        providerId: widget.providerId,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : 'Promote $_providerLabel',
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : 'Feature your service on Patient Home',
        imageBytes: _selectedImageBytes!,
        ctaLabel: _selectedCtaLabel,
        durationHours: durationHours,
        targetCity: _selectedCities.join(', '),
        targetCities: _selectedCities.toList(),
        customAmountPaid: totalAmount,
      );

      setState(() => _loadingMessage = 'Creating Razorpay payment order...');

      // 2. Create Razorpay order via Cloud Function
      final orderData = await PromotedAdsService.createRazorpayOrder(
        adId: adModel.adId,
        durationHours: durationHours,
      );

      final orderId = orderData['orderId'] as String;
      final keyId = orderData['keyId'] as String;
      final amount = orderData['amount'] as num;

      setState(() => _loadingMessage = 'Opening Razorpay checkout...');

      // 3. Open Razorpay Checkout and collect payment result
      final paymentResult = await RazorpayPaymentHelper.instance.openCheckout(
        keyId: keyId,
        orderId: orderId,
        amountINR: amount,
        title: 'DoctorNect Promoted Ad',
        description: '${plan['title']} campaign — $_providerLabel',
        prefillEmail: widget.providerEmail,
        prefillContact: widget.providerContact,
      );

      if (!mounted) return;

      if (!paymentResult.success) {
        setState(() => _submitting = false);
        AppToast.error(
          context,
          paymentResult.errorMessage ?? 'Payment was cancelled or failed.',
        );
        return;
      }

      setState(() => _loadingMessage = 'Verifying payment...');

      // 4. Verify payment server-side
      final verified = await PromotedAdsService.verifyRazorpayPayment(
        adId: adModel.adId,
        orderId: paymentResult.orderId ?? orderId,
        paymentId: paymentResult.paymentId!,
        signature: paymentResult.signature!,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (verified) {
        Navigator.pop(context, true);
      } else {
        AppToast.error(
            context, 'Payment verification failed. Please contact support.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        AppToast.error(context, 'Error processing payment: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _currentStep == 0
              ? 'Promote'
              : _currentStep == 1
                  ? 'Banner Promotion'
                  : 'Banner Campaign Plan',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: AppTypography.headlineSmall),
        ),
        centerTitle: true,
      ),
      body: _submitting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFF97316)),
                  const SizedBox(height: 20),
                  Text(
                    _loadingMessage,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_bannerConfig != null && !_bannerConfig!.enabled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_outline,
                            color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _bannerConfig!.bannerNotice.isNotEmpty
                                ? _bannerConfig!.bannerNotice
                                : 'Banner promotion system is currently paused by administrator.',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Top Step Progress Indicator Bar
                Container(
                  color: AppColors.surfaceOf(context),
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).size.width > 900 ? 40 : 16,
                    vertical: 14,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Row(
                      children: [
                        _buildStepBadge(0, 'Overview'),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: _currentStep >= 1
                                ? const Color(0xFF7C3AED)
                                : AppColors.borderOf(context),
                          ),
                        ),
                        _buildStepBadge(1, 'Banner'),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: _currentStep >= 2
                                ? const Color(0xFF7C3AED)
                                : AppColors.borderOf(context),
                          ),
                        ),
                        _buildStepBadge(2, 'Plan & Pay'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _currentStep,
                    children: [
                      _buildStep1Overview(isDark),
                      _buildStep2BannerSetup(isDark),
                      _buildStep3PlanSelection(isDark),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStepBadge(int stepIndex, String label) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: isDone
              ? const Color(0xFF7C3AED)
              : isActive
                  ? const Color(0xFF7C3AED)
                  : (isDark ? const Color(0xFF334155) : Colors.grey.shade200),
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '${stepIndex + 1}',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? Colors.white
                        : (isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive
                  ? const Color(0xFF7C3AED)
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1: Overview & Promotion Options (Dynamic Dark / Light Mode)
  // ---------------------------------------------------------------------------
  Widget _buildStep1Overview(bool isDark) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Purple Hero Card with Megaphone graphic
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF2E1065), const Color(0xFF1E1B4B)]
                        : [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF4C1D95)
                        : const Color(0xFFDDD6FE),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Get more visibility\nAttract more patients.',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? const Color(0xFFDDD6FE)
                                  : const Color(0xFF4C1D95),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Promote your $_providerLabel on patient portal and reach thousands of aspiring patients.',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFFC4B5FD)
                                  : const Color(0xFF6B21A8),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF7C3AED).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(TablerIcons.speakerphone,
                            color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // "Why Promote" Section Cards
              Text(
                'Why Promote',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildWhyPromoteCard(
                      icon: TablerIcons.eye,
                      iconBg: isDark
                          ? const Color(0xFF3B0764)
                          : const Color(0xFFF3E8FF),
                      iconColor: isDark
                          ? const Color(0xFFC4B5FD)
                          : const Color(0xFF7C3AED),
                      title: 'Increase Visibility',
                      subtitle:
                          'Show your practice to thousands of active patients',
                    ),
                    const SizedBox(width: 12),
                    _buildWhyPromoteCard(
                      icon: TablerIcons.users,
                      iconBg: isDark
                          ? const Color(0xFF3B0764)
                          : const Color(0xFFF3E8FF),
                      iconColor: isDark
                          ? const Color(0xFFC4B5FD)
                          : const Color(0xFF7C3AED),
                      title: 'Target Right Patients',
                      subtitle:
                          'Reach patients searching in your city & specialty',
                    ),
                    const SizedBox(width: 12),
                    _buildWhyPromoteCard(
                      icon: TablerIcons.bolt,
                      iconBg: isDark
                          ? const Color(0xFF451A03)
                          : const Color(0xFFFEF3C7),
                      iconColor: isDark
                          ? const Color(0xFFFDE047)
                          : const Color(0xFFD97706),
                      title: 'Instant Bookings',
                      subtitle:
                          'Direct CTA button leads patients straight to booking',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // "Promotion Options" Card
              Text(
                'Promotion Options',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              _buildOptionCard(
                id: 'banner',
                icon: TablerIcons.speakerphone,
                iconColor: const Color(0xFF10B981),
                iconBg:
                    isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                title: 'Banner Promotion',
                subtitle: 'Display banner on top of patient home app',
              ),
              const SizedBox(height: 32),

              // Bottom Continue Button (Orange)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  child: Text(
                    'Continue to Banner Setup →',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhyPromoteCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String id,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedOption == id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _selectedOption = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2E1065) : const Color(0xFFF5F3FF))
              : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C3AED)
                : AppColors.borderOf(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : AppColors.textSecondaryOf(context),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TARGET CITIES CARD & MODAL PICKER
  // ---------------------------------------------------------------------------
  Widget _buildTargetCitiesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : AppColors.borderOf(context),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Target Cities (${_selectedCities.length})',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showCityPickerModal,
                icon: Icon(
                  Icons.edit_location_alt_outlined,
                  size: 14,
                  color: isDark
                      ? const Color(0xFFC4B5FD)
                      : const Color(0xFF6D28D9),
                ),
                label: Text(
                  'Add / Modify',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFC4B5FD)
                        : const Color(0xFF6D28D9),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? const Color(0xFFC4B5FD)
                      : const Color(0xFF6D28D9),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF8B5CF6)
                        : const Color(0xFFC4B5FD),
                    width: 1.3,
                  ),
                  backgroundColor: isDark
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.25)
                      : const Color(0xFF7C3AED).withValues(alpha: 0.08),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // City Chips Wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedCities.map((city) {
              final rate = IndianCities.dailyRate(city);
              final isMetro = IndianCities.isMetro(city);
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 5, 7, 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1B4B)
                      : const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF8B5CF6)
                        : const Color(0xFFC4B5FD),
                    width: 1.3,
                  ),
                  boxShadow: isDark
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF7C3AED).withValues(alpha: 0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      city,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isMetro
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFF059669),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '₹$rate/d',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    InkWell(
                      onTap: () {
                        if (_selectedCities.length > 1) {
                          setState(() => _selectedCities.remove(city));
                        } else {
                          AppToast.info(context,
                              'At least one target city must be selected.');
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Divider(
              height: 1,
              color: isDark
                  ? const Color(0xFF374151)
                  : AppColors.borderOf(context)),
          const SizedBox(height: 10),

          // Bottom Combined Rate Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Combined Daily Rate:',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppColors.textSecondaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_selectedCities.length > 1) ...[
                      const SizedBox(height: 2),
                      Text(
                        _rateSumFormulaString,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: isDark
                              ? const Color(0xFFA78BFA)
                              : const Color(0xFF7C3AED),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹$_combinedDailyRate / day',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w900,
                  color: isDark
                      ? const Color(0xFFA78BFA)
                      : const Color(0xFF6B21A8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCityPickerModal() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tempSelected = Set<String>.from(_selectedCities);
    String selectedState = 'Maharashtra';
    String searchQuery = '';
    final searchController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allStates = [
              'Maharashtra',
              'All States (India)',
              ...IndianCities.byState.keys
                  .where((s) => s != 'Maharashtra')
                  .toList()
                ..sort()
            ];

            List<String> availableCities = [];
            if (selectedState == 'All States (India)') {
              availableCities = IndianCities.all;
            } else {
              availableCities = IndianCities.forState(selectedState);
            }

            if (searchQuery.trim().isNotEmpty) {
              final q = searchQuery.trim().toLowerCase();
              availableCities = availableCities
                  .where((c) => c.toLowerCase().contains(q))
                  .toList();
            }

            final isAllSelected = availableCities.isNotEmpty &&
                availableCities.every((c) => tempSelected.contains(c));

            final currentDailyRate = tempSelected.fold<int>(
                0, (sum, c) => sum + IndianCities.dailyRate(c));

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.borderOf(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header: Select Target Cities & Select All
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Target Cities',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            if (isAllSelected) {
                              tempSelected.removeAll(availableCities);
                            } else {
                              tempSelected.addAll(availableCities);
                            }
                          });
                        },
                        child: Text(
                          isAllSelected ? 'Deselect All' : 'Select All',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Filters: [India] pill + State Dropdown
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF7C3AED)
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'India',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1B4B).withValues(alpha: 0.5)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: AppColors.borderOf(context)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedState,
                              isExpanded: true,
                              dropdownColor: AppColors.surfaceOf(context),
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimaryOf(context),
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w600,
                              ),
                              items: allStates.map((st) {
                                return DropdownMenuItem<String>(
                                  value: st,
                                  child: Text(st),
                                );
                              }).toList(),
                              onChanged: (newSt) {
                                if (newSt != null) {
                                  setModalState(() => selectedState = newSt);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1B4B).withValues(alpha: 0.5)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: GoogleFonts.inter(
                          color: AppColors.textPrimaryOf(context),
                          fontSize: AppTypography.bodySmall),
                      decoration: InputDecoration(
                        hintText:
                            'Search city (e.g. Nagpur, Amravati, Akola)...',
                        hintStyle: GoogleFonts.inter(
                            color: AppColors.textSecondaryOf(context),
                            fontSize: AppTypography.bodySmall),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 20,
                            color: AppColors.textSecondaryOf(context)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (val) =>
                          setModalState(() => searchQuery = val),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Scrollable City List
                  Expanded(
                    child: availableCities.isEmpty
                        ? Center(
                            child: Text(
                              'No cities found matching "$searchQuery"',
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: availableCities.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1, color: AppColors.borderOf(context)),
                            itemBuilder: (context, idx) {
                              final city = availableCities[idx];
                              final stateName = IndianCities.stateForCity(city);
                              final isMetro = IndianCities.isMetro(city);
                              final rate = IndianCities.dailyRate(city);
                              final isChecked = tempSelected.contains(city);

                              return InkWell(
                                onTap: () {
                                  setModalState(() {
                                    if (isChecked) {
                                      tempSelected.remove(city);
                                    } else {
                                      tempSelected.add(city);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$city ($stateName)',
                                          style: GoogleFonts.inter(
                                            fontSize: AppTypography.bodyMedium,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimaryOf(
                                                context),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isMetro
                                              ? (isDark
                                                  ? const Color(0xFF3B0764)
                                                  : const Color(0xFFF3E8FF))
                                              : (isDark
                                                  ? const Color(0xFF064E3B)
                                                  : const Color(0xFFD1FAE5)),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isMetro
                                              ? 'Metro ₹$rate/d'
                                              : 'Standard ₹$rate/d',
                                          style: GoogleFonts.inter(
                                            fontSize: AppTypography.labelSmall,
                                            fontWeight: FontWeight.w800,
                                            color: isMetro
                                                ? (isDark
                                                    ? const Color(0xFFA78BFA)
                                                    : const Color(0xFF6B21A8))
                                                : (isDark
                                                    ? const Color(0xFF34D399)
                                                    : const Color(0xFF065F46)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Checkbox(
                                        value: isChecked,
                                        activeColor: const Color(0xFF7C3AED),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        onChanged: (val) {
                                          setModalState(() {
                                            if (val == true) {
                                              tempSelected.add(city);
                                            } else {
                                              tempSelected.remove(city);
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Bottom Apply Selection Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        if (tempSelected.isEmpty) {
                          AppToast.info(context,
                              'Please select at least one target city.');
                          return;
                        }
                        setState(() {
                          _selectedCities = tempSelected;
                        });
                        Navigator.pop(sheetContext);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: Text(
                        'Apply Selection (${tempSelected.length} Cities • ₹$currentDailyRate/day)',
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyLarge,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFullScreenBannerPreview() {
    final previewTitle = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Promote Your Medical Practice';
    final previewCta = _selectedCtaLabel;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(ctx),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Live Patient Carousel Preview',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(ctx),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0F9B7E),
                        Color(0xFF0D9488),
                        Color(0xFF14B8A6)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (_selectedImageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            _selectedImageBytes!,
                            width: double.infinity,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star,
                                            size: 11, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          'FEATURED PROMOTION',
                                          style: GoogleFonts.inter(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    previewTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.headlineSmall,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          previewCta,
                                          style: GoogleFonts.inter(
                                            fontSize: AppTypography.labelMedium,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF0F766E),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right,
                                            size: 14, color: Color(0xFF0F766E)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.campaign_outlined,
                                  color: Colors.white, size: 28),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerPreviewHeader(bool isDark) {
    final previewTitle = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Promote Your Medical Practice';
    final previewCta = _selectedCtaLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Preview of Banner Promotion',
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 12),

        // Live Banner Box
        Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F9B7E), Color(0xFF0D9488), Color(0xFF14B8A6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (_selectedImageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _selectedImageBytes!,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // FEATURED PROMOTION gold pill badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 11, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'FEATURED PROMOTION',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            previewTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  previewCta,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F766E),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    size: 14, color: Color(0xFF0F766E)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.campaign_outlined,
                          color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2 info columns: Top Banner Position & Banner Specifications
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top Banner Position',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your banner will be displayed prominently at the top of the patient portal home screen carousel.',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Banner Specifications',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '• Recommended Size: 1200 × 400 px\n• Formats: JPG, PNG\n• Max Size: Up to 2MB',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // See Full Screen Live Preview button
        OutlinedButton(
          onPressed: _showFullScreenBannerPreview,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0284C7),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(
            'See Full Screen Live Preview',
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0284C7),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2: Banner Image & Links Details (Dynamic Dark / Light Mode)
  // ---------------------------------------------------------------------------
  Widget _buildStep2BannerSetup(bool isDark) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppColors.surfaceOf(context),
      hintStyle: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Preview of Banner Promotion (Screenshot 1)
                _buildBannerPreviewHeader(isDark),
                const SizedBox(height: 24),

                // Target Cities Selection Card (Screenshot 1 & 2)
                _buildTargetCitiesCard(isDark),
                const SizedBox(height: 24),

                // Banner Image Upload Box (Dashed area)
                Text(
                  'Banner image',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Upload attractive banner to promote your organization',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickAdImage,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 130,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.borderOf(context), width: 1.5),
                    ),
                    child: _selectedImageBytes != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(_selectedImageBytes!,
                                    fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('Change Image',
                                      style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: AppTypography.labelSmall)),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload_outlined,
                                  size: 36,
                                  color: AppColors.textSecondaryOf(context)),
                              const SizedBox(height: 6),
                              Text(
                                'Upload banner image',
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              Text(
                                'Select banner image from your device JPG, PNG up to 2 mb',
                                style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context)),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Headline Input
                Text(
                  'Ad Headline (Title)',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  maxLength: 50,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimaryOf(context)),
                  decoration: inputDecoration.copyWith(
                    hintText: 'e.g., Special 20% Off Cardiology Screening',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a headline'
                      : null,
                ),
                const SizedBox(height: 14),

                // Subtitle Input
                Text(
                  'Ad Description',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descController,
                  maxLength: 100,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimaryOf(context)),
                  decoration: inputDecoration.copyWith(
                    hintText:
                        'e.g., Book expert consultation with top specialists today.',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a description'
                      : null,
                ),
                const SizedBox(height: 14),

                // Link Input (Optional)
                Text(
                  'Link (Optional)',
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _linkController,
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimaryOf(context)),
                  decoration: inputDecoration.copyWith(
                    hintText: 'Paste link (optional website or profile link)',
                  ),
                ),
                const SizedBox(height: 28),

                // Next CTA Button (Orange)
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      if (_selectedImageBytes == null) {
                        AppToast.info(context, 'Please upload a banner image.');
                        return;
                      }
                      setState(() => _currentStep = 2);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    child: Text(
                      'Choose Campaign Plan →',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 3: Banner Campaign Plan Carousel & Payment (Dynamic Dark / Light Mode)
  // ---------------------------------------------------------------------------
  Widget _buildCampaignPlanCard(
      Map<String, dynamic> plan, int index, bool isDark) {
    final isSelected = _selectedPlanIndex == index;
    final planDays = plan['days'] as int;
    final calculatedPrice = _calculatePlanPrice(planDays);
    final formulaSubtitle = _selectedCities.length == 1
        ? '(₹${IndianCities.dailyRate(_selectedCities.first)}) × $planDays days = ₹$calculatedPrice'
        : '($_rateSumPillFormulaString) × $planDays days = ₹$calculatedPrice';

    final features = [
      _selectedCities.length == 1
          ? 'Banner visible in ${_selectedCities.first} for $planDays day${planDays == 1 ? '' : 's'}'
          : 'Banner visible across ${_selectedCities.length} target cities ($_citiesSnippet) for $planDays days',
      'Top position in patient home carousel',
      'Direct CTA tap redirection',
      if (planDays >= 30)
        'Dedicated campaign manager'
      else
        'Real-time campaign analytics',
    ];

    return InkWell(
      onTap: () {
        setState(() => _selectedPlanIndex = index);
        if (_planPageController.hasClients) {
          _planPageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin:
                const EdgeInsets.only(top: 14, right: 8, left: 8, bottom: 4),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? const Color(0xFF1E1B4B) : Colors.white)
                  : AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF7C3AED)
                    : AppColors.borderOf(context),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan['title'],
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      '₹$calculatedPrice',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineLarge,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? const Color(0xFFA78BFA)
                            : const Color(0xFF6B21A8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  formulaSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  plan['subtitle'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                Divider(
                    height: 1,
                    color: isDark
                        ? const Color(0xFF374151)
                        : AppColors.borderOf(context)),
                const SizedBox(height: 10),

                // Features List with Purple Checks
                ...List.generate(
                  features.length,
                  (fIdx) {
                    final feature = features[fIdx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3B0764)
                                  : const Color(0xFFF3E8FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check,
                                size: 13, color: Color(0xFF7C3AED)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              feature,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  plan['badge'],
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3PlanSelection(bool isDark) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final selectedPlan = _campaignPlans[_selectedPlanIndex];
    final selectedPlanDays = selectedPlan['days'] as int;
    final selectedPlanCalculatedPrice = _calculatePlanPrice(selectedPlanDays);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Banner Campaign Plan',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineMedium,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),

              // Top Target Cities Card (Matches Screenshot 3)
              _buildTargetCitiesCard(isDark),
              const SizedBox(height: 20),

              // Carousel of Plans with peeking next card (height 290 prevents overflow)
              SizedBox(
                height: 290,
                child: PageView.builder(
                  controller: _planPageController,
                  itemCount: _campaignPlans.length,
                  onPageChanged: (idx) =>
                      setState(() => _selectedPlanIndex = idx),
                  itemBuilder: (context, index) => _buildCampaignPlanCard(
                      _campaignPlans[index], index, isDark),
                ),
              ),
              const SizedBox(height: 14),

              // Carousel Navigation Control (Previous / Dots / Next)vigation Control (Previous / Dots / Next)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _selectedPlanIndex > 0
                        ? () => _planPageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut)
                        : null,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Previous'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimaryOf(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),

                  // Page Indicator Dots (Teal active dot)
                  Row(
                    children: List.generate(
                      _campaignPlans.length,
                      (dIdx) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _selectedPlanIndex == dIdx ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _selectedPlanIndex == dIdx
                              ? const Color(0xFF0D9488)
                              : (isDark
                                  ? const Color(0xFF475569)
                                  : const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  TextButton.icon(
                    onPressed: _selectedPlanIndex < _campaignPlans.length - 1
                        ? () => _planPageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut)
                        : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Next'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textPrimaryOf(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Bottom Orange Payment Gateway Button (Matches Screenshot 3)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitAndPay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                  child: Text(
                    'Buy Subscription & Launch (₹$selectedPlanCalculatedPrice)',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
