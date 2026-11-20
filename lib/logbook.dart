import 'shifts.dart';

enum PaymentMethod {
  cash('Bar'),
  card('Karte'),
  platform('Über Plattform'),
  invoice('Rechnung');

  const PaymentMethod(this.label);
  final String label;
}

// Quick choices combine source/payment for fast entry, while records still
// retain the two independent fields for accurate cash and platform reports.
class FareType {
  const FareType(this.label, this.source, this.payment);
  final String label;
  final String source;
  final PaymentMethod payment;
  bool matches(String source, PaymentMethod payment) =>
      this.source == source && this.payment == payment;
}

const fareTypes = [
  FareType('Bar', 'Taxi', PaymentMethod.cash),
  FareType('Uber', 'Uber', PaymentMethod.platform),
  FareType('Uber Bar', 'Uber', PaymentMethod.cash),
  FareType('Karte', 'Taxi', PaymentMethod.card),
  FareType('Rechnung', 'Taxi', PaymentMethod.invoice),
  FareType('Bolt', 'Bolt', PaymentMethod.platform),
  FareType('FREENOW', 'FREENOW', PaymentMethod.platform),
];

// Store money as whole cents. Never add currency using floating point.
int? parseCents(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final result = int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return result > 0 ? result : null;
}

double? parseKilometers(String input) {
  if (input.trim().isEmpty) return null;
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  return value != null && value.isFinite && value > 0 && value <= 10000
      ? value
      : null;
}

class Trip {
  const Trip({
    required this.id,
    required this.at,
    required this.cents,
    required this.source,
    required this.payment,
    this.tipCents = 0,
    this.kilometers,
    this.note = '',
    this.editedAt,
    this.deletedAt,
    this.history = const [],
  });

  final String id;
  final DateTime at;
  final int cents;
  final int tipCents;
  final String source;
  final PaymentMethod payment;
  final double? kilometers;
  final String note;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final List<Map<String, dynamic>> history;
  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'cents': cents,
        'tipCents': tipCents,
        'source': source,
        'payment': payment.name,
        'kilometers': kilometers,
        'note': note,
        'editedAt': editedAt?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'history': history,
      };

  factory Trip.fromJson(Map<String, dynamic> json) {
    final cents = json['cents'] as int;
    final tipCents = json['tipCents'] as int? ?? 0;
    final kilometers = (json['kilometers'] as num?)?.toDouble();
    if (cents <= 0 || tipCents < 0 || tipCents > 99999999 ||
        (kilometers != null &&
            (!kilometers.isFinite || kilometers <= 0 || kilometers > 10000))) {
      throw const FormatException('Ungültige Fahrtdaten.');
    }
    return Trip(
      id: json['id'] as String,
      at: DateTime.parse(json['at'] as String),
      cents: cents,
      tipCents: tipCents,
      source: json['source'] as String,
      payment: PaymentMethod.values.byName(json['payment'] as String),
      kilometers: kilometers,
      note: json['note'] as String? ?? '',
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      history: List<Map<String, dynamic>>.unmodifiable((json['history'] as List? ?? []).map((entry) => Map<String, dynamic>.from(entry as Map))),
    );
  }
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A forgotten running shift must not pull fares of later days into it.
const maxOpenShift = Duration(hours: 24);

/// The working day a fare belongs to: the local start day of the shift that
/// contains it. A fare at 01:00 in a shift that started at 17:00 counts for the
/// evening before. Fares outside any shift use their own calendar day.
DateTime workDayOf(DateTime at, Iterable<ShiftRecord> shifts) {
  for (final shift in shifts) {
    final end = shift.end ?? shift.start.add(maxOpenShift);
    if (!at.isBefore(shift.start) && !at.isAfter(end)) {
      final start = shift.start.toLocal();
      return DateTime(start.year, start.month, start.day);
    }
  }
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}

List<Trip> tripsOnDay(Iterable<Trip> trips, DateTime day,
    [Iterable<ShiftRecord> shifts = const []]) =>
    trips.where((t) => sameDay(workDayOf(t.at, shifts), day)).toList();

List<Trip> tripsInMonth(Iterable<Trip> trips, DateTime month,
    [Iterable<ShiftRecord> shifts = const []]) => trips.where((t) {
      final day = workDayOf(t.at, shifts);
      return day.year == month.year && day.month == month.month;
    }).toList();

