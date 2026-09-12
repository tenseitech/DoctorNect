import '../notifications/app_toast.dart';
import '../security/input_sanitize.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalLauncher {
  static Future<bool> openUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    late final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return false;
    }
    if (!InputSanitize.isAllowedLaunchUri(uri)) return false;

    try {
      return await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    }
  }

  /// Normalizes an Indian phone string to dialable digits (with leading + when present).
  static String? normalizePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) return null;
    final lower = phone.toLowerCase();
    if (lower.contains('contact via')) return null;

    var digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('+')) return digits;

    if (digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) {
      return '+91$digits';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    return digits;
  }

  /// WhatsApp wa.me expects digits without + prefix.
  static String? whatsAppPhoneDigits(String? phone) {
    final normalized = normalizePhone(phone);
    if (normalized == null) return null;
    return normalized.replaceAll(RegExp(r'\D'), '');
  }

  /// Opens the phone dialer with the doctor's number.
  static Future<bool> callPhone(String phone, {BuildContext? context}) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) {
      if (context != null && context.mounted) {
        AppToast.info(context, 'Doctor phone number is not available');
      }
      return false;
    }

    final uri = Uri(scheme: 'tel', path: normalized);
    try {
      return await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (_) {
      try {
        return await launchUrl(uri);
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: normalized));
        if (context != null && context.mounted) {
          AppToast.info(context, 'Could not open dialer. Number copied: $normalized');
        }
        return false;
      }
    }
  }

  /// Opens the native SMS composer with a pre-filled body when supported.
  static Future<bool> composeSms({
    required String phone,
    required String body,
    BuildContext? context,
  }) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) return shareSmsBody(body: body, context: context);

    final uri = Uri(
      scheme: 'sms',
      path: normalized,
      queryParameters: <String, String>{'body': body},
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: '$body\n\nSend to: $normalized'));
      if (context != null && context.mounted) {
        AppToast.info(context, 'SMS app not available. Message copied to clipboard.');
      }
      return false;
    }
  }

  /// Opens SMS composer with message body only (pick recipient in the SMS app).
  static Future<bool> shareSmsBody({
    required String body,
    BuildContext? context,
  }) async {
    final uri = Uri(
      scheme: 'sms',
      queryParameters: <String, String>{'body': body},
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: body));
      if (context != null && context.mounted) {
        AppToast.info(context, 'SMS not available. Message copied to clipboard.');
      }
      return false;
    }
  }

  /// Share text via WhatsApp.
  static Future<bool> shareViaWhatsApp({
    required String text,
    String? phone,
    BuildContext? context,
  }) async {
    final waDigits = whatsAppPhoneDigits(phone);
    final uri = waDigits == null
        ? Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}')
        : Uri.parse('https://wa.me/$waDigits?text=${Uri.encodeComponent(text)}');

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context != null && !context.mounted) return false;
      return shareText(text, context: context);
    }
  }

  /// Share text via Telegram.
  static Future<bool> shareViaTelegram({
    required String text,
    String? url,
    BuildContext? context,
  }) async {
    final shareUrl = url?.trim().isNotEmpty == true ? url!.trim() : 'https://doctornect.com';
    final tgWeb = Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(shareUrl)}&text=${Uri.encodeComponent(text)}',
    );
    final tgApp = Uri.parse('tg://msg?text=${Uri.encodeComponent(text)}');

    try {
      if (await canLaunchUrl(tgApp)) {
        return await launchUrl(tgApp, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(tgWeb, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context != null && !context.mounted) return false;
      return shareText(text, context: context);
    }
  }

  /// Share plain text using the native share sheet.
  static Future<bool> shareText(String text, {BuildContext? context}) async {
    try {
      final result = await Share.share(text);
      return result.status == ShareResultStatus.success;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context != null && context.mounted) {
        AppToast.info(context, 'Copied to clipboard');
      }
      return false;
    }
  }
}
