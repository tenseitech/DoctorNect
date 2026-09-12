import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider? profilePhotoFileProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (file.existsSync()) return FileImage(file);
  return null;
}
