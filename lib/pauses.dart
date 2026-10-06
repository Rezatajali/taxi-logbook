enum PauseOrigin { timer, manual, gps }

const gpsPauseThreshold = Duration(minutes: 15);
bool qualifiesAsGpsPause(Duration stopped) => stopped > gpsPauseThreshold;

class PauseRecord {
  PauseRecord({required this.id, required this.start, this.end,
    this.origin = PauseOrigin.manual}) {
    if (end != null && !end!.isAfter(start)) {
      throw const FormatException('Das Ende muss nach dem Beginn liegen.');
    }
  }
  final String id;
  final DateTime start;
  final DateTime? end;
  final PauseOrigin origin;
  bool get running => end == null;
  Map<String, dynamic> toJson() => {'id': id, 'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(), 'origin': origin.name};
  factory PauseRecord.fromJson(Map<String, dynamic> json) => PauseRecord(
    id: json['id'] as String, start: DateTime.parse(json['start'] as String),
    end: json['end'] == null ? null : DateTime.parse(json['end'] as String),
    origin: PauseOrigin.values.byName(json['origin'] as String? ?? 'manual'));
  PauseRecord finish(DateTime at) => PauseRecord(id: id, start: start, end: at, origin: origin);
}

// Clip to the selected local day and merge overlaps to avoid double counting.
Duration pauseDurationForDay(Iterable<PauseRecord> pauses, DateTime day, DateTime now) {
  final from = DateTime(day.year, day.month, day.day);
  final until = DateTime(day.year, day.month, day.day + 1);
  final intervals = <(DateTime, DateTime)>[];
  for (final pause in pauses) {
    final start = pause.start.isBefore(from) ? from : pause.start;
    final actualEnd = pause.end ?? now;
    final end = actualEnd.isAfter(until) ? until : actualEnd;
    if (end.isAfter(start)) intervals.add((start, end));
  }
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  var total = Duration.zero;
  DateTime? start, end;
  for (final interval in intervals) {
    if (end == null || interval.$1.isAfter(end)) {
      if (end != null) total += end.difference(start!);
      start = interval.$1;
      end = interval.$2;
    } else if (interval.$2.isAfter(end)) {
      end = interval.$2;
    }
  }
  return end == null ? total : total + end.difference(start!);
}
