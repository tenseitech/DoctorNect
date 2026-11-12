/// Result of re-reading DB after an ambiguous lab report persist (RPC throw/timeout).
enum LabReportKeyCheckResult {
  /// Every checked row references [newKey].
  allRowsMatch,

  /// No checked row references [newKey] (safe to delete orphan S3 object).
  noRowsMatch,

  /// Some rows reference [newKey], some do not (partial persist).
  partialMatch,

  /// Could not read DB (network/RLS/error) — do not delete S3 object.
  inconclusive,
}
