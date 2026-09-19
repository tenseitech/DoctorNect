import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/invite/doctor_invite_service.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_launcher.dart';
import '../profile/data/doctor_profile_store.dart';
import '../../../core/theme/app_typography.dart';

/// Doctor-to-doctor referral — generate and share an invite link.
class ReferDoctorView extends StatefulWidget {
  const ReferDoctorView({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: const ReferDoctorView(),
        );
      },
    );
  }

  @override
  State<ReferDoctorView> createState() => _ReferDoctorViewState();
}

class _ReferDoctorViewState extends State<ReferDoctorView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  String? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    setState(() => _loading = true);
    final link = await DoctorInviteService.linkForCurrentDoctor(userType: InviteNetworkUserType.doctor);
    if (!mounted) return;
    setState(() {
      _link = link;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _referMessage(String name, String link) {
    final doctorName = DoctorProfileStore.displayNameWithPrefix;
    return 'Hi Dr. $name, I am $doctorName inviting you to join DoctorNect — '
        'a platform for doctors to manage appointments, prescriptions, and patient care. '
        'Join me here: $link';
  }

  Future<void> _copyLink() async {
    if (!_formKey.currentState!.validate()) return;
    
    final link = _link ?? DoctorInviteService.buildNetworkInviteLink(
      doctorId: DoctorSession.loggedInDoctorId,
      userType: InviteNetworkUserType.doctor,
    );
    
    final name = _nameController.text.trim();
    final message = _referMessage(name, link);

    await Clipboard.setData(ClipboardData(text: message));
  }

  Future<void> _shareLink() async {
    if (!_formKey.currentState!.validate()) return;
    
    final link = _link ?? DoctorInviteService.buildNetworkInviteLink(
      doctorId: DoctorSession.loggedInDoctorId,
      userType: InviteNetworkUserType.doctor,
    );
    
    final name = _nameController.text.trim();
    final message = _referMessage(name, link);
    
    await ExternalLauncher.shareText(message, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final doctorName = DoctorProfileStore.displayNameWithPrefix;
    final fallbackLink = DoctorInviteService.buildNetworkInviteLink(
      doctorId: DoctorSession.loggedInDoctorId,
      userType: InviteNetworkUserType.doctor,
    );

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.doctorBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(TablerIcons.users_plus, color: AppColors.doctorBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Refer another Doctor',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          Text(
                            'Generate and share a referral link',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter the doctor\'s name to generate a personalized referral message with your link from $doctorName.',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration('Doctor name', Icons.person_outline),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter doctor name to generate message' : null,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.doctorBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.doctorBlue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 20, color: AppColors.doctorBlue.withValues(alpha: 0.9)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : SelectableText(
                                _link ?? fallbackLink,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.bodyMedium,
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
                  onPressed: _loading ? null : _copyLink,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(
                    'Copy Invite Message',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.doctorBlue,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _shareLink,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    'Share Invite',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.doctorBlue,
                    side: const BorderSide(color: AppColors.doctorBlue),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
      filled: true,
      fillColor: AppColors.cardBgOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        borderSide: const BorderSide(color: AppColors.doctorBlue, width: 1.5),
      ),
    );
  }
}
