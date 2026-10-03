import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  String title = 'Delete?',
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      content: Text(message, style: TextStyle(fontFamily: 'Inter')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.white,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
