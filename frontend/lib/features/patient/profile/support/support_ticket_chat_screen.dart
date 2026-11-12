import '../../../../core/notifications/app_toast.dart';

import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/session/patient_session.dart';
import '../../../../core/supabase/support_ticket_supabase_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

class _ChatMessageItemData {
  const _ChatMessageItemData({
    required this.senderRole,
    required this.senderName,
    required this.text,
    this.createdAt,
  });

  final String senderRole;
  final String senderName;
  final String text;
  final DateTime? createdAt;
}

class SupportTicketChatScreen extends StatefulWidget {
  final String ticketId;
  final String issueType;
  final String message;
  final String status;
  final String? screenshot;
  final DateTime createdAt;

  const SupportTicketChatScreen({
    super.key,
    required this.ticketId,
    required this.issueType,
    required this.message,
    required this.status,
    this.screenshot,
    required this.createdAt,
  });

  @override
  State<SupportTicketChatScreen> createState() =>
      _SupportTicketChatScreenState();
}

class _SupportTicketChatScreenState extends State<SupportTicketChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    try {
      final senderId = PatientSession.loggedInPatientId.isNotEmpty
          ? PatientSession.loggedInPatientId
          : (FirebaseAuth.instance.currentUser?.uid ?? 'patient');
      await SupportTicketSupabaseRepository.instance.sendMessage(
        ticketId: widget.ticketId,
        senderId: senderId,
        senderName: 'You',
        senderRole: 'patient',
        text: text,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      AppToast.info(context, 'Failed to send message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    Color statusBg;
    switch (widget.status.toLowerCase()) {
      case 'resolved':
        statusColor = const Color(0xFF2E7D32);
        statusBg = const Color(0xFFE8F5E9);
        break;
      case 'in_progress':
        statusColor = const Color(0xFFE65100);
        statusBg = const Color(0xFFFFF3E0);
        break;
      default:
        statusColor = const Color(0xFF1565C0);
        statusBg = const Color(0xFFE3F2FD);
    }

    final formattedTicketId = widget.ticketId
        .substring(0, min(8, widget.ticketId.length))
        .toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'Ticket #$formattedTicketId',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: AppTypography.headlineSmall,
              ),
            ),
            Text(
              widget.issueType,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.status.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
        ],
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = PatientProfileFormStyles.resolveContentWidth(
            context,
            constraints,
          );

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                children: [
                  // Ticket Original Info Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Original Request',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(widget.createdAt),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.message,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.4,
                          ),
                        ),
                        if (widget.screenshot != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.attach_file,
                                size: 12,
                                color: AppColors.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.screenshot!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Chat Messages Area
                  Expanded(
                    child: _buildSupabaseMessages(constraints),
                  ),

                  // Message Input Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          offset: const Offset(0, -2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Type your message...',
                                hintStyle: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: AppTypography.bodyMedium,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color: AppColors.borderOf(context),
                                    width: 1,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: AppColors.patientTeal,
                            child: IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: _sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSupabaseMessages(BoxConstraints constraints) {
    return StreamBuilder<List<TicketMessageModel>>(
      stream: SupportTicketSupabaseRepository.instance
          .watchTicketMessages(widget.ticketId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.patientTeal),
          );
        }

        final messages = (snapshot.data ?? [])
            .map((m) => _ChatMessageItemData(
                  senderRole: m.senderRole,
                  senderName: m.senderName,
                  text: m.text,
                  createdAt: m.createdAt,
                ))
            .toList();

        if (messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        return _buildMessagesList(messages, constraints);
      },
    );
  }


  Widget _buildMessagesList(
    List<_ChatMessageItemData> messages,
    BoxConstraints constraints,
  ) {
    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Text(
            'No messages yet. Send a message to start conversation.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.bodySmall,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msgData = messages[index];
        final isMe = msgData.senderRole == 'patient';
        final senderName = msgData.senderName;
        final text = msgData.text;
        final timestamp = msgData.createdAt;

        final timeLabel = timestamp != null
            ? DateFormat('hh:mm a').format(timestamp)
            : 'Sending...';

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * 0.75,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.patientTeal
                  : AppColors.surfaceOf(context),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isMe ? 14 : 2),
                bottomRight: Radius.circular(isMe ? 2 : 14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  offset: const Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
              border: isMe
                  ? null
                  : Border.all(
                      color: AppColors.borderOf(context),
                      width: 0.5,
                    ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Text(
                    senderName,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.patientTeal,
                    ),
                  ),
                if (!isMe) const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: AppTypography.bodySmall,
                    color: isMe ? Colors.white : AppColors.textPrimaryOf(context),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
