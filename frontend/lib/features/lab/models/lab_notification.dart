class LabNotification {
  LabNotification({
    required this.id,
    required this.labId,
    required this.title,
    required this.message,
    required this.createdAt,
    this.referenceId,
    this.isRead = false,
  });

  final String id;
  final String labId;
  final String title;
  final String message;
  final DateTime createdAt;
  final String? referenceId;
  bool isRead;
}
