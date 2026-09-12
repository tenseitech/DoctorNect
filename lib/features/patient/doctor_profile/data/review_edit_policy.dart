abstract final class ReviewEditPolicy {
  ReviewEditPolicy._();

  static const editWindow = Duration(hours: 48);

  static bool withinEditWindow(DateTime createdAt, [DateTime? now]) {
    final clock = now ?? DateTime.now();
    return clock.difference(createdAt) <= editWindow;
  }
}
