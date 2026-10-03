import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main AndroidManifest strips broad gallery media permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    for (final permission in [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
      'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
    ]) {
      expect(
        manifest,
        contains('android:name="$permission" tools:node="remove"'),
        reason: 'Expected merged-permission removal for $permission',
      );
    }
  });

  test('gallery image picking uses Android Photo Picker entry point', () {
    final picker =
        File('lib/core/media/gallery_image_picker.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(picker, contains('useAndroidPhotoPicker = true'));
    expect(picker, contains('pickMultiImage'));
    expect(picker, contains('pickImage'));
    expect(main, contains('GalleryImagePicker.enableAndroidPhotoPicker()'));
  });
}
