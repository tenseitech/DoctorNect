import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Gallery/camera image selection.
///
/// On Android, gallery uses the system Photo Picker (`PickVisualMedia`) so the
/// app does not need `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`. Call
/// [enableAndroidPhotoPicker] at startup before any [ImagePicker] API.
class PickedGalleryImage {
  const PickedGalleryImage({
    required this.name,
    required this.bytes,
    this.path,
  });

  final String name;
  final Uint8List bytes;
  final String? path;
}

abstract final class GalleryImagePicker {
  static final ImagePicker _picker = ImagePicker();
  static bool _androidPhotoPickerEnabled = false;

  /// Enables Android Photo Picker. Safe to call more than once and on non-Android.
  static void enableAndroidPhotoPicker() {
    if (_androidPhotoPickerEnabled) return;
    final implementation = ImagePickerPlatform.instance;
    if (implementation is ImagePickerAndroid) {
      implementation.useAndroidPhotoPicker = true;
    }
    _androidPhotoPickerEnabled = true;
  }

  static Future<PickedGalleryImage?> pickSingle({int imageQuality = 85}) {
    return _pick(source: ImageSource.gallery, imageQuality: imageQuality);
  }

  static Future<PickedGalleryImage?> pickFromCamera({int imageQuality = 85}) {
    return _pick(source: ImageSource.camera, imageQuality: imageQuality);
  }

  static Future<List<PickedGalleryImage>> pickMultiple({int imageQuality = 85}) async {
    enableAndroidPhotoPicker();
    final files = await _picker.pickMultiImage(imageQuality: imageQuality);
    if (files.isEmpty) return const [];

    final picked = <PickedGalleryImage>[];
    for (final file in files) {
      final image = await _fromXFile(file);
      if (image != null) picked.add(image);
    }
    return picked;
  }

  static Future<PickedGalleryImage?> _pick({
    required ImageSource source,
    required int imageQuality,
  }) async {
    enableAndroidPhotoPicker();
    final file = await _picker.pickImage(
      source: source,
      imageQuality: imageQuality,
    );
    if (file == null) return null;
    return _fromXFile(file);
  }

  static Future<PickedGalleryImage?> _fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedGalleryImage(
      name: file.name,
      path: file.path,
      bytes: bytes,
    );
  }
}
