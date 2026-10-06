import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/store.dart';

Trip trip(String id, int cents, DateTime at,
    {String source = 'Uber', PaymentMethod payment = PaymentMethod.cash,
    double? kilometers}) => Trip(id: id, at: at, cents: cents, source: source,
        payment: payment, kilometers: kilometers);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Quick entry preserves separate source/payment data including invoices', () {
    final uber = fareTypes.singleWhere((type) => type.label == 'Uber');
    expect(uber.source, 'Uber');
    expect(uber.payment, PaymentMethod.platform);
    final invoice = fareTypes.singleWhere((type) => type.label == 'Rechnung');
    final saved = trip('invoice', 2270, DateTime(2026, 10, 5),
        source: invoice.source, payment: invoice.payment);
    expect(Trip.fromJson(saved.toJson()).payment, PaymentMethod.invoice);
    expect(TripSummary([saved]).cashCents, 0);
    expect(TripSummary([saved]).byPayment[PaymentMethod.invoice], 2270);
  });

  test('German amounts use exact cents and reject ambiguous values', () {
    expect(parseCents('22,70'), 2270);
    expect(parseCents('22.7'), 2270);
    expect(parseCents(' 200 '), 20000);
    for (final invalid in ['0', '-1', '22,701', '1.000,00', 'NaN', '1e3', '']) {
      expect(parseCents(invalid), isNull, reason: invalid);
    }
    expect(parseKilometers('12,5'), 12.5);
    for (final invalid in ['', '-2', '0', 'NaN', 'Infinity', '10001']) {
      expect(parseKilometers(invalid), isNull);
    }
  });

  test('Sources and cash payments are independent; months and active days are exact', () {
    final summary = TripSummary(tripsInMonth([
      trip('1', 20000, DateTime(2026, 10, 1)),
      trip('2', 30000, DateTime(2026, 10, 2), payment: PaymentMethod.platform),
      trip('3', 40000, DateTime(2026, 10, 3), source: 'Bolt', payment: PaymentMethod.card),
      trip('4', 2270, DateTime(2026, 9, 30)),
      trip('5', 10000, DateTime(2025, 10, 1)),
    ], DateTime(2026, 10)));
    expect(summary.totalCents, 90000);
    expect(summary.cashCents, 20000);
    expect(summary.workingDays, 3);
    expect(summary.averageWorkingDayCents, 30000);
    expect(summary.bySource, {'Uber': 50000, 'Bolt': 40000});
    expect(summary.dailyCents(DateTime(2026, 10)).take(4), [20000, 30000, 40000, 0]);
    expect(summary.dailyCents(DateTime(2026, 10)), hasLength(31));
    expect(TripSummary([]).dailyCents(DateTime(2024, 2)), hasLength(29));
    expect(TripSummary([]).averageWorkingDayCents, 0);
  });

  test('Revenue/km excludes trips with unknown distance', () {
    final summary = TripSummary([
      trip('1', 20000, DateTime(2026, 10, 1), kilometers: 150),
      trip('2', 30000, DateTime(2026, 10, 1)),
    ]);
    expect(summary.totalCents, 50000);
    expect(summary.eurosPerKilometer, closeTo(200 / 150, 0.00001));
    expect(summary.tripsWithDistance, 1);
    expect(TripSummary([]).eurosPerKilometer, isNull);
  });

  test('Trips survive reload; editing replaces one entry and deleting persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LogbookStore(prefs)..load();
    await store.saveTrip(trip('1', 2270, DateTime(2026, 10, 1), kilometers: 12.5));
    await store.addSource('Zentrale');
    await store.addSource('zentrale');
    final reloaded = LogbookStore(prefs)..load();
    expect(reloaded.trips.single.cents, 2270);
    expect(reloaded.trips.single.kilometers, 12.5);
    expect(reloaded.sources.where((s) => s.toLowerCase() == 'zentrale'), hasLength(1));
    await reloaded.saveTrip(trip('1', 3000, DateTime(2026, 10, 1)));
    expect(reloaded.trips, hasLength(1));
    expect(reloaded.trips.single.cents, 3000);
    await reloaded.deleteTrip('1');
    final archived = (LogbookStore(prefs)..load()).trips.single;
    expect(archived.deleted, true);
    expect(archived.history, hasLength(2));
    expect(archived.history.first['cents'], 2270);
    expect(TripSummary([archived]).totalCents, 0);
    expect(() => reviseTrip(archived, trip('1', 4000, DateTime(2026, 10, 1))), throwsStateError);
  });

  test('Unreadable saved data is preserved and reported', () async {
    SharedPreferences.setMockInitialValues({LogbookStore.storageKey: 'broken json'});
    final prefs = await SharedPreferences.getInstance();
    expect(() => LogbookStore(prefs).load(), throwsFormatException);
    expect(prefs.getString(LogbookStore.storageKey), 'broken json');
  });
}

