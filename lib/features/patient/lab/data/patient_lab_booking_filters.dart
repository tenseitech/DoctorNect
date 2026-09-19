import '../../../../core/firebase/firestore_service.dart';

abstract final class PatientLabBookingFilters {
  PatientLabBookingFilters._();

  static DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool isUpcoming(LabBookingRecord booking) {
    final status = booking.status.toLowerCase();
    if (status == 'completed' ||
        status == 'declined' ||
        status == 'cancelled') {
      return false;
    }

    final today = _dayOnly(DateTime.now());
    final bookingDay = _dayOnly(booking.dateTime);
    return !bookingDay.isBefore(today);
  }

  static bool isHistory(LabBookingRecord booking) => !isUpcoming(booking);

  static List<LabBookingRecord> upcoming(List<LabBookingRecord> all) {
    return all.where(isUpcoming).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  static List<LabBookingRecord> history(List<LabBookingRecord> all) {
    return all.where(isHistory).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }
}
