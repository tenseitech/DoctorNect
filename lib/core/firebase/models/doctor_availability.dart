class DoctorScheduleAvailability {
  const DoctorScheduleAvailability({
    required this.workingDays,
    required this.morningStart,
    required this.morningEnd,
    required this.eveningEnabled,
    required this.eveningStart,
    required this.eveningEnd,
    required this.slotDurationMins,
    required this.maxPatientsPerDay,
    required this.breakEnabled,
    required this.breakStart,
    required this.breakEnd,
    required this.blockedDates,
    this.leaveStart,
    this.leaveEnd,
  });

  final List<String> workingDays;
  final String morningStart;
  final String morningEnd;
  final bool eveningEnabled;
  final String eveningStart;
  final String eveningEnd;
  final int slotDurationMins;
  final int maxPatientsPerDay;
  final bool breakEnabled;
  final String breakStart;
  final String breakEnd;
  final Set<DateTime> blockedDates;
  final DateTime? leaveStart;
  final DateTime? leaveEnd;

  static DoctorScheduleAvailability defaults() => DoctorScheduleAvailability(
        workingDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        morningStart: '09:00 AM',
        morningEnd: '01:00 PM',
        eveningEnabled: true,
        eveningStart: '04:00 PM',
        eveningEnd: '08:00 PM',
        slotDurationMins: 15,
        maxPatientsPerDay: 20,
        breakEnabled: false,
        breakStart: '01:00 PM',
        breakEnd: '02:00 PM',
        blockedDates: const {},
      );

  DoctorScheduleAvailability copyWith({
    List<String>? workingDays,
    String? morningStart,
    String? morningEnd,
    bool? eveningEnabled,
    String? eveningStart,
    String? eveningEnd,
    int? slotDurationMins,
    int? maxPatientsPerDay,
    bool? breakEnabled,
    String? breakStart,
    String? breakEnd,
    Set<DateTime>? blockedDates,
    DateTime? leaveStart,
    DateTime? leaveEnd,
    bool clearLeave = false,
  }) {
    return DoctorScheduleAvailability(
      workingDays: workingDays ?? this.workingDays,
      morningStart: morningStart ?? this.morningStart,
      morningEnd: morningEnd ?? this.morningEnd,
      eveningEnabled: eveningEnabled ?? this.eveningEnabled,
      eveningStart: eveningStart ?? this.eveningStart,
      eveningEnd: eveningEnd ?? this.eveningEnd,
      slotDurationMins: slotDurationMins ?? this.slotDurationMins,
      maxPatientsPerDay: maxPatientsPerDay ?? this.maxPatientsPerDay,
      breakEnabled: breakEnabled ?? this.breakEnabled,
      breakStart: breakStart ?? this.breakStart,
      breakEnd: breakEnd ?? this.breakEnd,
      blockedDates: blockedDates ?? this.blockedDates,
      leaveStart: clearLeave ? null : (leaveStart ?? this.leaveStart),
      leaveEnd: clearLeave ? null : (leaveEnd ?? this.leaveEnd),
    );
  }
}

typedef DoctorAvailability = DoctorScheduleAvailability;
