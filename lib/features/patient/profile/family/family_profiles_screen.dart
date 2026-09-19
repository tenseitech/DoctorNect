import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/confirm_delete_dialog.dart';
import '../../../../widgets/labeled_remove_button.dart';
import '../data/patient_profile_mock.dart';
import '../models/patient_profile_models.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../widgets/profile_edit_widgets.dart';
import 'add_family_member_profile_screen.dart';
import '../../../../core/theme/app_typography.dart';

class FamilyProfilesScreen extends StatefulWidget {
  const FamilyProfilesScreen({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<FamilyProfilesScreen> createState() => _FamilyProfilesScreenState();
}

class _FamilyProfilesScreenState extends State<FamilyProfilesScreen> {
  Future<void> _openAddMember() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddFamilyMemberProfileScreen()),
    );
    setState(() {});
    widget.onChanged();
  }

  Future<void> _openEditMember(FamilyProfileMember member) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddFamilyMemberProfileScreen(existingMember: member),
      ),
    );
    setState(() {});
    widget.onChanged();
  }

  Future<void> _removeMember(FamilyProfileMember member) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      title: 'Remove family member?',
      message: 'Remove ${member.name} from your family profiles?',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    try {
      await PatientProfileMock.removeFamilyMember(member.id);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not remove family member. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = PatientProfileMock.familyMembers;

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: PatientProfileFormStyles.profileAppBar('Family Profiles',
          context: context),
      body: PatientProfileFormStyles.constrainedListWithBottom(
        listBuilder: (context) => ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          children: [
            ProfileEditWidgets.sectionCard(
              icon: Icons.family_restroom_outlined,
              title: 'Your family',
              subtitle: 'Book appointments and lab tests for members',
              child: members.isEmpty
                  ? _EmptyFamilyState(onAdd: _openAddMember)
                  : Column(
                      children: [
                        for (var i = 0; i < members.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _MemberCard(
                            member: members[i],
                            onTap: () => _openEditMember(members[i]),
                            onRemove: () => _removeMember(members[i]),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
        bottom: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: PatientProfileFormStyles.outlinedAddButton(
              label: 'Add member',
              onPressed: _openAddMember,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFamilyState extends StatelessWidget {
  const _EmptyFamilyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(Icons.people_outline,
              size: 48,
              color: AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'No family members yet',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, fontSize: AppTypography.bodyLarge),
          ),
          const SizedBox(height: 6),
          Text(
            'Add spouse, children, or parents to book on their behalf.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
                height: 1.4),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, color: AppColors.patientTeal),
            label: Text(
              'Add first member',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, color: AppColors.patientTeal),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onTap,
    required this.onRemove,
  });

  final FamilyProfileMember member;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final initial = member.photoInitial ?? member.name[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.patientTeal,
                            AppColors.patientTeal.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.surfaceOf(context),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              AppColors.patientTeal.withValues(alpha: 0.12),
                          child: Text(
                            initial,
                            style: GoogleFonts.inter(
                              color: AppColors.patientTeal,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: AppTypography.headlineSmall),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${member.relationLabel} · ${member.age} yrs · ${member.bloodGroup}',
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.labelMedium,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                          if (member.allergies.isNotEmpty ||
                              member.conditions.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (member.allergies.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.coronavirus_outlined,
                                    label:
                                        '${member.allergies.length} allergies',
                                  ),
                                if (member.conditions.isNotEmpty)
                                  _InfoChip(
                                    icon: Icons.monitor_heart_outlined,
                                    label:
                                        '${member.conditions.length} conditions',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryOf(context), size: 22),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LabeledRemoveButton(
            label: 'Remove member',
            icon: Icons.person_remove_outlined,
            fullWidth: true,
            compact: false,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.patientTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.patientTeal),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.patientTeal),
          ),
        ],
      ),
    );
  }
}
