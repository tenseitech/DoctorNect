import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/enums/user_type.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/confirm_delete_dialog.dart';
import '../../../widgets/doctor_invite_action_button.dart';
import '../../../widgets/nav_request_dot.dart';
import '../../patient/data/registered_doctors_store.dart';
import '../../pharmacy/data/pharmacy_connection_store.dart';
import '../../shared/widgets/invite_doctor_sheet.dart';

const _lineColor = Color(0xFFE2E8F0);
const _headerBg = Color(0xFFF1F5F9);

String partnerDoctorLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Doctor';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

String partnerDoctorInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'D';
  for (final part in trimmed.split(RegExp(r'\s+'))) {
    if (part.isEmpty) continue;
    final lower = part.toLowerCase();
    if (lower == 'dr' || lower == 'dr.') continue;
    return part[0].toUpperCase();
  }
  return trimmed[0].toUpperCase();
}

String partnerDoctorSortKey(String name) {
  var trimmed = name.trim().toLowerCase();
  if (trimmed.startsWith('dr.')) trimmed = trimmed.substring(3).trim();
  if (trimmed.startsWith('dr ')) trimmed = trimmed.substring(3).trim();
  return trimmed;
}

List<RegisteredDoctorSearchResult> sortDoctorsAlphabetically(
  List<RegisteredDoctorSearchResult> doctors,
) {
  final sorted = List<RegisteredDoctorSearchResult>.from(doctors);
  sorted.sort((a, b) => partnerDoctorSortKey(a.name).compareTo(partnerDoctorSortKey(b.name)));
  return sorted;
}

