import '../../core/firebase/firestore_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/constants/ambulance_icons.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/firebase/firestore_paths.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/location/location_match.dart';
import '../../core/notifications/ambulance_notification_emitter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/external_launcher.dart';
import '../../core/constants/country_phone_codes.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/phone_number_field.dart';
import '../patient/profile/data/patient_profile_mock.dart';
import 'data/ambulance_booking_sync.dart';
import 'data/ambulance_store.dart';
import 'models/ambulance_models.dart';
import '../doctor/profile/sections/doctor_add_ambulance_screen.dart';
import 'widgets/ambulance_rating_dialog.dart';
import '../../core/theme/app_typography.dart';

class AmbulanceBookingScreen extends StatefulWidget {
  const AmbulanceBookingScreen({
    super.key,
    required this.bookedByRole,
    this.initialPatientName,
    this.initialContactPhone,
    this.embeddedInShell = false,
  });

  final AmbulanceBookedByRole bookedByRole;
  final String? initialPatientName;
  final String? initialContactPhone;
  final bool embeddedInShell;

  @override
  State<AmbulanceBookingScreen> createState() => _AmbulanceBookingScreenState();
}

class _AmbulanceBookingScreenState extends State<AmbulanceBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _patientNameController = TextEditingController();
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  final _phoneController = TextEditingController();
  final _store = AmbulanceStore.instance;
  final _repository = FirestoreService.instance.ambulance;
  final _sync = AmbulanceBookingSync.instance;

  bool _submitting = false;
  String? _activeBookingId;
  Timer? _countdownTimer;
  int _remainingSeconds = 300;
  AmbulanceType? _selectedType;
  String _phoneDialCode = CountryPhoneCodes.defaultDialCode;

  bool get _isPatient => widget.bookedByRole == AmbulanceBookedByRole.patient;

  void _applyPhone(String? raw) {
    final parsed = FormValidators.parsePhone(raw);
    _phoneDialCode = parsed.dialCode;
    _phoneController.text = parsed.localNumber;
  }

  @override
  void initState() {
    super.initState();
    if (_isPatient) {
      final name = PatientProfileMock.profile.name;
      if (name.isNotEmpty) _patientNameController.text = name;
      _applyPhone(PatientProfileMock.profile.mobile);
    } else {
      final name = widget.initialPatientName?.trim();
      if (name != null && name.isNotEmpty) {
        _patientNameController.text = name;
      }
      _applyPhone(widget.initialContactPhone);
    }
    _restoreActiveBooking();
    _store.addListener(_onStoreChanged);
    final bookerId = AmbulanceNotificationEmitter.bookerId(widget.bookedByRole);
    if (bookerId.isNotEmpty) {
      _sync.watchPatientHistory(bookerId);
    }
  }

  AmbulanceBooking? _findRestorableBooking(String patientId) {
    final mine = _store.bookings
        .where(
          (b) =>
              b.bookedById == patientId &&
              b.bookedByRole == widget.bookedByRole,
        )
        .toList();

    final inProgress = mine.where((b) => b.isPending || b.isAccepted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (inProgress.isNotEmpty) return inProgress.first;

    final unratedDone = mine
        .where((b) => b.isCompleted && !b.isRated && !b.isRatingSkipped)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (unratedDone.isNotEmpty) return unratedDone.first;

    return null;
  }

  void _restoreActiveBooking() {
    final patientId =
        AmbulanceNotificationEmitter.bookerId(widget.bookedByRole);
    if (patientId.isEmpty) return;

    final existing = _findRestorableBooking(patientId);
    if (existing != null && !existing.isCancelled) {
      setState(() => _activeBookingId = existing.id);
      _sync.watchPatientBroadcast(existing.id);
      if (existing.isPending) _startCountdownIfNeeded();
    }
  }

  void _onStoreChanged() {
    final id = _activeBookingId;
    if (id != null) {
      final booking = _store.findBooking(id);
      if (booking != null && booking.isCancelled) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        _sync.stopPatientWatch();
        if (mounted) setState(() => _activeBookingId = null);
        return;
      }
    }

    final active = _activeBooking;
    if (active == null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }

    if (active.isPending) {
      if (_countdownTimer == null) _startCountdownIfNeeded();
    } else {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  void _startCountdownIfNeeded() {
    _countdownTimer?.cancel();
    final active = _activeBooking;
    if (active == null || !active.isPending) return;

    final elapsed = DateTime.now().difference(active.createdAt).inSeconds;
    setState(() {
      _remainingSeconds = (300 - elapsed).clamp(0, 300);
    });

    if (_remainingSeconds <= 0) {
      _handleTimeout();
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = _activeBooking;
      if (current == null || !current.isPending) {
        timer.cancel();
        _countdownTimer = null;
        return;
      }
      final elapsed = DateTime.now().difference(current.createdAt).inSeconds;
      setState(() {
        _remainingSeconds = (300 - elapsed).clamp(0, 300);
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _handleTimeout();
      }
    });
  }

  Future<void> _handleTimeout() async {
    final active = _activeBooking;
    if (active != null && active.isPending) {
      await _repository.cancelBroadcast(active.id);
    }
    _sync.stopPatientWatch();
    if (!mounted) return;
    setState(() => _activeBookingId = null);
    // Removed snackbar
  }

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _countdownTimer?.cancel();
    _sync.stopPatientWatch();
    _sync.stopPatientHistoryWatch();
    _patientNameController.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _validateContactInfo() {
    if (_isPatient) {
      final digits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length != 10) {
        // Removed snackbar
        return false;
      }
      if (_patientNameController.text.trim().isEmpty) {
        _patientNameController.text = PatientProfileMock.profile.name.isNotEmpty
            ? PatientProfileMock.profile.name
            : 'Patient';
      }
    }
    return true;
  }

  Future<String?> _getUserCity(String bookerId) async {
    if (_isPatient) {
      final city = PatientProfileMock.profileAddress.city.trim();
      if (city.isNotEmpty) return city;
      return PatientProfileMock.profileCity.trim().isEmpty
          ? null
          : PatientProfileMock.profileCity.trim();
    } else if (widget.bookedByRole == AmbulanceBookedByRole.doctor) {
      if (!FirebaseBootstrap.isReady) return null;
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(bookerId)
            .get();
        if (doc.exists && doc.data() != null) {
          return readNestedAddressCity(doc.data()!);
        }
      } catch (_) {}
    }
    return null;
  }

  void _showBookingError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _bookAmbulance() async {
    if (_submitting || _activeBooking != null) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_validateContactInfo()) return;

    final pickupLocation = _pickupController.text.trim();
    setState(() => _submitting = true);

    final patientId =
        AmbulanceNotificationEmitter.bookerId(widget.bookedByRole);
    if (patientId.isEmpty) {
      setState(() => _submitting = false);
      _showBookingError(
        widget.bookedByRole == AmbulanceBookedByRole.doctor
            ? 'Your doctor session is missing. Please sign in again and retry.'
            : 'Your patient session is missing. Please sign in again and retry.',
      );
      return;
    }

    final userCity = await _getUserCity(patientId);
    final requestCity = (userCity?.trim().isNotEmpty == true)
        ? userCity!.trim()
        : pickupLocation.trim();

    final onlineDrivers =
        await _repository.fetchAllOnlineDrivers(userCity: requestCity);
    if (!mounted) return;

    if (onlineDrivers.isEmpty) {
      setState(() => _submitting = false);
      _showBookingError(
        'No ambulance drivers are online in your area right now. '
        'Please try again in a few minutes or call emergency services if this is urgent.',
      );
      return;
    }

    String? broadcastId;
    try {
      broadcastId = await _repository.broadcastAmbulanceRequest(
        patientId: patientId,
        pickupLocation: pickupLocation,
        dropLocation: _dropController.text.trim(),
        patientName: _patientNameController.text.trim(),
        contactPhone: FormValidators.formatFullPhone(
          _phoneDialCode,
          _phoneController.text.trim(),
        ),
        bookedByRole: widget.bookedByRole.name,
        requestedType: _selectedType,
        userCity: requestCity,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showBookingError(
        'Could not send your ambulance request. Check your connection and try again.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (broadcastId != null) {
        _activeBookingId = broadcastId;
        _sync.watchPatientBroadcast(broadcastId);
        _startCountdownIfNeeded();
      }
    });

    if (broadcastId == null) {
      _showBookingError(
        'Could not create your ambulance request. Please try again.',
      );
      return;
    }
  }

  AmbulanceBooking? get _activeBooking {
    final id = _activeBookingId;
    if (id == null) return null;
    final booking = _store.findBooking(id);
    if (booking == null || booking.isCancelled) return null;
    return booking;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final active = _activeBooking;
        final canInteract = active == null && !_submitting;
        final patientId =
            AmbulanceNotificationEmitter.bookerId(widget.bookedByRole);
        return Scaffold(
          backgroundColor: AppColors.cardBgOf(context),
          appBar: AppBar(
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: !widget.embeddedInShell,
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AmbulanceIcons.gradient,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AmbulanceIcons.gradient.last
                            .withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(child: AmbulancePlusSign(size: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Ambulance',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: AppTypography.headlineSmall,
                        ),
                      ),
                      Text(
                        'Fast help when you need it',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (patientId.isNotEmpty)
                _AmbulanceHistoryButton(
                  patientId: patientId,
                  role: widget.bookedByRole,
                  activeBookingId: _activeBookingId,
                  onTap: () => _openAmbulanceHistory(
                      context, patientId, widget.bookedByRole),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final cardMaxWidth = ResponsiveLayout.isCompact(context)
                  ? constraints.maxWidth
                  : ResponsiveLayout.isMedium(context)
                      ? 720.0
                      : 820.0;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20,
                    24 + bottomInset + (widget.embeddedInShell ? 90 : 0)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EmergencyInfoStrip(isPatient: _isPatient),
                        const SizedBox(height: 20),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceOf(context),
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppColors.borderOf(context)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimaryOf(context)
                                    .withValues(alpha: 0.04),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _AmbulanceTypeDropdown(
                                    value: _selectedType,
                                    enabled: canInteract,
                                    onChanged: (v) =>
                                        setState(() => _selectedType = v),
                                  ),
                                  if (active != null) ...[
                                    const SizedBox(height: 20),
                                    _BookingStatusCard(
                                      booking: active,
                                      embedded: true,
                                      remainingTimeLabel: active.isPending
                                          ? _formatTime(_remainingSeconds)
                                          : null,
                                      onDismiss: () {
                                        _sync.stopPatientWatch();
                                        setState(() => _activeBookingId = null);
                                      },
                                      onRate: active.isCompleted &&
                                              !active.isRated &&
                                              !active.isRatingSkipped
                                          ? () => _rateTrip(context, active)
                                          : null,
                                      onCancel: active.isPending ||
                                              active.isAccepted
                                          ? () async {
                                              final messenger =
                                                  ScaffoldMessenger.of(context);
                                              final ok = await _repository
                                                  .cancelBroadcast(
                                                active.id,
                                              );
                                              if (!mounted) return;
                                              if (ok) {
                                                _sync.stopPatientWatch();
                                                setState(() =>
                                                    _activeBookingId = null);
                                                messenger.showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Request cancelled'),
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                  ),
                                                );
                                              } else {
                                                final message = _repository
                                                        .lastCancelFailureUserMessage ??
                                                    'Could not cancel this request. Please try again.';
                                                messenger.showSnackBar(
                                                  SnackBar(
                                                    content: Text(message),
                                                    backgroundColor:
                                                        const Color(0xFFDC2626),
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  if (!_isPatient) ...[
                                    TextFormField(
                                      controller: _patientNameController,
                                      enabled: canInteract,
                                      decoration: _fieldDecoration(
                                          'Patient name', Icons.person_outline),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? 'Enter patient name'
                                              : null,
                                    ),
                                    const SizedBox(height: 12),
                                    PhoneNumberField(
                                      controller: _phoneController,
                                      initialDialCode: _phoneDialCode,
                                      onDialCodeChanged: (code) =>
                                          _phoneDialCode = code,
                                      enabled: canInteract,
                                      decoration: _fieldDecoration(
                                        'Contact phone',
                                        Icons.phone_outlined,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  _AddressRouteInputs(
                                    pickupController: _pickupController,
                                    dropController: _dropController,
                                    enabled: canInteract,
                                  ),
                                  const SizedBox(height: 22),
                                  if (active == null) ...[
                                    FilledButton(
                                      onPressed: canInteract && !_submitting
                                          ? _bookAmbulance
                                          : null,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFDC2626),
                                        disabledBackgroundColor:
                                            const Color(0xFFDC2626)
                                                .withValues(alpha: 0.35),
                                        foregroundColor: AppColors.white,
                                        minimumSize:
                                            const Size(double.infinity, 54),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: _submitting
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: AppColors.surfaceOf(
                                                    context),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const AmbulancePlusSign(
                                                    size: 22),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Book Ambulance',
                                                  style: GoogleFonts.inter(
                                                    fontSize: AppTypography
                                                        .headlineSmall,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Request goes to all online drivers. '
                                      'You will wait up to 5 minutes for acceptance.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        color:
                                            AppColors.textSecondaryOf(context),
                                        height: 1.45,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    if (!_isPatient) ...[
                                      const SizedBox(height: 18),
                                      OutlinedButton(
                                        onPressed: canInteract
                                            ? () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const DoctorAddAmbulanceScreen(),
                                                  ),
                                                );
                                              }
                                            : null,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFFDC2626),
                                          side: const BorderSide(
                                              color: Color(0xFFDC2626)),
                                          minimumSize:
                                              const Size(double.infinity, 48),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const AmbulancePlusSign(
                                              size: 18,
                                              color: Color(0xFFDC2626),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Add Ambulance',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Register a new ambulance service and send the driver an invite link.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: AppTypography.labelSmall,
                                          color: AppColors.textSecondaryOf(
                                              context),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openAmbulanceHistory(
      BuildContext context, String patientId, AmbulanceBookedByRole role) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: _AmbulanceHistoryDialog(
            patientId: patientId,
            role: role,
            activeBookingId: _activeBookingId,
          ),
        );
      },
    );
  }

  Future<void> _rateTrip(BuildContext context, AmbulanceBooking booking) async {
    final rated = await showAmbulanceRatingDialog(
      context: context,
      bookingId: booking.id,
      ambulanceName: booking.acceptedAmbulanceName ?? 'Ambulance',
    );
    if (!context.mounted || !rated) return;
    // Removed snackbar
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(
        fontSize: AppTypography.bodySmall,
        color: AppColors.textSecondaryOf(context),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon:
          Icon(icon, size: 19, color: AppColors.textSecondaryOf(context)),
      filled: true,
      fillColor: AppColors.cardBgOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _EmergencyInfoStrip extends StatelessWidget {
  const _EmergencyInfoStrip({required this.isPatient});

  final bool isPatient;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF261515) : const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF4C1D1D) : const Color(0xFFFEE2E2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626)
                    .withValues(alpha: isDark ? 0.25 : 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: AmbulancePlusSign(
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPatient
                    ? 'Share pickup and destination. Nearby online drivers get notified instantly.'
                    : 'Book for your patient. All online ambulance drivers receive the request.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: isDark
                      ? AppColors.darkTextPrimary.withValues(alpha: 0.88)
                      : const Color(0xFF475569),
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbulanceHistoryButton extends StatelessWidget {
  const _AmbulanceHistoryButton({
    required this.patientId,
    required this.role,
    required this.onTap,
    this.activeBookingId,
  });

  final String patientId;
  final AmbulanceBookedByRole role;
  final String? activeBookingId;
  final VoidCallback onTap;

  int _tripCount() {
    return AmbulanceStore.instance.bookings
        .where(
          (b) =>
              b.bookedById == patientId &&
              b.bookedByRole == role &&
              (b.isCompleted || b.isCancelled) &&
              b.id != activeBookingId,
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final count = _tripCount();

    return IconButton(
      onPressed: onTap,
      tooltip: 'Ambulance History',
      style: IconButton.styleFrom(
        backgroundColor: AppColors.cardBgOf(context),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.history, color: Color(0xFFDC2626)),
          if (count > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.surfaceOf(context),
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbulanceHistoryDialog extends StatelessWidget {
  const _AmbulanceHistoryDialog({
    required this.patientId,
    required this.role,
    this.activeBookingId,
  });

  final String patientId;
  final AmbulanceBookedByRole role;
  final String? activeBookingId;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final cardHeight = (screen.height * 0.72).clamp(320.0, 560.0);
    final cardWidth = screen.width > 560 ? 520.0 : screen.width - 40;

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimaryOf(context).withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListenableBuilder(
            listenable: AmbulanceStore.instance,
            builder: (context, _) {
              final trips = AmbulanceStore.instance.bookings
                  .where(
                    (b) =>
                        b.bookedById == patientId &&
                        b.bookedByRole == role &&
                        (b.isCompleted || b.isCancelled) &&
                        b.id != activeBookingId,
                  )
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: AmbulanceIcons.gradient),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              const Center(child: AmbulancePlusSign(size: 18)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ambulance History',
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.headlineSmall,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                trips.isEmpty
                                    ? 'No past trips yet'
                                    : '${trips.length} past trip${trips.length == 1 ? '' : 's'}',
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close_rounded),
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppColors.borderOf(context)),
                  Expanded(
                    child: trips.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626)
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: AmbulancePlusSign(
                                        size: 24,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Your completed trips will show here.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodyMedium,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                            child: Column(
                              children: trips
                                  .map((trip) =>
                                      _PatientHistoryTripCard(trip: trip))
                                  .toList(),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PatientHistoryTripCard extends StatelessWidget {
  const _PatientHistoryTripCard({required this.trip});

  final AmbulanceBooking trip;

  Future<void> _rate(BuildContext context) async {
    final rated = await showAmbulanceRatingDialog(
      context: context,
      bookingId: trip.id,
      ambulanceName: trip.acceptedAmbulanceName ?? 'Ambulance',
    );
    if (!context.mounted || !rated) return;
    // Removed snackbar
  }

  @override
  Widget build(BuildContext context) {
    final isDone = trip.isCompleted;
    final statusColor =
        isDone ? const Color(0xFF0D9488) : const Color(0xFFDC2626);
    final statusLabel = isDone ? 'Completed' : 'Cancelled';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trip.patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (trip.notes != null && trip.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              trip.notes!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.access_time,
                  size: 13,
                  color: AppColors.textSecondaryOf(context)
                      .withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  DateFormat('dd MMM yyyy · hh:mm a').format(trip.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      color: AppColors.textSecondaryOf(context)),
                ),
              ),
            ],
          ),
          if (trip.acceptedAmbulanceName != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_hospital_outlined,
                          size: 14, color: AppColors.textSecondaryOf(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trip.acceptedAmbulanceName!,
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (trip.acceptedDriverName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Driver: ${trip.acceptedDriverName!} • ${trip.acceptedVehicleNumber ?? ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                  ],
                  if (trip.acceptedDriverPhone != null) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 12,
                            color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 4),
                        Text(
                          trip.acceptedDriverPhone!,
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.labelSmall,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (isDone) ...[
            const SizedBox(height: 10),
            if (trip.isRated)
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < trip.rating!
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${trip.rating}/5',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  if (trip.review != null && trip.review!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"${trip.review}"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _rate(context),
                  icon: const Icon(Icons.star_rounded, size: 16),
                  label: Text(
                    'Rate & Review',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _ambulanceTypeDefinition(AmbulanceType? type) {
  switch (type) {
    case null:
      return 'Sabse fast match ke liye. Nearest available ambulance assign hogi.';
    case AmbulanceType.bls:
      return 'Trained EMTs ke saath basic care: oxygen, CPR, bleeding control, splinting. Stable ya non-critical patients ke liye.';
    case AmbulanceType.als:
      return 'Paramedics ke saath advanced care: cardiac monitor/ECG, defibrillator, IV medicines, airway management. Critical cases (heart attack, stroke, serious injury) ke liye.';
    case AmbulanceType.icu:
      return 'Ventilator aur ICU equipment ke saath critical care team. Severe life support ya hospital ICU transfer ke liye.';
    case AmbulanceType.patientTransport:
      return 'Non-emergency travel: wheelchair/stretcher support, routine checkup ya hospital discharge ke liye. Emergency care ke liye nahi.';
  }
}

class _AmbulanceTypeDropdown extends StatelessWidget {
  const _AmbulanceTypeDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AmbulanceType? value;
  final bool enabled;
  final ValueChanged<AmbulanceType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final options = <(AmbulanceType?, String, IconData, Color)>[
      (
        null,
        'All Types',
        Icons.notifications_active_outlined,
        const Color(0xFF6366F1)
      ),
      (
        AmbulanceType.bls,
        'BLS',
        Icons.monitor_heart_outlined,
        const Color(0xFF16A34A)
      ),
      (
        AmbulanceType.als,
        'ALS',
        Icons.medication_outlined,
        const Color(0xFF0284C7)
      ),
      (
        AmbulanceType.icu,
        'ICU',
        Icons.emergency_outlined,
        const Color(0xFFDC2626)
      ),
      (
        AmbulanceType.patientTransport,
        'Transport',
        Icons.accessible_outlined,
        const Color(0xFFCA8A04)
      ),
    ];

    final unselectedBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.5)
        : const Color(0xFFF8FAFC);
    final unselectedBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final unselectedText = isDark
        ? AppColors.darkTextPrimary.withValues(alpha: 0.85)
        : const Color(0xFF334155);
    final unselectedIcon =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ambulance type',
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Optional — leave on All Types for fastest match',
          style: GoogleFonts.inter(
            fontSize: AppTypography.labelSmall,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((opt) {
            final (type, label, icon, color) = opt;
            final selected = value == type;
            final activeTextColor = isDark
                ? Colors.white
                : (color == const Color(0xFFCA8A04)
                    ? const Color(0xFF854D0E)
                    : color);

            return InkWell(
              onTap: enabled ? () => onChanged(type) : null,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: isDark ? 0.22 : 0.10)
                      : unselectedBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? color : unselectedBorder,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: selected ? color : unselectedIcon,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? activeTextColor : unselectedText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: Container(
            key: ValueKey(value),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: isDark
                        ? AppColors.darkTextSecondary.withValues(alpha: 0.8)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                Expanded(
                  child: Text(
                    _ambulanceTypeDefinition(value),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressRouteInputs extends StatefulWidget {
  const _AddressRouteInputs({
    required this.pickupController,
    required this.dropController,
    required this.enabled,
  });

  final TextEditingController pickupController;
  final TextEditingController dropController;
  final bool enabled;

  @override
  State<_AddressRouteInputs> createState() => _AddressRouteInputsState();
}

class _AddressRouteInputsState extends State<_AddressRouteInputs> {
  bool _fetchingPickup = false;
  bool _showPickupLocationError = false;

  Future<void> _openDeviceLocationSettings() async {
    if (kIsWeb) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    await Geolocator.openAppSettings();
  }

  Future<String?> _resolveAddressFromPosition(Position pos) async {
    String? resolvedAddress;

    try {
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final parts = [
          pm.street,
          pm.subLocality,
          pm.locality ?? pm.subAdministrativeArea,
          pm.administrativeArea,
          pm.postalCode,
        ].where((s) => s != null && s.trim().isNotEmpty).toSet().toList();
        if (parts.isNotEmpty) {
          resolvedAddress = parts.join(', ');
        }
      }
    } catch (_) {}

    if (resolvedAddress == null || resolvedAddress.trim().isEmpty) {
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'lat': '${pos.latitude}',
          'lon': '${pos.longitude}',
          'format': 'json',
          'addressdetails': '1',
        });
        final response = await http.get(
          uri,
          headers: const {'User-Agent': 'DoctorNect/1.0 (healthcare-app)'},
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final address = payload['address'] as Map<String, dynamic>?;
          if (address != null) {
            final road = address['road']?.toString();
            final sub =
                (address['suburb'] ?? address['neighbourhood'])?.toString();
            final city =
                (address['city'] ?? address['town'] ?? address['village'])
                    ?.toString();
            final parts = [
              if (road != null && road.isNotEmpty) road,
              if (sub != null && sub.isNotEmpty) sub,
              if (city != null && city.isNotEmpty) city,
            ];
            resolvedAddress = parts.isNotEmpty
                ? parts.join(', ')
                : (payload['display_name'] as String?);
          }
        }
      } catch (_) {}
    }

    return resolvedAddress;
  }

  Future<void> _fetchPickupLocation() async {
    if (!widget.enabled) return;
    setState(() {
      _fetchingPickup = true;
      _showPickupLocationError = false;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _showPickupLocationError = true);
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final resolvedAddress = await _resolveAddressFromPosition(pos);

      if (!mounted) return;

      if (resolvedAddress != null && resolvedAddress.trim().isNotEmpty) {
        widget.pickupController.text = resolvedAddress.trim();
      } else {
        widget.pickupController.text =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
      setState(() => _showPickupLocationError = false);
    } catch (_) {
      if (mounted) {
        setState(() => _showPickupLocationError = true);
      }
    } finally {
      if (mounted) {
        setState(() => _fetchingPickup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          // Left column (Indicators)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 14),
            child: Column(
              children: [
                const SizedBox(height: 21),
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF16A34A), Color(0xFFDC2626)],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    border:
                        Border.all(color: const Color(0xFFDC2626), width: 2.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 21),
              ],
            ),
          ),
          // Right column (Text fields)
          Expanded(
            child: Column(
              children: [
                TextFormField(
                  controller: widget.pickupController,
                  enabled: widget.enabled,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) {
                    if (_showPickupLocationError) {
                      setState(() => _showPickupLocationError = false);
                    }
                  },
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Pickup location',
                    hintStyle: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      color: AppColors.textSecondaryOf(context),
                      fontWeight: FontWeight.w400,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Use current location',
                      icon: _fetchingPickup
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFDC2626)),
                            )
                          : const Icon(Icons.my_location,
                              size: 20, color: Color(0xFFDC2626)),
                      onPressed: widget.enabled && !_fetchingPickup
                          ? _fetchPickupLocation
                          : null,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceOf(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFDC2626), width: 1.5),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter pickup location'
                      : null,
                ),
                if (_showPickupLocationError) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_off_outlined,
                        size: 14,
                        color: AppColors.error.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            Text(
                              'Location access is needed to auto-fill pickup.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                              ),
                            ),
                            InkWell(
                              onTap: _openDeviceLocationSettings,
                              borderRadius: BorderRadius.circular(4),
                              child: Text(
                                'Open settings',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: widget.dropController,
                  enabled: widget.enabled,
                  textCapitalization: TextCapitalization.words,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Destination hospital or address',
                    hintStyle: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      color: AppColors.textSecondaryOf(context),
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceOf(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.borderOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFFDC2626), width: 1.5),
                    ),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter destination'
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingStatusCard extends StatefulWidget {
  const _BookingStatusCard({
    required this.booking,
    this.embedded = false,
    this.remainingTimeLabel,
    this.onDismiss,
    this.onRate,
    this.onCancel,
  });

  final AmbulanceBooking booking;
  final bool embedded;
  final String? remainingTimeLabel;
  final VoidCallback? onDismiss;
  final VoidCallback? onRate;
  final VoidCallback? onCancel;

  @override
  State<_BookingStatusCard> createState() => _BookingStatusCardState();
}

class _BookingStatusCardState extends State<_BookingStatusCard> {
  String? _serviceName;
  String? _driverName;
  String? _driverPhone;
  String? _vehicleNumber;
  String? _ambulanceType;
  bool _loadingDetails = false;
  int _rejectedCount = 0;
  int _totalNotified = 0;
  StreamSubscription<QuerySnapshot>? _rejectedSub;

  AmbulanceBooking get booking => widget.booking;

  @override
  void initState() {
    super.initState();
    _hydrateDriverDetails();
    _subscribeRejectedCount();
  }

  void _subscribeRejectedCount() {
    if (!FirebaseBootstrap.isReady) return;
    final broadcastId = booking.id;
    if (broadcastId.isEmpty) return;
    _rejectedSub?.cancel();
    _rejectedSub = FirebaseFirestore.instance
        .collection(FirestorePaths.ambulanceRequests)
        .where('broadcastId', isEqualTo: broadcastId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final total = snap.docs.length;
      final rejected = snap.docs
          .where((d) => (d.data()['status'] as String?) == 'rejected')
          .length;
      setState(() {
        _totalNotified = total;
        _rejectedCount = rejected;
      });
    });
  }

  @override
  void didUpdateWidget(_BookingStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.id != widget.booking.id ||
        oldWidget.booking.status != widget.booking.status ||
        oldWidget.booking.acceptedAmbulanceId !=
            widget.booking.acceptedAmbulanceId) {
      _hydrateDriverDetails();
      _subscribeRejectedCount();
    }
  }

  @override
  void dispose() {
    _rejectedSub?.cancel();
    super.dispose();
  }

  Future<void> _hydrateDriverDetails() async {
    _serviceName = booking.acceptedAmbulanceName;
    _driverName = booking.acceptedDriverName;
    _driverPhone = booking.acceptedDriverPhone;
    _vehicleNumber = booking.acceptedVehicleNumber;
    _ambulanceType = booking.acceptedAmbulanceType;

    if (!booking.isAccepted && !booking.isCompleted) return;

    final hasPhone = _driverPhone != null && _driverPhone!.trim().isNotEmpty;
    if (hasPhone) {
      if (mounted) setState(() {});
      return;
    }

    final driverId = booking.acceptedAmbulanceId;
    if (driverId == null || driverId.isEmpty) return;

    setState(() => _loadingDetails = true);
    final amb =
        await FirestoreService.instance.ambulance.fetchAmbulanceById(driverId);
    if (!mounted) return;
    setState(() {
      _loadingDetails = false;
      if (amb != null) {
        _serviceName = amb.serviceName;
        _driverName = amb.driverName;
        _driverPhone = amb.phone;
        _vehicleNumber = amb.vehicleNumber;
        _ambulanceType = amb.ambulanceTypeLabel;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = booking.status;

    Color color;
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case AmbulanceBookingStatus.pending:
        color = const Color(0xFFCA8A04);
        icon = Icons.hourglass_top;
        title = 'Waiting for acceptance';
        subtitle =
            'All online drivers were notified. First to accept gets your trip.';
        break;
      case AmbulanceBookingStatus.accepted:
        color = const Color(0xFF16A34A);
        icon = Icons.check_circle;
        title = 'Ambulance assigned';
        subtitle =
            '${booking.acceptedAmbulanceName ?? "Ambulance"} is on the way.';
        break;
      case AmbulanceBookingStatus.completed:
        color = const Color(0xFF0D9488);
        icon = Icons.stars_rounded;
        title = 'Trip Completed!';
        subtitle = 'Thank you for using our ambulance service.';
        break;
      case AmbulanceBookingStatus.cancelled:
        color = const Color(0xFFDC2626);
        icon = Icons.cancel;
        if (booking.rawStatus == 'rejected') {
          title = 'Cancelled by Ambulance';
          subtitle =
              'The assigned ambulance driver has cancelled this request.';
        } else {
          title = 'Request Cancelled';
          subtitle = 'Your ambulance request was cancelled.';
        }
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.embedded
            ? AppColors.surfaceOf(context)
            : AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTypography.bodyMedium,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (status == AmbulanceBookingStatus.completed &&
                  !booking.isRated &&
                  !booking.isRatingSkipped &&
                  widget.onDismiss != null)
                GestureDetector(
                  onTap: () {
                    FirestoreService.instance.ambulance
                        .rateBroadcast(broadcastId: booking.id, stars: -1);
                    widget.onDismiss?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondaryOf(context)
                          .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppColors.textSecondaryOf(context)),
                  ),
                ),
            ],
          ),
          if ((status == AmbulanceBookingStatus.accepted ||
                  status == AmbulanceBookingStatus.completed) &&
              (booking.acceptedAmbulanceId != null ||
                  _serviceName != null)) ...[
            const SizedBox(height: 14),
            _AcceptedDriverDetails(
              loading: _loadingDetails,
              serviceName:
                  _serviceName ?? booking.acceptedAmbulanceName ?? 'Ambulance',
              driverName: _driverName,
              driverPhone: _driverPhone,
              vehicleNumber: _vehicleNumber,
              ambulanceType: _ambulanceType,
            ),
          ],
          if (widget.remainingTimeLabel != null &&
              status == AmbulanceBookingStatus.pending) ...[
            const SizedBox(height: 12),
            // ── Rapido-style skipped drivers row ──────────────────────────
            if (_totalNotified > 0) ...[
              _SkippedDriversRow(
                total: _totalNotified,
                skipped: _rejectedCount,
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, color: color, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Time remaining: ${widget.remainingTimeLabel}',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if ((status == AmbulanceBookingStatus.pending ||
                  status == AmbulanceBookingStatus.accepted) &&
              widget.onCancel != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Request'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Color(0xFFDC2626),
                  side: BorderSide(color: Color(0xFFDC2626)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          if (status == AmbulanceBookingStatus.completed ||
              status == AmbulanceBookingStatus.cancelled) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == AmbulanceBookingStatus.completed &&
                    !booking.isRated &&
                    !booking.isRatingSkipped) ...[
                  FilledButton.icon(
                    onPressed: widget.onRate ??
                        () {
                          showAmbulanceRatingDialog(
                            context: context,
                            bookingId: booking.id,
                            ambulanceName:
                                booking.acceptedAmbulanceName ?? 'Ambulance',
                          );
                        },
                    icon: const Icon(Icons.star_rounded, size: 18),
                    label: Text(
                      'Rate Driver',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (status == AmbulanceBookingStatus.completed &&
                    booking.isRated) ...[
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Rated ${booking.rating}★',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
                if (status != AmbulanceBookingStatus.completed ||
                    booking.isRated ||
                    booking.isRatingSkipped) ...[
                  TextButton(
                    onPressed: widget.onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondaryOf(context),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AcceptedDriverDetails extends StatelessWidget {
  const _AcceptedDriverDetails({
    required this.loading,
    required this.serviceName,
    this.driverName,
    this.driverPhone,
    this.vehicleNumber,
    this.ambulanceType,
  });

  final bool loading;
  final String serviceName;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleNumber;
  final String? ambulanceType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned driver',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon: Icons.local_hospital_outlined,
                  label: 'Service',
                  value: serviceName,
                ),
                if (driverName != null && driverName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Driver',
                    value: driverName!,
                  ),
                ],
                if (ambulanceType != null &&
                    ambulanceType!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailRow(
                    icon: Icons.medical_services_outlined,
                    label: 'Type',
                    value: ambulanceType!,
                  ),
                ],
                if (vehicleNumber != null &&
                    vehicleNumber!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _DetailRow(
                    icon: Icons.directions_car_outlined,
                    label: 'Vehicle',
                    value: vehicleNumber!,
                  ),
                ],
                if (driverPhone != null && driverPhone!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => ExternalLauncher.callPhone(
                          driverPhone!.trim(),
                          context: context),
                      icon: const Icon(Icons.phone, size: 18),
                      label: Text(
                        'Call ${driverPhone!.trim()}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        minimumSize: const Size(double.infinity, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
        SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
              children: [
                TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DigitsOnlyFormatter extends TextInputFormatter {
  const DigitsOnlyFormatter({this.maxLength});

  final int? maxLength;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (maxLength != null && digits.length > maxLength!) {
      digits = digits.substring(0, maxLength!);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Rapido-style widget: shows how many drivers were notified and how many skipped.
class _SkippedDriversRow extends StatelessWidget {
  const _SkippedDriversRow({
    required this.total,
    required this.skipped,
  });

  final int total;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final accepted = total - skipped;
    final skipPercent = total > 0 ? skipped / total : 0.0;

    // Pick label & colors based on severity
    final String message;
    final Color barColor;
    if (skipped == 0) {
      message =
          '$total driver${total == 1 ? '' : 's'} notified — waiting for response';
      barColor = const Color(0xFF16A34A);
    } else if (accepted > 0) {
      message = '$skipped of $total driver${total == 1 ? '' : 's'} skipped';
      barColor = const Color(0xFFCA8A04);
    } else {
      message =
          '$skipped of $total driver${total == 1 ? '' : 's'} skipped your request';
      barColor = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_car_outlined, size: 14, color: barColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: skipped > 0 ? skipPercent : null,
                minHeight: 4,
                backgroundColor: barColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  skipped > 0 ? barColor : const Color(0xFF16A34A),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
