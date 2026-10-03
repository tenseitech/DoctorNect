import '../../pharmacy/models/pharmacy_models.dart';

enum LabConnectionRequester { lab, doctor }

class LabConnection {
  LabConnection({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.labId,
    required this.labName,
    required this.status,
    required this.requestedAt,
    required this.requestedBy,
    this.respondedAt,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final String labId;
  final String labName;
  ConnectionStatus status;
  final DateTime requestedAt;
  final LabConnectionRequester requestedBy;
  DateTime? respondedAt;
}