/// Generic connection item for Partner <-> Doctor UI.
class PartnerConnectionItem {
  PartnerConnectionItem({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.requestedAt,
    this.respondedAt,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final DateTime requestedAt;
  final DateTime? respondedAt;
}

/// Shared base UI for Pharmacy & Lab doctor connection screens.
class PartnerConnectDoctorsBaseView extends StatefulWidget {
  const PartnerConnectDoctorsBaseView({
    super.key,
    required this.partnerRole,
    required this.partnerId,
    required this.partnerTypeLabel,
    required this.accentColor,
    required this.listenables,
    required this.activeConnections,
    required this.fromDoctorRequests,
    required this.sentByPartnerInvites,
    required this.cityFilter,
    required this.searchDoctorsFn,
    required this.activitySubtitleBuilder,
    required this.onApproveConnection,
    required this.onRejectConnection,
    required this.onRevokeConnection,
    required this.onRemoveConnection,
    required this.onSendRequest,
    required this.isConnected,
    required this.isPendingSent,
    required this.isPendingFromDoctor,
    required this.attachFirestoreSync,
    required this.detachFirestoreSync,
    required this.pageLayoutBuilder,
    this.showAppBar = false,
    this.appBarTitle,
    this.inviteDownloadSubtitle,
  });

  final UserType partnerRole;
  final String partnerId;
  final String partnerTypeLabel;
  final Color accentColor;
  final List<Listenable> listenables;
  final List<PartnerConnectionItem> Function() activeConnections;
  final List<PartnerConnectionItem> Function() fromDoctorRequests;
  final List<PartnerConnectionItem> Function() sentByPartnerInvites;
  final String? Function() cityFilter;
  final List<RegisteredDoctorSearchResult> Function(String query) searchDoctorsFn;
  final String Function(String doctorId) activitySubtitleBuilder;
  final void Function(String id, String doctorName) onApproveConnection;
  final void Function(String id, String doctorName) onRejectConnection;
  final void Function(String id, String doctorName) onRevokeConnection;
  final void Function(String id, String doctorName) onRemoveConnection;
  final String? Function(RegisteredDoctorSearchResult doctor) onSendRequest;
  final bool Function(String doctorId) isConnected;
  final bool Function(String doctorId) isPendingSent;
  final bool Function(String doctorId) isPendingFromDoctor;
  final void Function() attachFirestoreSync;
  final void Function() detachFirestoreSync;
  final Widget Function(BuildContext context, Widget child) pageLayoutBuilder;
  final bool showAppBar;
  final String? appBarTitle;
  final String? inviteDownloadSubtitle;

  @override
  State<PartnerConnectDoctorsBaseView> createState() => _PartnerConnectDoctorsBaseViewState();
}

class _PartnerConnectDoctorsBaseViewState extends State<PartnerConnectDoctorsBaseView> {
  final _searchController = TextEditingController();
  List<RegisteredDoctorSearchResult> _results = [];
  bool get _isAddDoctorMode => widget.showAppBar && widget.appBarTitle == 'Add Doctor';

  void _search() {
    if (!mounted) return;
    setState(() {
      _results = widget.searchDoctorsFn(_searchController.text);
    });
  }

  @override
  void initState() {
    super.initState();
    _results = widget.searchDoctorsFn('');
    RegisteredDoctorsStore.instance.addListener(_search);
    RegisteredDoctorsStore.instance.startListening();
    if (widget.showAppBar) {
      widget.attachFirestoreSync();
    }
  }

  @override
  void dispose() {
    RegisteredDoctorsStore.instance.removeListener(_search);
    if (widget.showAppBar) {
      widget.detachFirestoreSync();
    }
    _searchController.dispose();
    super.dispose();
  }

  void _openInviteDoctorSheet() {
    InviteDoctorSheet.show(context);
  }

  Widget _buildInviteDoctorCard({bool compact = false}) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(compact ? 14 : 12),
      child: InkWell(
        onTap: _openInviteDoctorSheet,
        borderRadius: BorderRadius.circular(compact ? 14 : 12),
        child: Container(
          padding: EdgeInsets.all(compact ? 14 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 14 : 12),
            border: Border.all(color: widget.accentColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.download_outlined, color: widget.accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite doctor to download app',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.inviteDownloadSubtitle ??
                          'Share a download link â€” they install DoctorNect, register as a doctor, and connect with your ${widget.partnerTypeLabel}',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context), height: 1.35),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Invite',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: widget.accentColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectActionButtons({required int pendingCount, bool compact = false}) {
    final addDoctorButton = FilledButton.icon(
      onPressed: _openAddDoctorScreen,
      icon: IconWithRequestDot(
        showDot: pendingCount > 0,
        dotColor: widget.accentColor,
        icon: const Icon(Icons.person_add_alt_1, size: 18),
      ),
      label: Text(
        pendingCount > 0 ? 'Add Doctor ($pendingCount)' : 'Add Doctor',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: widget.accentColor,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final inviteDoctorButton = OutlinedButton.icon(
      onPressed: _openInviteDoctorSheet,
      icon: const Icon(Icons.link, size: 18),
      label: Text(
        'Invite to download',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.accentColor,
        side: BorderSide(color: widget.accentColor),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          addDoctorButton,
          const SizedBox(height: 10),
          inviteDoctorButton,
        ],
      );
    }

    return Row(
      children: [
        addDoctorButton,
        const SizedBox(width: 10),
        inviteDoctorButton,
      ],
    );
  }

  void _openAddDoctorScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartnerConnectDoctorsBaseView(
          partnerRole: widget.partnerRole,
          partnerId: widget.partnerId,
          partnerTypeLabel: widget.partnerTypeLabel,
          accentColor: widget.accentColor,
          listenables: widget.listenables,
          activeConnections: widget.activeConnections,
          fromDoctorRequests: widget.fromDoctorRequests,
          sentByPartnerInvites: widget.sentByPartnerInvites,
          cityFilter: widget.cityFilter,
          searchDoctorsFn: widget.searchDoctorsFn,
          activitySubtitleBuilder: widget.activitySubtitleBuilder,
          onApproveConnection: widget.onApproveConnection,
          onRejectConnection: widget.onRejectConnection,
          onRevokeConnection: widget.onRevokeConnection,
          onRemoveConnection: widget.onRemoveConnection,
          onSendRequest: widget.onSendRequest,
          isConnected: widget.isConnected,
          isPendingSent: widget.isPendingSent,
          isPendingFromDoctor: widget.isPendingFromDoctor,
          attachFirestoreSync: widget.attachFirestoreSync,
          detachFirestoreSync: widget.detachFirestoreSync,
          pageLayoutBuilder: widget.pageLayoutBuilder,
          showAppBar: true,
          appBarTitle: 'Add Doctor',
          inviteDownloadSubtitle: widget.inviteDownloadSubtitle,
        ),
      ),
    );
  }

