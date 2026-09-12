import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/doctor_invite_action_button.dart';
import '../../../widgets/nav_request_dot.dart';
import '../widgets/doctor_screen_title_bar.dart';

/// Generic profile item for Pharmacy or Lab search and listing from Doctor suite.
class DoctorPartnerProfileItem {
  DoctorPartnerProfileItem({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.address,
    required this.phone,
    required this.email,
    required this.city,
    this.registrationNumber = '',
  });

  final String id;
  final String name;
  final String ownerName;
  final String address;
  final String phone;
  final String email;
  final String city;
  final String registrationNumber;
}

/// Generic connection item for Doctor <-> Partner connection.
class DoctorPartnerConnectionItem {
  DoctorPartnerConnectionItem({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.requestedAt,
    this.respondedAt,
  });

  final String id;
  final String partnerId;
  final String partnerName;
  final DateTime requestedAt;
  final DateTime? respondedAt;
}

/// Shared base UI for Doctor's Connected Stores & Connected Labs screens.
class DoctorConnectedPartnersBaseView extends StatefulWidget {
  const DoctorConnectedPartnersBaseView({
    super.key,
    required this.partnerRole,
    required this.partnerHeaderTitle,
    required this.partnerHeaderSubtitle,
    required this.partnerTypeLabel,
    required this.accentColor,
    required this.listenables,
    required this.activeConnections,
    required this.pendingFromPartner,
    required this.pendingFromDoctor,
    required this.searchResults,
    required this.searchHintText,
    required this.cityFilterLabel,
    required this.activitySubtitleBuilder,
    required this.onSearchPartners,
    required this.onViewPatients,
    required this.onDisconnect,
    required this.onApprove,
    required this.onReject,
    required this.onRevoke,
    required this.onSendRequest,
    required this.onOpenAddPartner,
    required this.onOpenInviteSheet,
    required this.attachFirestoreSync,
    required this.detachFirestoreSync,
    required this.isConnected,
    required this.isPendingSent,
    required this.isPendingFromPartner,
    this.showAppBar = true,
    this.appBarTitle,
  });

  final UserType partnerRole;
  final String partnerHeaderTitle;
  final String partnerHeaderSubtitle;
  final String partnerTypeLabel;
  final Color accentColor;
  final List<Listenable> listenables;
  final List<DoctorPartnerConnectionItem> Function() activeConnections;
  final List<DoctorPartnerConnectionItem> Function() pendingFromPartner;
  final List<DoctorPartnerConnectionItem> Function() pendingFromDoctor;
  final List<DoctorPartnerProfileItem> Function() searchResults;
  final String searchHintText;
  final String? Function() cityFilterLabel;
  final String Function(String partnerId) activitySubtitleBuilder;
  final void Function(String query) onSearchPartners;
  final void Function(String partnerId, String partnerName) onViewPatients;
  final void Function(String connectionId, String partnerName) onDisconnect;
  final void Function(String connectionId, String partnerName) onApprove;
  final void Function(String connectionId, String partnerName) onReject;
  final void Function(String connectionId, String partnerName) onRevoke;
  final String? Function(DoctorPartnerProfileItem partner) onSendRequest;
  final void Function() onOpenAddPartner;
  final void Function() onOpenInviteSheet;
  final void Function() attachFirestoreSync;
  final void Function() detachFirestoreSync;
  final bool Function(String partnerId) isConnected;
  final bool Function(String partnerId) isPendingSent;
  final bool Function(String partnerId) isPendingFromPartner;
  final bool showAppBar;
  final String? appBarTitle;

  @override
  State<DoctorConnectedPartnersBaseView> createState() => _DoctorConnectedPartnersBaseViewState();
}

class _DoctorConnectedPartnersBaseViewState extends State<DoctorConnectedPartnersBaseView> {
  final _searchController = TextEditingController();
  bool get _isAddMode => widget.showAppBar && widget.appBarTitle == 'Add ${widget.partnerTypeLabel}';

