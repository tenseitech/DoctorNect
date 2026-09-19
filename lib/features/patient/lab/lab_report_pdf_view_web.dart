// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Web PDF preview — desktop uses a blob iframe; mobile browsers skip iframe
/// (iOS Safari renders blob PDFs blank inside iframes).
class LabReportPdfView extends StatefulWidget {
  const LabReportPdfView({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onDownload,
  });

  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;

  @override
  State<LabReportPdfView> createState() => _LabReportPdfViewState();
}

class _LabReportPdfViewState extends State<LabReportPdfView> {
  late final String _viewType;
  String? _blobUrl;
  bool _iframeRegistered = false;
  bool? _useMobileFallback;

  @override
  void initState() {
    super.initState();
    _viewType = 'lab-report-pdf-$hashCode';
    final blob = html.Blob([widget.bytes], 'application/pdf');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);
  }

  bool _isMobileWeb(BuildContext context) {
    if (!kIsWeb) return false;
    if (ResponsiveLayout.isCompact(context)) return true;

    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod') ||
        (ua.contains('android') && ua.contains('mobile'));
  }

  void _registerIframe() {
    final blobUrl = _blobUrl;
    if (blobUrl == null) return;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = html.IFrameElement()
        ..src = blobUrl
        ..style.border = 'none'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;

      return html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.margin = '0'
        ..style.padding = '0'
        ..style.overflow = 'hidden'
        ..append(iframe);
    });
    _iframeRegistered = true;
  }

  void _openReportInNewTab() {
    final url = _blobUrl;
    if (url == null) return;
    html.window.open(url, '_blank');
  }

  @override
  void dispose() {
    final url = _blobUrl;
    if (url != null) {
      html.Url.revokeObjectUrl(url);
    }
    super.dispose();
  }

  Widget _buildMobileFallback() {
    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 72, color: AppColors.labPurple),
              const SizedBox(height: 16),
              Text(
                widget.fileName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Your browser works best when this report opens in a full-screen viewer.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context), height: 1.45),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openReportInNewTab,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open report'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.labPurple,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _useMobileFallback ??= _isMobileWeb(context);

    if (_useMobileFallback!) {
      return _buildMobileFallback();
    }

    if (!_iframeRegistered) {
      _registerIframe();
    }

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: SizedBox.expand(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
