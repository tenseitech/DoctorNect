import 'package:flutter/material.dart';

class SectionSaveBar extends StatelessWidget {
  const SectionSaveBar(
      {super.key, required this.visible, required this.onSave});

  final bool visible;
  final VoidCallback onSave;

  static const _maxContentWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Save Changes'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
