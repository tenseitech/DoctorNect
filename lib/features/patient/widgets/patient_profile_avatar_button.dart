import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../profile/data/patient_photo_local_store.dart';
import '../profile/data/patient_profile_mock.dart';
import 'package:medibond/features/shared/screens/patient_profile_screen.dart';

class PatientProfileAvatarButton extends StatefulWidget {
  const PatientProfileAvatarButton({super.key, this.radius = 20});

  final double radius;

  @override
  State<PatientProfileAvatarButton> createState() => _PatientProfileAvatarButtonState();
}

class _PatientProfileAvatarButtonState extends State<PatientProfileAvatarButton> {
  Uint8List? _localPhotoBytes;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    PatientProfileMock.listenable.addListener(_onProfileChanged);
    unawaited(_loadLocalPhoto());
  }

  @override
  void dispose() {
    PatientProfileMock.listenable.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    unawaited(_loadLocalPhoto());
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalPhoto() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return;

    final bytes = await PatientPhotoLocalStore.load(patientId);
    if (!mounted) return;
    setState(() => _localPhotoBytes = bytes);
  }

  ImageProvider? _avatarImage(String? photoUrl) {
    final patientId = PatientSession.loggedInPatientId;
    final bytes = _localPhotoBytes ?? PatientPhotoLocalStore.readCached(patientId);
    if (bytes != null && bytes.isNotEmpty) {
      return MemoryImage(bytes);
    }
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      return NetworkImage(photoUrl.trim());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final profile = PatientProfileMock.profile;
    final name = profile.name.isNotEmpty ? profile.name : PatientSession.loggedInPatientName;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    final avatarImage = _avatarImage(profile.photoUrl);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PatientProfileScreen.open(context),
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
                color: AppColors.patientTeal.withValues(alpha: _pressed ? 0.16 : 0.22),
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
