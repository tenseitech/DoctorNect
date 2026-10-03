import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/invite/pharmacy_doctor_invite_service.dart';
import '../../../core/session/ambulance_session.dart';
import '../../../core/session/lab_session.dart';
import '../../../core/session/medical_store_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/external_launcher.dart';
import '../../lab/data/lab_registry.dart';
import '../../pharmacy/data/medical_store_registry.dart';

abstract final class LabDoctorInviteService {
  static const appDownloadUrl = 'https://doctornect.com/download';

  static String buildInviteLink(String labId, {String? role}) {
    final id = labId.trim().isEmpty ? 'lab' : labId.trim();
    final params = <String, String>{'lab': id};
    if (role != null) {
      params['role'] = role;
    }
    return Uri.parse(appDownloadUrl)
        .replace(queryParameters: params)
        .toString();
  }

  static String inviteMessage({
    required String labName,
    required String link,
    String? role,
  }) {
    final name = labName.trim().isEmpty ? 'A diagnostic lab' : labName.trim();
    if (role == 'doctor') {
      return '$name invited you to download DoctorNect and register as a doctor to connect with their lab. '
          'Download the app and sign up using this link:\n$link';
    }
    return '$name invited you to download DoctorNect to connect with their lab. '
        'Download the app and sign up using this link:\n$link';
  }

  static String labNameForCurrentLab() {
    final labId = LabSession.loggedInLabId;
    final lab = LabRegistry.findById(labId);
    final name = lab?.labName.trim();
    if (name != null && name.isNotEmpty) return name;
    final sessionName = LabSession.loggedInLabName.trim();
    return sessionName.isEmpty ? 'Your lab' : sessionName;
  }
}

typedef InviteDoctorSheet = LabInviteDoctorSheet;

class LabInviteDoctorSheet extends StatefulWidget {
  const LabInviteDoctorSheet({
    super.key,
    this.role,
    this.title,
    this.partnerRole,
    this.partnerId,
    this.partnerName,
    this.partnerTypeLabel,
    this.accentColor,
    this.inviteUrl,
  });

  final String? role;
  final String? title;
  final UserType? partnerRole;
  final String? partnerId;
  final String? partnerName;
  final String? partnerTypeLabel;
  final Color? accentColor;
  final String? inviteUrl;

  static Future<void> show(
    BuildContext context, {
    String? role,
    String? title,
    UserType? partnerRole,
    String? partnerId,
    String? partnerName,
    String? partnerTypeLabel,
    Color? accentColor,
    String? inviteUrl,
  }) {
    final isDark = AppColors.isDark(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          isDark ? AppColors.darkSurface : AppColors.surfaceOf(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LabInviteDoctorSheet(
        role: role,
        title: title,
        partnerRole: partnerRole,
        partnerId: partnerId,
        partnerName: partnerName,
        partnerTypeLabel: partnerTypeLabel,
        accentColor: accentColor,
        inviteUrl: inviteUrl,
      ),
    );
  }

  @override
  State<LabInviteDoctorSheet> createState() => _LabInviteDoctorSheetState();
}

class _LabInviteDoctorSheetState extends State<LabInviteDoctorSheet> {
  UserType _resolvePartnerRole() {
    if (widget.partnerRole != null) return widget.partnerRole!;
    if (MedicalStoreSession.loggedInStoreId.isNotEmpty) {
      return UserType.medicalStore;
    }
    if (LabSession.loggedInLabId.isNotEmpty) {
      return UserType.lab;
    }
    if (AmbulanceSession.loggedInAmbulanceId.isNotEmpty) {
      return UserType.ambulance;
    }
    return UserType.lab;
  }

  String _resolveTypeLabel(UserType role) {
    if (widget.partnerTypeLabel != null &&
        widget.partnerTypeLabel!.trim().isNotEmpty) {
      return widget.partnerTypeLabel!.trim().toLowerCase();
    }
    return switch (role) {
      UserType.medicalStore => 'store',
      UserType.lab => 'lab',
      UserType.ambulance => 'service',
      _ => 'partner',
    };
  }

