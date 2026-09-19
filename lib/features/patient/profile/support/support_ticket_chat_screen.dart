import '../../../../core/notifications/app_toast.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/session/patient_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/patient_profile_form_styles.dart';
import '../../../../core/theme/app_typography.dart';

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
  State<SupportTicketChatScreen> createState() => _SupportTicketChatScreenState();
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

    final messageData = {
      'senderId': PatientSession.loggedInPatientId,
      'senderName': 'You',
      'senderRole': 'patient',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(widget.ticketId)
          .collection('messages')
          .add(messageData);

      // Auto scroll
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // Simulate Support Agent response after 1.5s
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        final replies = [
          "Thank you for the update. Our support team is reviewing your ticket and will resolve it as soon as possible.",
          "Got it. We have passed this information to our technical team.",
          "Understood. We are looking into this details right now.",
          "We have noted your query. Is there anything else you'd like to add while we investigate?",
          "We are on it! A support representative will update you shortly.",
        ];
        final replyText = replies[Random().nextInt(replies.length)];

        await FirebaseFirestore.instance
            .collection('support_tickets')
            .doc(widget.ticketId)
            .collection('messages')
            .add({
          'senderId': 'support_agent_mock',
          'senderName': 'Support Agent',
          'senderRole': 'support',
          'text': replyText,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      });
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

    final formattedTicketId = widget.ticketId.substring(0, min(8, widget.ticketId.length)).toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'Ticket #$formattedTicketId',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: AppTypography.headlineSmall),
            ),
            Text(
              widget.issueType,
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
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
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          )
        ],
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = PatientProfileFormStyles.resolveContentWidth(context, constraints);

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
                      border: Border.all(color: AppColors.borderOf(context), width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Original Request',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy, hh:mm a').format(widget.createdAt),
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.message,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.bodySmall,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.4,
                          ),
                        ),
                        if (widget.screenshot != null) ...[
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.attach_file, size: 12, color: AppColors.textSecondaryOf(context)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.screenshot!,
                                  style: GoogleFonts.inter(
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
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('support_tickets')
                          .doc(widget.ticketId)
                          .collection('messages')
                          .orderBy('createdAt', descending: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.patientTeal),
                          );
                        }

                        final messages = snapshot.data?.docs ?? [];

                        // Trigger scroll to bottom on load
                        if (messages.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: messages.isEmpty ? 1 : messages.length,
                          itemBuilder: (context, index) {
                            if (messages.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32.0),
                                child: Center(
                                  child: Text(
                                    'No messages yet. Send a message to start conversation.',
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodySmall,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final msgDoc = messages[index];
                            final msgData = msgDoc.data() as Map<String, dynamic>;
                            final isMe = msgData['senderRole'] == 'patient';
                            final senderName = msgData['senderName'] as String? ?? 'User';
                            final text = msgData['text'] as String? ?? '';
                            final timestamp = msgData['createdAt'] as Timestamp?;

                            final timeLabel = timestamp != null
                                ? DateFormat('hh:mm a').format(timestamp.toDate())
                                : 'Sending...';

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * 0.75,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe ? AppColors.patientTeal : AppColors.surfaceOf(context),
                                  border: isMe
                                      ? null
                                      : Border.all(color: AppColors.borderOf(context), width: 0.5),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: Radius.circular(isMe ? 12 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isMe) ...[
                                      Text(
                                        senderName,
                                        style: GoogleFonts.inter(
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.patientTeal,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                    ],
                                    Text(
                                      text,
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodyMedium,
                                        color: isMe ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        timeLabel,
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          color: isMe ? AppColors.surfaceOf(context).withValues(alpha: 0.7) : AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Message Input Field
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      border: Border(
                        top: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: GoogleFonts.inter(color: AppColors.textSecondaryOf(context), fontSize: AppTypography.bodyMedium),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: AppColors.cardBgOf(context),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: const BoxDecoration(
                            color: AppColors.patientTeal,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: AppColors.white, size: 20),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
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
}