  @override
  void initState() {
    super.initState();
    widget.attachFirestoreSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onSearchPartners('');
      }
    });
  }

  @override
  void dispose() {
    widget.detachFirestoreSync();
    _searchController.dispose();
    super.dispose();
  }

  void _triggerSearch() {
    if (!mounted) return;
    setState(() {
      widget.onSearchPartners(_searchController.text);
    });
  }

  Future<void> _confirmDisconnect(DoctorPartnerConnectionItem connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Disconnect from ${connection.partnerName}?'),
        content: Text(
          "You won't be able to send new orders/prescriptions to this ${widget.partnerTypeLabel.toLowerCase()} until you reconnect.",
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    widget.onDisconnect(connection.id, connection.partnerName);
    AppToast.info(context, 'Disconnected from ${connection.partnerName}');
  }

  void _sendRequest(DoctorPartnerProfileItem partner) {
    final error = widget.onSendRequest(partner);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Invite Sent to ${partner.name}'),
        backgroundColor: error == null ? widget.accentColor : null,
      ),
    );
    if (error == null) _triggerSearch();
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.inputRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(Icons.search, size: 22, color: AppColors.textSecondaryOf(context)),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.searchHintText,
                hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
              onSubmitted: (_) => _triggerSearch(),
              onChanged: (_) {
                if (_searchController.text.trim().isEmpty) _triggerSearch();
              },
            ),
          ),
          TextButton(
            onPressed: _triggerSearch,
            style: TextButton.styleFrom(
              foregroundColor: widget.accentColor,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text('Search', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: Listenable.merge(widget.listenables),
      builder: (context, _) {
        final pendingFromPartner = widget.pendingFromPartner();
        final pendingFromDoctor = widget.pendingFromDoctor();
        final active = widget.activeConnections();

        if (_isAddMode) {
          return _buildAddPartnerContent(pendingFromPartner, pendingFromDoctor);
        }

        final pendingCount = pendingFromPartner.length + pendingFromDoctor.length;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DoctorScreenTitleBar(
              title: widget.partnerHeaderTitle,
              subtitle: widget.partnerHeaderSubtitle,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onOpenAddPartner,
                    icon: IconWithRequestDot(
                      showDot: pendingCount > 0,
                      dotColor: widget.accentColor,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                    label: Text(
                      pendingCount > 0 ? 'Add ${widget.partnerTypeLabel} ($pendingCount)' : 'Add ${widget.partnerTypeLabel}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenInviteSheet,
                    icon: const Icon(Icons.link, size: 18),
                    label: Text('Invite', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.accentColor,
                      side: BorderSide(color: widget.accentColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DocSectionHeader(title: 'Connected', count: active.length),
            const SizedBox(height: 8),
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.storefront_outlined, size: 48, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text('No ${widget.partnerTypeLabel.toLowerCase()}s connected yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Add ${widget.partnerTypeLabel}" to search and connect.',
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...active.map(
                (c) => _DocConnectedPartnerRow(
                  connection: c,
                  subtitle: widget.activitySubtitleBuilder(c.partnerId),
                  accentColor: widget.accentColor,
                  onViewPatients: () => widget.onViewPatients(c.partnerId, c.partnerName),
                  onDisconnect: () => _confirmDisconnect(c),
                ),
              ),
          ],
        );
      },
    );

    if (widget.showAppBar) {
      return Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        appBar: AppBar(
          title: Text(widget.appBarTitle ?? widget.partnerHeaderTitle, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.surfaceOf(context),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildAddPartnerContent(
    List<DoctorPartnerConnectionItem> pendingFromPartner,
    List<DoctorPartnerConnectionItem> pendingFromDoctor,
  ) {
    final results = widget.searchResults();
    final cityLabel = widget.cityFilterLabel();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSearchBar(),
        const SizedBox(height: 16),
        if (pendingFromPartner.isNotEmpty) ...[
          _DocSectionHeader(title: 'Requests for you', count: pendingFromPartner.length),
          const SizedBox(height: 8),
          ...pendingFromPartner.map(
            (c) => _DocPendingCard(
              title: c.partnerName,
              dateLabel: 'Requested: ${c.requestedAt.day}/${c.requestedAt.month}/${c.requestedAt.year}',
              accentColor: widget.accentColor,
              onApprove: () {
                widget.onApprove(c.id, c.partnerName);
                AppToast.info(context, 'Connected with ${c.partnerName}');
              },
              onReject: () {
                widget.onReject(c.id, c.partnerName);
                AppToast.info(context, 'Rejected ${c.partnerName}');
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (pendingFromDoctor.isNotEmpty) ...[
          _DocSectionHeader(title: 'Sent by you (Pending)', count: pendingFromDoctor.length),
          const SizedBox(height: 8),
          ...pendingFromDoctor.map(
            (c) => _DocPendingInviteRow(
              title: c.partnerName,
              dateLabel: 'Sent: ${c.requestedAt.day}/${c.requestedAt.month}/${c.requestedAt.year}',
              accentColor: widget.accentColor,
              onRevoke: () {
                widget.onRevoke(c.id, c.partnerName);
                AppToast.info(context, 'Invite revoked for ${c.partnerName}');
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        _DocSectionHeader(
          title: cityLabel == null ? 'All verified ${widget.partnerTypeLabel.toLowerCase()}s' : '${widget.partnerTypeLabel}s in $cityLabel',
          count: results.length,
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No verified ${widget.partnerTypeLabel.toLowerCase()}s found.',
                style: GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
              ),
            ),
          )
        else
          ...results.map(
            (p) => _DocPartnerSearchTile(
              partner: p,
              accentColor: widget.accentColor,
              isConnected: widget.isConnected(p.id),
              isPendingSent: widget.isPendingSent(p.id),
              isPendingFromPartner: widget.isPendingFromPartner(p.id),
              onConnect: () => _sendRequest(p),
            ),
          ),
      ],
    );
  }
}

class _DocSectionHeader extends StatelessWidget {
  const _DocSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.borderOf(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _DocConnectedPartnerRow extends StatelessWidget {
  const _DocConnectedPartnerRow({
    required this.connection,
    required this.subtitle,
    required this.accentColor,
    required this.onViewPatients,
    required this.onDisconnect,
  });

  final DoctorPartnerConnectionItem connection;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onViewPatients;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accentColor.withValues(alpha: 0.12),
            child: Text(
              connection.partnerName.trim().isNotEmpty ? connection.partnerName.trim()[0].toUpperCase() : 'P',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: accentColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connection.partnerName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onViewPatients,
            style: OutlinedButton.styleFrom(
              foregroundColor: accentColor,
              side: BorderSide(color: accentColor),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('View Patients', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.link_off, size: 18, color: AppColors.error),
            tooltip: 'Disconnect',
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}

class _DocPendingInviteRow extends StatelessWidget {
  const _DocPendingInviteRow({
    required this.title,
    required this.dateLabel,
    required this.accentColor,
    required this.onRevoke,
  });

  final String title;
  final String dateLabel;
  final Color accentColor;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(dateLabel, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          DoctorInviteActionButton(
            isPending: true,
            accentColor: accentColor,
            onInvite: () {},
            onRevoke: onRevoke,
          ),
        ],
      ),
    );
  }
}

class _DocPartnerSearchTile extends StatelessWidget {
  const _DocPartnerSearchTile({
    required this.partner,
    required this.accentColor,
    required this.isConnected,
    required this.isPendingSent,
    required this.isPendingFromPartner,
    required this.onConnect,
  });

  final DoctorPartnerProfileItem partner;
  final Color accentColor;
  final bool isConnected;
  final bool isPendingSent;
  final bool isPendingFromPartner;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner.name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(partner.address, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          if (isConnected)
            Text('Connected', style: GoogleFonts.inter(fontSize: 13, color: accentColor, fontWeight: FontWeight.w600))
          else if (isPendingSent)
            Text('Pending', style: GoogleFonts.inter(fontSize: 13, color: Colors.amber.shade700, fontWeight: FontWeight.w600))
          else if (isPendingFromPartner)
            Text('Requested', style: GoogleFonts.inter(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w600))
          else
            FilledButton(
              onPressed: onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _DocPendingCard extends StatelessWidget {
  const _DocPendingCard({
    required this.title,
    required this.dateLabel,
    required this.accentColor,
    required this.onApprove,
    required this.onReject,
  });

  final String title;
  final String dateLabel;
  final Color accentColor;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(dateLabel, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onReject,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
            child: const Text('Decline', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onApprove,
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('Accept', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}