  void _sendRequest(RegisteredDoctorSearchResult doctor) {
    final error = widget.onSendRequest(doctor);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Invite sent to ${partnerDoctorLabel(doctor.name)}'),
        backgroundColor: error == null ? widget.accentColor : null,
      ),
    );
    if (error == null) _search();
  }

  Widget _buildSearchBar({bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(compact ? 14 : 12),
        border: Border.all(color: _lineColor),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: compact ? 'Search doctors...' : 'Search by name, clinic, or registration no...',
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
          prefixIcon: Icon(Icons.search, size: 22, color: AppColors.textSecondaryOf(context)),
          suffixIcon: _searchController.text.trim().isNotEmpty
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _search();
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 12 : 14,
          ),
        ),
        onSubmitted: (_) => _search(),
        onChanged: (_) {
          setState(() {});
          if (_searchController.text.trim().isEmpty) _search();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: Listenable.merge(widget.listenables),
      builder: (context, _) {
        final active = widget.activeConnections();
        final fromDoctor = widget.fromDoctorRequests();
        final sentByPartner = widget.sentByPartnerInvites();

        if (_isAddDoctorMode) {
          return _buildAddDoctorContent(widget.partnerId, fromDoctor, sentByPartner);
        }

        final pendingCount = fromDoctor.length + sentByPartner.length;
        final compact = ResponsiveLayout.isCompact(context);

        return widget.pageLayoutBuilder(
          context,
          ListView(
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Connect Dr.',
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your doctor connections and pending requests.',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 14),
                    _buildConnectActionButtons(pendingCount: pendingCount, compact: true),
                    const SizedBox(height: 14),
                    _buildInviteDoctorCard(compact: true),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connect Dr.',
                            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage your doctor connections and pending requests.',
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                    _buildConnectActionButtons(pendingCount: pendingCount),
                  ],
                ),
              const SizedBox(height: 24),
              _PartnerSectionHeader(title: 'Active connections', count: active.length),
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 48, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No active connections',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap Add Doctor to search and connect with a doctor.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...active.map((c) {
                  final subtitle = widget.activitySubtitleBuilder(c.doctorId);
                  return _PartnerConnectionTile(
                    connection: c,
                    subtitle: subtitle,
                    accentColor: widget.accentColor,
                    onRemove: () {
                      widget.onRemoveConnection(c.id, c.doctorName);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Disconnected from ${partnerDoctorLabel(c.doctorName)}')),
                      );
                    },
                  );
                }),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );

    if (widget.showAppBar) {
      final compact = ResponsiveLayout.isCompact(context);
      return Scaffold(
        backgroundColor: compact ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            widget.appBarTitle ?? 'Connect Dr.',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.surfaceOf(context),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _lineColor),
          ),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildAddDoctorContent(
    String partnerId,
    List<PartnerConnectionItem> fromDoctor,
    List<PartnerConnectionItem> sentByPartner,
  ) {
    if (ResponsiveLayout.isCompact(context)) {
      return _buildAddDoctorMobileContent(partnerId, fromDoctor, sentByPartner);
    }

    final connectedCount = _results.where((d) => widget.isConnected(d.id)).length;
    final cityLabel = widget.cityFilter();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ResponsiveLayout.isCompact(context) ? 16 : 24,
        20,
        ResponsiveLayout.isCompact(context) ? 16 : 24,
        32,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Find doctors on DoctorNect',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                cityLabel == null
                    ? '${_results.length} registered Â· $connectedCount connected Â· ${fromDoctor.length} requests Â· ${sentByPartner.length} pending'
                    : '${_results.length} in $cityLabel Â· $connectedCount connected Â· ${fromDoctor.length} requests Â· ${sentByPartner.length} pending',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                softWrap: true,
              ),
              const SizedBox(height: 16),
              _buildInviteDoctorCard(),
              const SizedBox(height: 16),
              _buildSearchBar(),
              if (fromDoctor.isNotEmpty) ...[
                const SizedBox(height: 24),
                _PartnerAddDoctorSectionHeader(
                  title: 'Connection requests',
                  count: fromDoctor.length,
                  subtitle: 'Doctors that want to connect with your ${widget.partnerTypeLabel}',
                ),
                const SizedBox(height: 10),
                _PartnerAddDoctorTable(
                  columnWidths: const [220, 120, 180],
                  headers: const ['Doctor', 'Requested', 'Action'],
                  children: fromDoctor.map((c) {
                    return _PartnerAddDoctorTableRow(
                      columnWidths: const [220, 120, 180],
                      cells: [
                        _PartnerDoctorNameCell(name: c.doctorName),
                        Text(
                          DateFormat('dd MMM yyyy').format(c.requestedAt),
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                widget.onRejectConnection(c.id, c.doctorName);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Declined ${partnerDoctorLabel(c.doctorName)}')),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: () {
                                widget.onApproveConnection(c.id, c.doctorName);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Connected with ${partnerDoctorLabel(c.doctorName)}'),
                                    backgroundColor: widget.accentColor,
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: widget.accentColor,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
              if (sentByPartner.isNotEmpty) ...[
                const SizedBox(height: 24),
                _PartnerAddDoctorSectionHeader(
                  title: 'Pending invites',
                  count: sentByPartner.length,
                  subtitle: 'Waiting for doctor approval',
                ),
                const SizedBox(height: 10),
                _PartnerAddDoctorTable(
                  columnWidths: const [220, 120, 180],
                  headers: const ['Doctor', 'Sent', 'Action'],
                  children: sentByPartner.map((c) {
                    return _PartnerAddDoctorTableRow(
                      columnWidths: const [220, 120, 180],
                      cells: [
                        _PartnerDoctorNameCell(name: c.doctorName),
                        Text(
                          DateFormat('dd MMM yyyy').format(c.requestedAt),
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
                        ),
                        DoctorInviteActionButton(
                          isPending: true,
                          accentColor: widget.accentColor,
                          onInvite: () {},
                          onRevoke: () {
                            widget.onRevokeConnection(c.id, c.doctorName);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Invite revoked for ${partnerDoctorLabel(c.doctorName)}')),
                            );
                          },
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 24),
              _PartnerAddDoctorSectionHeader(
                title: 'Registered doctors',
                count: _results.length,
                subtitle: cityLabel == null
                    ? 'Search and send an invite to connect'
                    : 'Doctors registered in $cityLabel â€” search and send an invite',
              ),
              const SizedBox(height: 10),
              _buildRegisteredDoctorsList(partnerId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddDoctorMobileContent(
    String partnerId,
    List<PartnerConnectionItem> fromDoctor,
    List<PartnerConnectionItem> sentByPartner,
  ) {
    final connectedCount = _results.where((d) => widget.isConnected(d.id)).length;
    final cityLabel = widget.cityFilter();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _PartnerAddDoctorMobileHeader(
          registered: _results.length,
          connected: connectedCount,
          requests: fromDoctor.length,
          pending: sentByPartner.length,
          cityLabel: cityLabel,
          accentColor: widget.accentColor,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildSearchBar(compact: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildInviteDoctorCard(compact: true),
        ),
        if (fromDoctor.isNotEmpty) ...[
          const SizedBox(height: 20),
          _PartnerMobileSectionLabel(title: 'Connection requests', count: fromDoctor.length),
          const SizedBox(height: 8),
          ...fromDoctor.map((c) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _PartnerConnectionRequestMobileCard(
                  connection: c,
                  accentColor: widget.accentColor,
                  onApprove: () => widget.onApproveConnection(c.id, c.doctorName),
                  onReject: () => widget.onRejectConnection(c.id, c.doctorName),
                ),
              )),
        ],
        if (sentByPartner.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PartnerMobileSectionLabel(title: 'Pending invites', count: sentByPartner.length),
          const SizedBox(height: 8),
          ...sentByPartner.map((c) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _PartnerPendingInviteMobileCard(
                  connection: c,
                  accentColor: widget.accentColor,
                  onRevoke: () => widget.onRevokeConnection(c.id, c.doctorName),
                ),
              )),
        ],
        const SizedBox(height: 10),
        _PartnerMobileSectionLabel(title: 'Registered doctors', count: _results.length),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: _buildRegisteredDoctorsList(partnerId),
        ),
      ],
    );
  }

  Widget _buildRegisteredDoctorsList(String partnerId) {
    final cityLabel = widget.cityFilter();

    if (_results.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _lineColor),
        ),
        child: Column(
          children: [
            Icon(Icons.person_search_outlined, size: 40, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.45)),
            const SizedBox(height: 10),
            Text(
              cityLabel == null ? 'No doctors found' : 'No doctors in $cityLabel',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              cityLabel == null
                  ? 'Try a different name, clinic, or registration number.'
                  : 'Only doctors registered in your city are shown. Try a different search or check back later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      );
    }

    if (ResponsiveLayout.isCompact(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _lineColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              for (var i = 0; i < _results.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: _lineColor),
                _PartnerRegisteredDoctorMobileTile(
                  doctor: _results[i],
                  accentColor: widget.accentColor,
                  isConnected: widget.isConnected(_results[i].id),
                  isPendingSent: widget.isPendingSent(_results[i].id),
                  isPendingFromDoctor: widget.isPendingFromDoctor(_results[i].id),
                  onSendRequest: () => _sendRequest(_results[i]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _PartnerAddDoctorTable(
      columnWidths: const [180, 140, 110, 110, 100],
      headers: const ['Doctor', 'Specialization', 'Clinic', 'Reg. No.', 'Status'],
      children: _results.map((d) {
        return _PartnerAddDoctorTableRow(
          columnWidths: const [180, 140, 110, 110, 100],
          cells: [
            _PartnerDoctorNameCell(name: d.name, subtitle: d.clinicName.isNotEmpty ? d.clinicName : null),
            Text(
              d.specialization.isNotEmpty ? d.specialization : '—',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
            Text(
              d.clinicName.isNotEmpty ? d.clinicName : '—',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
            Text(
              (d.councilNumber != null && d.councilNumber!.isNotEmpty) ? d.councilNumber! : '—',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context)),
            ),
            _PartnerDoctorAction(
              doctor: d,
              accentColor: widget.accentColor,
              isConnected: widget.isConnected(d.id),
              isPendingSent: widget.isPendingSent(d.id),
              isPendingFromDoctor: widget.isPendingFromDoctor(d.id),
              onSendRequest: () => _sendRequest(d),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _PartnerSectionHeader extends StatelessWidget {
  const _PartnerSectionHeader({required this.title, required this.count});

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
            color: _headerBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _lineColor),
          ),
          child: Text('$count', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _PartnerConnectionTile extends StatelessWidget {
  const _PartnerConnectionTile({
    required this.connection,
    required this.subtitle,
    required this.accentColor,
    required this.onRemove,
  });

  final PartnerConnectionItem connection;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accentColor.withValues(alpha: 0.12),
            foregroundColor: accentColor,
            child: Text(
              partnerDoctorInitial(connection.doctorName),
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerDoctorLabel(connection.doctorName),
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.link_off, size: 20, color: AppColors.error),
            onPressed: () async {
              final confirmed = await showConfirmDeleteDialog(
                context,
                title: 'Disconnect Doctor',
                message: 'Are you sure you want to disconnect from ${partnerDoctorLabel(connection.doctorName)}?',
                confirmLabel: 'Disconnect',
              );
              if (confirmed) onRemove();
            },
          ),
        ],
      ),
    );
  }
}

class _PartnerAddDoctorSectionHeader extends StatelessWidget {
  const _PartnerAddDoctorSectionHeader({
    required this.title,
    required this.count,
    this.subtitle,
  });

  final String title;
  final int count;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: _headerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _lineColor),
              ),
              child: Text('$count', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ],
    );
  }
}

class _PartnerAddDoctorTable extends StatelessWidget {
  const _PartnerAddDoctorTable({
    required this.columnWidths,
    required this.headers,
    required this.children,
  });

  final List<double> columnWidths;
  final List<String> headers;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: _headerBg,
              child: Row(
                children: [
                  for (var i = 0; i < headers.length; i++)
                    Expanded(
                      flex: (columnWidths[i]).toInt(),
                      child: Text(
                        headers[i],
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondaryOf(context)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _lineColor),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('None', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondaryOf(context))),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _PartnerAddDoctorTableRow extends StatelessWidget {
  const _PartnerAddDoctorTableRow({required this.columnWidths, required this.cells});

  final List<double> columnWidths;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: (columnWidths[i]).toInt(),
              child: cells[i],
            ),
        ],
      ),
    );
  }
}

class _PartnerDoctorNameCell extends StatelessWidget {
  const _PartnerDoctorNameCell({required this.name, this.subtitle});

  final String name;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.doctorBlue.withValues(alpha: 0.1),
          foregroundColor: AppColors.doctorBlue,
          child: Text(
            partnerDoctorInitial(name),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                partnerDoctorLabel(name),
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartnerAddDoctorMobileHeader extends StatelessWidget {
  const _PartnerAddDoctorMobileHeader({
    required this.registered,
    required this.connected,
    required this.requests,
    required this.pending,
    required this.accentColor,
    this.cityLabel,
  });

  final int registered;
  final int connected;
  final int requests;
  final int pending;
  final Color accentColor;
  final String? cityLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: const Border(bottom: BorderSide(color: _lineColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Find doctors on DoctorNect', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            cityLabel == null
                ? 'Doctors registered on DoctorNect â€” connect or invite'
                : 'Doctors registered in $cityLabel â€” connect or invite',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PartnerMobileStatChip(label: 'Registered', count: registered, color: AppColors.doctorBlue),
                const SizedBox(width: 8),
                _PartnerMobileStatChip(label: 'Connected', count: connected, color: accentColor),
                if (requests > 0) ...[
                  const SizedBox(width: 8),
                  _PartnerMobileStatChip(label: 'Requests', count: requests, color: Colors.orange),
                ],
                if (pending > 0) ...[
                  const SizedBox(width: 8),
                  _PartnerMobileStatChip(label: 'Pending', count: pending, color: Colors.amber.shade700),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerMobileStatChip extends StatelessWidget {
  const _PartnerMobileStatChip({required this.label, required this.count, required this.color});

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _PartnerMobileSectionLabel extends StatelessWidget {
  const _PartnerMobileSectionLabel({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _headerBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _lineColor),
            ),
            child: Text('$count', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _PartnerConnectionRequestMobileCard extends StatelessWidget {
  const _PartnerConnectionRequestMobileCard({
    required this.connection,
    required this.accentColor,
    required this.onApprove,
    required this.onReject,
  });

  final PartnerConnectionItem connection;
  final Color accentColor;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PartnerDoctorNameCell(name: connection.doctorName),
          const SizedBox(height: 8),
          Text(
            'Requested: ${DateFormat('dd MMM yyyy').format(connection.requestedAt)}',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartnerPendingInviteMobileCard extends StatelessWidget {
  const _PartnerPendingInviteMobileCard({
    required this.connection,
    required this.accentColor,
    required this.onRevoke,
  });

  final PartnerConnectionItem connection;
  final Color accentColor;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PartnerDoctorNameCell(name: connection.doctorName),
                const SizedBox(height: 4),
                Text(
                  'Sent: ${DateFormat('dd MMM yyyy').format(connection.requestedAt)}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                ),
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

class _PartnerRegisteredDoctorMobileTile extends StatelessWidget {
  const _PartnerRegisteredDoctorMobileTile({
    required this.doctor,
    required this.accentColor,
    required this.isConnected,
    required this.isPendingSent,
    required this.isPendingFromDoctor,
    required this.onSendRequest,
  });

  final RegisteredDoctorSearchResult doctor;
  final Color accentColor;
  final bool isConnected;
  final bool isPendingSent;
  final bool isPendingFromDoctor;
  final VoidCallback onSendRequest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PartnerDoctorNameCell(name: doctor.name),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    if (doctor.specialization.isNotEmpty)
                      Text(doctor.specialization, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                    if (doctor.clinicName.isNotEmpty)
                      Text('• ${doctor.clinicName}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PartnerDoctorAction(
            doctor: doctor,
            accentColor: accentColor,
            isConnected: isConnected,
            isPendingSent: isPendingSent,
            isPendingFromDoctor: isPendingFromDoctor,
            onSendRequest: onSendRequest,
          ),
        ],
      ),
    );
  }
}

class _PartnerDoctorAction extends StatelessWidget {
  const _PartnerDoctorAction({
    required this.doctor,
    required this.accentColor,
    required this.isConnected,
    required this.isPendingSent,
    required this.isPendingFromDoctor,
    required this.onSendRequest,
  });

  final RegisteredDoctorSearchResult doctor;
  final Color accentColor;
  final bool isConnected;
  final bool isPendingSent;
  final bool isPendingFromDoctor;
  final VoidCallback onSendRequest;

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      return _PartnerStatusPill(label: 'Connected', color: accentColor);
    }
    if (isPendingSent) {
      return const _PartnerStatusPill(label: 'Pending', color: Colors.amber);
    }
    if (isPendingFromDoctor) {
      return const _PartnerStatusPill(label: 'Requested', color: Colors.orange);
    }
    return FilledButton(
      onPressed: onSendRequest,
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _PartnerStatusPill extends StatelessWidget {
  const _PartnerStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}