class TripSummary {
  TripSummary(Iterable<Trip> input, {Iterable<ShiftRecord> shifts = const []})
      : trips = List.unmodifiable(input.where((trip) => !trip.deleted)),
        shifts = List.unmodifiable(shifts);
  final List<Trip> trips;
  /// Used to count fares after midnight for the day their shift started.
  final List<ShiftRecord> shifts;
  DateTime dayOf(Trip trip) => workDayOf(trip.at, shifts);

  int get totalCents => trips.fold(0, (sum, trip) => sum + trip.cents);
  int get tipCents => trips.fold(0, (sum, trip) => sum + trip.tipCents);
  int get receivedCents => totalCents + tipCents;
  static bool _isUberCash(Trip t) =>
      t.payment == PaymentMethod.cash && t.source == 'Uber';
  /// Cash fares without Uber cash ("Uber Bar" is reported on its own).
  int get cashCents => trips
      .where((t) => t.payment == PaymentMethod.cash && !_isUberCash(t))
      .fold(0, (sum, trip) => sum + trip.cents);
  int get uberCashCents => trips
      .where(_isUberCash)
      .fold(0, (sum, trip) => sum + trip.cents);

  /// Payment breakdown for reports: "Bar" and "Uber Bar" are separate rows.
  Map<String, int> get paymentBreakdown => {
        PaymentMethod.cash.label: cashCents,
        'Uber Bar': uberCashCents,
        for (final method in PaymentMethod.values)
          if (method != PaymentMethod.cash) method.label: byPayment[method]!,
      };
  int get workingDays => trips
      .map(dayOf)
      .toSet()
      .length;
  double get averageWorkingDayCents =>
      workingDays == 0 ? 0 : totalCents / workingDays;
  int get tripsWithDistance => trips.where((t) => t.kilometers != null).length;
  double get totalKilometers =>
      trips.fold(0, (sum, trip) => sum + (trip.kilometers ?? 0));

  // Missing distances must not inflate revenue/km. Only include matching
  // revenue and distance from the same measured trips.
  double? get eurosPerKilometer {
    if (totalKilometers == 0) return null;
    final measuredCents = trips
        .where((t) => t.kilometers != null)
        .fold(0, (sum, trip) => sum + trip.cents);
    return measuredCents / 100 / totalKilometers;
  }

  /// Tips per source (Uber, Bolt, Taxi …), only sources with tips.
  Map<String, int> get tipsBySource {
    final result = <String, int>{};
    for (final trip in trips.where((t) => t.tipCents > 0)) {
      result.update(trip.source, (v) => v + trip.tipCents, ifAbsent: () => trip.tipCents);
    }
    return result;
  }

  Map<String, int> get bySource {
    final result = <String, int>{};
    for (final trip in trips) {
      result.update(trip.source, (v) => v + trip.cents,
          ifAbsent: () => trip.cents);
    }
    return result;
  }

  Map<PaymentMethod, int> get byPayment => {
        for (final method in PaymentMethod.values)
          method: trips
              .where((t) => t.payment == method)
              .fold(0, (sum, t) => sum + t.cents),
      };

  List<int> dailyCents(DateTime month) {
    final days = List<int>.filled(DateTime(month.year, month.month + 1, 0).day, 0);
    for (final trip in tripsInMonth(trips, month, shifts)) {
      days[dayOf(trip).day - 1] += trip.cents;
    }
    return days;
  }
}


// Flat snapshots retain the old values without recursively nesting history.
Trip reviseTrip(Trip? previous, Trip next, {DateTime? now}) {
  if (previous == null) return next;
  if (previous.deleted) throw StateError('Gelöschte Fahrt kann nicht bearbeitet werden.');
  if (previous.at == next.at && previous.cents == next.cents && previous.tipCents == next.tipCents &&
      previous.source == next.source && previous.payment == next.payment &&
      previous.kilometers == next.kilometers && previous.note == next.note) {
    return previous;
  }
  final changed = now ?? DateTime.now().toUtc();
  final snapshot = previous.toJson()..remove('history');
  snapshot['action'] = 'Bearbeitet';
  snapshot['changedAt'] = changed.toIso8601String();
  return Trip.fromJson({...next.toJson(), 'editedAt': changed.toIso8601String(),
    'history': [...previous.history, snapshot]});
}

Trip markTripDeleted(Trip previous, {DateTime? now}) {
  if (previous.deleted) return previous;
  final changed = now ?? DateTime.now().toUtc();
  final snapshot = previous.toJson()..remove('history');
  snapshot['action'] = 'Gelöscht';
  snapshot['changedAt'] = changed.toIso8601String();
  return Trip.fromJson({...previous.toJson(), 'deletedAt': changed.toIso8601String(),
    'history': [...previous.history, snapshot]});
}
