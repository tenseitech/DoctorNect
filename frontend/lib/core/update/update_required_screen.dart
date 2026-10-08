import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen update prompt. There is no dismiss control.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.message,
    required this.storeUrl,
  });

  final String message;
  final String storeUrl;

  Future<void> _openStore() async {
    final uri = Uri.tryParse(storeUrl.trim());
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Update required',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _openStore,
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
