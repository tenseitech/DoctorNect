import '../../../../core/notifications/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';

import '../../../../core/session/doctor_session.dart'; // FIXED: doctor id for Firestore persist
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/doctor_credentials_editor.dart';
import '../../../../widgets/image_viewer_dialog.dart';
import '../../../../widgets/profile_photo_avatar.dart';
import '../data/doctor_photo_local_store.dart';
import '../data/doctor_profile_store.dart';
import '../widgets/section_save_bar.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/s3_aware_network_image.dart';

/// Quick edit for top-card fields: name, specialization, languages.
class EditProfileSection extends StatefulWidget {
  const EditProfileSection({super.key});

  @override
  State<EditProfileSection> createState() => _EditProfileSectionState();
}

class _EditProfileSectionState extends State<EditProfileSection> {
  late final _name = TextEditingController(text: _p.fullName);
  late List<String> _specializations = List<String>.from(_p.specializations);
  late List<String> _degrees = List<String>.from(_p.degrees);
  bool _dirty = false;

  DoctorProfileData get _p => DoctorProfileStore.instance.profile;

  @override
  void initState() {
    super.initState();
    DoctorProfileStore.instance.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    DoctorProfileStore.instance.removeListener(_onProfileChanged);
    _name.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  ImageProvider? get _avatarImage {
    final doctorId = DoctorSession.activeDoctorId;
    final bytes = _p.photoBytes ?? DoctorPhotoLocalStore.readCached(doctorId);
    return S3AwareImageProvider.resolveProvider(
      photoKey: _p.photoKey,
      photoStorage: _p.photoStorage,
      legacyUrl: _p.photoUrl,
      photoBytes: bytes,
    );
  }

  Future<void> _pickPhoto() async {
    ImageProvider? currentImage = _avatarImage;

    final picked = await pickProfilePhoto(
      context,
      hasExisting: currentImage != null,
      onView: () {
        if (currentImage != null) {
          showImageViewerDialog(context, currentImage, title: 'Profile Photo');
        }
      },
      onRemove: () async {
        final doctorId = DoctorSession.activeDoctorId;
        await DoctorProfileStore.instance.removePhoto(doctorId);
        _markDirty();
      },
    );
    if (picked == null || !picked.hasImage) {
      if (mounted)
        AppToast.error(context, 'No photo selected or picker failed.');
      return;
    }
    final doctorId = DoctorSession.activeDoctorId;
    setState(() {
      DoctorProfileStore.instance.updatePhoto(
        path: picked.path,
        bytes: picked.bytes,
      );
    });
    final bytes = picked.bytes;
    if (bytes != null && bytes.isNotEmpty && doctorId.isNotEmpty) {
      await DoctorPhotoLocalStore.save(doctorId, bytes);
      await DoctorProfileStore.instance.uploadPhotoToServer(doctorId, bytes);
    }
    _markDirty();
  }

  Future<void> _save() async {
    final cleanDegrees =
        _degrees.map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
    final cleanSpecializations = _specializations
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (cleanDegrees.isEmpty) {
      AppToast.info(context, 'Please enter at least one degree');
      return;
    }
    if (cleanSpecializations.isEmpty) {
      AppToast.info(context, 'Please enter at least one specialization');
      return;
    }

    _p.degrees = cleanDegrees;
    _p.qualification = cleanDegrees.join(', ');
    _p.specializations = cleanSpecializations;
    _p.specialization = cleanSpecializations.first;

    try {
      await DoctorProfileStore.instance.persist(DoctorSession.loggedInDoctorId);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(
        context,
        'Could not save changes. Please check your connection and try again.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final avatarImage = _avatarImage;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 48,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.15),
                                  backgroundImage: avatarImage,
                                  child: avatarImage == null
                                      ? Text(
                                          _name.text.isNotEmpty
                                              ? _name.text[0].toUpperCase()
                                              : 'D',
                                          style: const TextStyle(
                                            fontSize:
                                                AppTypography.displayLarge,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: GestureDetector(
                                    onTap: _pickPhoto,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF185FA5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _name,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Full name',
                              filled: true,
                              fillColor: AppColors.cardBgOf(context),
                              suffixIcon: Tooltip(
                                message: 'Name cannot be changed',
                                child: Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DoctorCredentialsEditor(
                            initialDegrees: _degrees,
                            initialSpecializations: _specializations,
                            onDegreesChanged: (v) {
                              _degrees = v;
                              _markDirty();
                            },
                            onSpecializationsChanged: (v) {
                              _specializations = v;
                              _markDirty();
                            },
                            accentColor: AppColors.doctorBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SectionSaveBar(visible: _dirty, onSave: _save),
        ],
      ),
    );
  }
}
