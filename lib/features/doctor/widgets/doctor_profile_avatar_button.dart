import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../profile/data/doctor_photo_local_store.dart';
import '../profile/data/doctor_profile_store.dart';
import '../profile/doctor_profile_screen.dart';

class DoctorProfileAvatarButton extends StatefulWidget {
  const DoctorProfileAvatarButton({super.key, this.radius = 20});

  final double radius;

  @override
  State<DoctorProfileAvatarButton> createState() =>
      _DoctorProfileAvatarButtonState();
}

class _DoctorProfileAvatarButtonState extends State<DoctorProfileAvatarButton> {
  Uint8List? _localPhotoBytes;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    DoctorProfileStore.instance.addListener(_onProfileChanged);
    unawaited(_loadLocalPhoto());
  }

  @override
  void dispose() {
    DoctorProfileStore.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    unawaited(_loadLocalPhoto());
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalPhoto() async {
    final doctorId = DoctorSession.activeDoctorId;
    if (doctorId.isEmpty) return;

    final bytes = await DoctorPhotoLocalStore.load(doctorId);
    if (!mounted || bytes == null || bytes.isEmpty) return;
    setState(() => _localPhotoBytes = bytes);
  }

  ImageProvider? _avatarImage(
      String? photoUrl, Uint8List? profileBytes, BuildContext context) {
    final doctorId = DoctorSession.activeDoctorId;
    final bytes = profileBytes ??
        _localPhotoBytes ??
        DoctorPhotoLocalStore.readCached(doctorId);
    if (bytes != null && bytes.isNotEmpty) {
      return MemoryImage(bytes);
    }
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      final cachePx =
          (widget.radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
      return ResizeImage(
        NetworkImage(photoUrl.trim()),
        width: cachePx,
        height: cachePx,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final profile = DoctorProfileStore.instance.profile;
    final name = DoctorProfileStore.displayName.isNotEmpty
        ? DoctorProfileStore.displayName
        : DoctorSession.loggedInDoctorName;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'D';
    final avatarImage =
        _avatarImage(profile.photoUrl, profile.photoBytes, context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DoctorProfileScreen.open(context),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _pressed
                  ? const [Color(0xFF0F766E), Color(0xFF075985)]
                  : const [Color(0xFF0D9488), Color(0xFF0369A1)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.patientTeal
                    .withValues(alpha: _pressed ? 0.16 : 0.22),
                blurRadius: _pressed ? 4 : 6,
                offset: Offset(0, _pressed ? 1 : 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: widget.radius,
            backgroundColor: AppColors.surfaceOf(context),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? Text(
                    initial,
                    style: GoogleFonts.inter(
                      fontSize: widget.radius * 0.82,
                      fontWeight: FontWeight.w800,
                      color: AppColors.patientTeal,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
