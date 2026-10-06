import 'pauses.dart';

enum ShiftOrigin { manual, timer, gps }

class ShiftRecord {
  ShiftRecord({required this.id, required this.start, this.end,
    this.origin = ShiftOrigin.manual}) {
    if (end != null && !end!.isAfter(start)) {
      throw const FormatException('Das Schichtende muss nach dem Anfang liegen.');
    }
  }
  final String id;
  final DateTime start;
  final DateTime? end;
  final ShiftOrigin origin;
  bool get running => end == null;
  ShiftRecord finish(DateTime at) => ShiftRecord(id: id, start: start, end: at, origin: origin);
  Map<String, dynamic> toJson() => {'id': id, 'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(), 'origin': origin.name};
  factory ShiftRecord.fromJson(Map<String, dynamic> json) => ShiftRecord(
    id: json['id'] as String, start: DateTime.parse(json['start'] as String),
    end: json['end'] == null ? null : DateTime.parse(json['end'] as String),
    origin: ShiftOrigin.values.byName(json['origin'] as String? ?? 'manual'));
}

void validateShift(Iterable<ShiftRecord> shifts, ShiftRecord next) {
  final until = next.end ?? DateTime.utc(2200);
  for (final other in shifts.where((s) => s.id != next.id)) {
    if (next.start.isBefore(other.end ?? DateTime.utc(2200)) && until.isAfter(other.start)) {
      throw const FormatException('Schichten dürfen sich nicht überschneiden. Bitte Anfang und Ende prüfen.');
    }
  }
}

typedef TimeInterval = (DateTime, DateTime);

List<TimeInterval> mergeIntervals(Iterable<TimeInterval> input) {
  final sorted = input.where((v) => v.$2.isAfter(v.$1)).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final result = <TimeInterval>[];
  for (final item in sorted) {
    if (result.isEmpty || item.$1.isAfter(result.last.$2)) {
      result.add(item);
    } else if (item.$2.isAfter(result.last.$2)) {
      result[result.length - 1] = (result.last.$1, item.$2);
    }
  }
  return result;
}

Duration intervalDuration(Iterable<TimeInterval> intervals) =>
  intervals.fold(Duration.zero, (sum, item) => sum + item.$2.difference(item.$1));

class WorkTotals {
  const WorkTotals(this.gross, this.breaks, this.credited);
  final Duration gross;
  final Duration breaks;
  final Duration credited;
  Duration get net => gross - breaks;
}

// Only recorded breaks inside a shift reduce actual work. No assumed deduction.
WorkTotals workTotals(Iterable<ShiftRecord> shifts, Iterable<PauseRecord> pauses,
    DateTime from, DateTime until, DateTime now) {
  final intervals = mergeIntervals(shifts.map((s) => (
    s.start.isBefore(from) ? from : s.start,
    (s.end ?? now).isAfter(until) ? until : (s.end ?? now))));
  final breakIntervals = mergeIntervals([
    for (final shift in intervals)
      for (final pause in pauses)
        (pause.start.isBefore(shift.$1) ? shift.$1 : pause.start,
          (pause.end ?? now).isAfter(shift.$2) ? shift.$2 : (pause.end ?? now)),
  ]);
  var credited = Duration.zero;
  // Requested short-shift credit is separate from actual working time.
  // Split the result by overlap while deciding the rule from the entire shift.
  for (final shift in shifts) {
    final start = shift.start.isBefore(from) ? from : shift.start;
    final actualEnd = shift.end ?? now;
    final end = actualEnd.isAfter(until) ? until : actualEnd;
    if (!end.isAfter(start)) continue;
    final breaks = intervalDuration(mergeIntervals(pauses.map((p) => (
      p.start.isBefore(start) ? start : p.start,
      (p.end ?? now).isAfter(end) ? end : (p.end ?? now)))));
    credited += end.difference(start) -
      (actualEnd.difference(shift.start) < const Duration(hours: 6) ? Duration.zero : breaks);
  }
  final gross = intervalDuration(intervals);
  // Overlapping legacy/cross-device entries must never inflate totals.
  if (credited > gross) credited = gross;
  return WorkTotals(gross, intervalDuration(breakIntervals), credited);
}

WorkTotals workTotalsForDay(Iterable<ShiftRecord> shifts, Iterable<PauseRecord> pauses,
    DateTime day, DateTime now) => workTotals(shifts, pauses,
      DateTime(day.year, day.month, day.day), DateTime(day.year, day.month, day.day + 1), now);

String? workWarning(WorkTotals totals) {
  if (totals.gross >= const Duration(hours: 12)) {
    return '12-Stunden-Schicht erreicht. Bitte Schicht beenden und Arbeitszeit prüfen.';
  }
  if (totals.net >= const Duration(hours: 10)) {
    return '10 Stunden Arbeitszeit erreicht. Allgemeine Höchstgrenze nach ArbZG; mögliche Sonderregelungen prüfen.';
  }
  if (totals.net > const Duration(hours: 8)) {
    return 'Mehr als 8 Stunden Arbeitszeit. Eine Verlängerung bis 10 Stunden ist grundsätzlich nur mit Ausgleich zulässig.';
  }
  return null;
}

Duration requiredRecordedBreak(Duration work) => work > const Duration(hours: 9)
  ? const Duration(minutes: 45) : work > const Duration(hours: 6)
  ? const Duration(minutes: 30) : Duration.zero;
