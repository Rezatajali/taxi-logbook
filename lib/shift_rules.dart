import 'logbook.dart';
import 'shifts.dart';

/// Shift rules for taxi drivers:
/// - a shift lasts at most 12 hours; up to 1 extra hour is tolerated,
///   after 13 hours it is closed automatically;
/// - after a shift there must be at least 11 hours of rest.
const maxShiftLength = Duration(hours: 12);
const shiftTolerance = Duration(hours: 1);
const minRest = Duration(hours: 11);

/// Latest regular end of a shift (start + 12 h).
DateTime shiftLatestEnd(ShiftRecord shift) => shift.start.add(maxShiftLength);

/// Hard limit: after start + 13 h the shift is closed.
DateTime shiftHardEnd(ShiftRecord shift) => shift.start.add(maxShiftLength + shiftTolerance);

/// End of the most recent finished shift that started before [now].
DateTime? lastShiftEnd(Iterable<ShiftRecord> shifts, DateTime now) {
  DateTime? result;
  for (final s in shifts) {
    final end = s.end;
    if (end != null && !end.isAfter(now) && (result == null || end.isAfter(result))) result = end;
  }
  return result;
}

/// When the 11-hour rest after the last shift is over (null = no rest pending).
DateTime? restUntil(Iterable<ShiftRecord> shifts, DateTime now) {
  final end = lastShiftEnd(shifts, now);
  if (end == null) return null;
  final until = end.add(minRest);
  return until.isAfter(now) ? until : null;
}

/// For a running shift past the 13-hour limit: the end to record. That is the
/// last fare inside the shift (at most start + 13 h), otherwise start + 12 h.
DateTime? automaticShiftEnd(ShiftRecord shift, Iterable<Trip> trips, DateTime now) {
  if (!shift.running || !now.isAfter(shiftHardEnd(shift))) return null;
  final hard = shiftHardEnd(shift);
  DateTime? lastFare;
  for (final t in trips) {
    if (t.deleted || t.at.isBefore(shift.start) || t.at.isAfter(hard)) continue;
    if (lastFare == null || t.at.isAfter(lastFare)) lastFare = t.at;
  }
  final end = lastFare != null && lastFare.isAfter(shift.start)
      ? lastFare : shiftLatestEnd(shift);
  return end;
}
