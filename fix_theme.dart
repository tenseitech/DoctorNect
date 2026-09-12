import 'dart:io';

void main() async {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('lib directory not found.');
    return;
  }

  int modifiedFiles = 0;

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = await entity.readAsString();
      String modified = content;

      // 1. Direct easy replacements
      modified = modified.replaceAll('AppColors.cardBackground', 'AppColors.cardBgOf(context)');
      modified = modified.replaceAll('AppColors.textPrimary', 'AppColors.textPrimaryOf(context)');
      modified = modified.replaceAll('AppColors.textSecondary', 'AppColors.textSecondaryOf(context)');
      modified = modified.replaceAll('AppColors.border', 'AppColors.borderOf(context)');
      // Need to avoid replacing textPrimaryOf with textPrimaryOfOf
      modified = modified.replaceAll('AppColors.textPrimaryOf(context)Of(context)', 'AppColors.textPrimaryOf(context)');
      modified = modified.replaceAll('AppColors.textSecondaryOf(context)Of(context)', 'AppColors.textSecondaryOf(context)');
      modified = modified.replaceAll('AppColors.borderOf(context)Of(context)', 'AppColors.borderOf(context)');
      modified = modified.replaceAll('AppColors.cardBgOf(context)Of(context)', 'AppColors.cardBgOf(context)');

      // 2. Line by line for Colors.white and AppColors.white
      final lines = modified.split('\n');
      bool changedLines = false;
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i];
        
        // Skip if line contains elements where white is intentional (text, icons on colored background)
        if (line.contains('TextStyle(') || 
            line.contains('Icon(') || 
            line.contains('Text(') || 
            line.contains('SvgPicture') || 
            line.contains('CircularProgressIndicator') ||
            line.contains('elevatedButtonTheme') ||
            line.contains('ElevatedButton')) {
          continue;
        }

        // Only replace if it's assigned to a background-like property or just 'color:' inside a box/container
        if (line.contains('backgroundColor:') || 
            line.contains('fillColor:') || 
            line.contains('surfaceTintColor:') || 
            line.contains('color:')) {
          
          if (line.contains('Colors.white') || line.contains('AppColors.white')) {
            // Replace white with surfaceOf(context)
            line = line.replaceAll('Colors.white', 'AppColors.surfaceOf(context)');
            line = line.replaceAll('AppColors.white', 'AppColors.surfaceOf(context)');
            lines[i] = line;
            changedLines = true;
          }
        }
      }

      if (changedLines) {
        modified = lines.join('\n');
      }

      // Check if we need to add the import for AppColors
      if (modified != content) {
        if (!modified.contains('import \'package:medibond/core/theme/app_colors.dart\';') &&
            !modified.contains('app_colors.dart')) {
          
          // Basic heuristic to insert import
          // We will rely on manual fixes if this fails
        }
        await entity.writeAsString(modified);
        modifiedFiles++;
        print('Modified: ${entity.path}');
      }
    }
  }

  print('Modified $modifiedFiles files.');
}
