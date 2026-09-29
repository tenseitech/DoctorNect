import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/media/gallery_image_picker.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/s3_aware_network_image.dart';

class PickedProfilePhoto {
  const PickedProfilePhoto({this.path, this.bytes});

  final String? path;
  final Uint8List? bytes;

  bool get hasImage =>
      (bytes != null && bytes!.isNotEmpty) ||
      (path != null && path!.isNotEmpty);
}

Future<PickedProfilePhoto?> pickProfilePhoto(
  BuildContext context, {
  bool hasExisting = false,
  VoidCallback? onView,
  VoidCallback? onRemove,
}) async {
  final result = await showModalBottomSheet<dynamic>(
    context: context,
    backgroundColor: AppColors.surfaceOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Text(
              'Upload Profile Photo',
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          if (hasExisting && onView != null)
            ListTile(
              leading: const Icon(
                Icons.fullscreen,
                color: AppColors.doctorBlue,
              ),
              title: Text(
                'View photo',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx, 'view');
              },
            ),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppColors.doctorBlue,
            ),
            title: Text(
              'Choose from gallery',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
            onTap: () async {
              try {
                final picked = await GalleryImagePicker.pickSingle();
                if (context.mounted) Navigator.pop(ctx, picked);
              } catch (_) {
                if (context.mounted) Navigator.pop(ctx, null);
              }
            },
          ),
          if (hasExisting && onRemove != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: Text(
                'Remove photo',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx, 'remove');
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );

  if (result == null) return null;

  if (result == 'view') {
    if (onView != null) onView();
    return null;
  }

  if (result == 'remove') {
    if (onRemove != null) onRemove();
    return null;
  }

  if (result is PickedGalleryImage) {
    return PickedProfilePhoto(
      path: result.path ?? result.name,
      bytes: result.bytes,
    );
  }

  return null;
}

/// Shows uploaded profile photo or name initial.
class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({
    super.key,
    required this.displayName,
    this.photoPath,
    this.photoBytes,
    this.photoUrl,
    this.photoKey,
    this.photoStorage,
    this.radius = 44,
    this.backgroundColor,
    this.fallbackColor,
  });

  final String displayName;
  final String? photoPath;
  final Uint8List? photoBytes;
  final String? photoUrl;
  final String? photoKey;
  final String? photoStorage;
  final double radius;
  final Color? backgroundColor;
  final Color? fallbackColor;

  ImageProvider? _imageProvider(BuildContext context) {
    final diameter = radius * 2;
    return S3AwareImageProvider.resolveProvider(
      photoKey: photoKey,
      photoStorage: photoStorage,
      legacyUrl: photoUrl,
      photoBytes: photoBytes,
      photoPath: photoPath,
      context: context,
      width: diameter,
      height: diameter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _imageProvider(context);
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : 'D';
    final bg = backgroundColor ?? AppColors.doctorBlue.withValues(alpha: 0.15);
    final fg = fallbackColor ?? AppColors.doctorBlue;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: image,
      child: image == null
          ? Text(
              initial,
              style: GoogleFonts.inter(
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            )
          : null,
    );
  }
}