  Color _resolveAccentColor(BuildContext context, UserType role) {
    if (widget.accentColor != null) return widget.accentColor!;
    return switch (role) {
      UserType.medicalStore => AppColors.pharmacyGreen,
      UserType.lab => AppColors.labPurple,
      UserType.ambulance => AppColors.error,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  String _resolvePartnerId(UserType role) {
    if (widget.partnerId != null && widget.partnerId!.trim().isNotEmpty) {
      return widget.partnerId!.trim();
    }
    return switch (role) {
      UserType.medicalStore => MedicalStoreSession.loggedInStoreId,
      UserType.lab => LabSession.loggedInLabId,
      UserType.ambulance => AmbulanceSession.loggedInAmbulanceId,
      _ => '',
    };
  }

  String _resolvePartnerName(UserType role, String partnerId) {
    if (widget.partnerName != null && widget.partnerName!.trim().isNotEmpty) {
      return widget.partnerName!.trim();
    }
    if (role == UserType.medicalStore) {
      final store = MedicalStoreRegistry.findById(partnerId);
      final name = store?.storeName.trim();
      if (name != null && name.isNotEmpty) return name;
      final sessionName = MedicalStoreSession.loggedInStoreName.trim();
      if (sessionName.isNotEmpty) return sessionName;
      return 'Your store';
    }
    if (role == UserType.lab) {
      final lab = LabRegistry.findById(partnerId);
      final name = lab?.labName.trim();
      if (name != null && name.isNotEmpty) return name;
      return LabDoctorInviteService.labNameForCurrentLab();
    }
    if (role == UserType.ambulance) {
      final name = AmbulanceSession.loggedInAmbulanceName.trim();
      return name.isNotEmpty ? name : 'Your ambulance service';
    }
    return 'Your partner';
  }

  String _resolveInviteLink(UserType role, String partnerId) {
    if (widget.inviteUrl != null && widget.inviteUrl!.trim().isNotEmpty) {
      return widget.inviteUrl!.trim();
    }
    if (role == UserType.medicalStore) {
      return PharmacyDoctorInviteService.buildInviteLink(partnerId);
    }
    if (role == UserType.lab) {
      return LabDoctorInviteService.buildInviteLink(
        partnerId,
        role: widget.role ?? 'doctor',
      );
    }
    if (role == UserType.ambulance) {
      final paramId = partnerId.isEmpty ? 'ambulance' : partnerId;
      return Uri.parse(LabDoctorInviteService.appDownloadUrl)
          .replace(queryParameters: {
        'ambulance': paramId,
        'role': widget.role ?? 'doctor',
      }).toString();
    }
    return LabDoctorInviteService.buildInviteLink(
      partnerId,
      role: widget.role,
    );
  }

  String _resolveInviteMessage({
    required UserType role,
    required String partnerName,
    required String typeLabel,
    required String link,
  }) {
    if (role == UserType.medicalStore) {
      return PharmacyDoctorInviteService.inviteMessage(
        storeName: partnerName,
        link: link,
      );
    }
    if (role == UserType.lab) {
      return LabDoctorInviteService.inviteMessage(
        labName: partnerName,
        link: link,
        role: widget.role ?? 'doctor',
      );
    }
    final cleanName =
        partnerName.trim().isEmpty ? 'Our $typeLabel' : partnerName.trim();
    return '$cleanName invited you to download DoctorNect and register as a doctor to connect with their $typeLabel. '
        'Download the app and sign up using this link:\n$link';
  }

  Future<void> _copyLink(String message) async {
    await Clipboard.setData(ClipboardData(text: message));
  }

  Future<void> _shareLink(String message) async {
    await ExternalLauncher.shareText(message, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final partnerRole = _resolvePartnerRole();
    final typeLabel = _resolveTypeLabel(partnerRole);
    final accentColor = _resolveAccentColor(context, partnerRole);
    final partnerId = _resolvePartnerId(partnerRole);
    final partnerName = _resolvePartnerName(partnerRole, partnerId);
    final link = _resolveInviteLink(partnerRole, partnerId);
    final shareMessage = _resolveInviteMessage(
      role: partnerRole,
      partnerName: partnerName,
      typeLabel: typeLabel,
      link: link,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBorder
                      : AppColors.textSecondaryOf(context)
                          .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title ?? 'Invite Doctor',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.headlineMedium,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this link with a doctor who is not on DoctorNect yet. They can download the app and connect with your $typeLabel.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? accentColor.withValues(alpha: 0.12)
                    : accentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accentColor.withValues(alpha: isDark ? 0.35 : 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 20,
                    color: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      link,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _copyLink(shareMessage),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(
                'Copy invite',
                style:
                    TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _shareLink(shareMessage),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(
                  color: accentColor.withValues(alpha: isDark ? 0.5 : 0.6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(
                'Share invite',
                style:
                    TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
