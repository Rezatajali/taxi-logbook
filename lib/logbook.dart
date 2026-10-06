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
    this.kilometers,
    this.note = '',
    this.editedAt,
    this.deletedAt,
    this.history = const [],
  });

  final String id;
  final DateTime at;
  final int cents;
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
    final kilometers = (json['kilometers'] as num?)?.toDouble();
    if (cents <= 0 ||
        (kilometers != null &&
            (!kilometers.isFinite || kilometers <= 0 || kilometers > 10000))) {
      throw const FormatException('Ungültige Fahrtdaten.');
    }
    return Trip(
      id: json['id'] as String,
      at: DateTime.parse(json['at'] as String),
      cents: cents,
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

List<Trip> tripsInMonth(Iterable<Trip> trips, DateTime month) => trips
    .where((t) => t.at.year == month.year && t.at.month == month.month)
    .toList();

class TripSummary {
  TripSummary(Iterable<Trip> input) : trips = List.unmodifiable(input.where((trip) => !trip.deleted));
  final List<Trip> trips;

  int get totalCents => trips.fold(0, (sum, trip) => sum + trip.cents);
  int get cashCents => trips
      .where((t) => t.payment == PaymentMethod.cash)
      .fold(0, (sum, trip) => sum + trip.cents);
  int get workingDays => trips
      .map((t) => DateTime(t.at.year, t.at.month, t.at.day))
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
    for (final trip in tripsInMonth(trips, month)) {
      days[trip.at.day - 1] += trip.cents;
    }
    return days;
  }
}


// Flat snapshots retain the old values without recursively nesting history.
Trip reviseTrip(Trip? previous, Trip next, {DateTime? now}) {
  if (previous == null) return next;
  if (previous.deleted) throw StateError('Gelöschte Fahrt kann nicht bearbeitet werden.');
  if (previous.at == next.at && previous.cents == next.cents &&
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
