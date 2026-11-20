import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

void main() {
  test('Tips are summed per source and stay out of revenue', () {
    final at = DateTime(2026, 10, 5, 12);
    final summary = TripSummary([
      Trip(id: '1', at: at, cents: 2000, tipCents: 200, source: 'Uber', payment: PaymentMethod.platform),
      Trip(id: '2', at: at, cents: 1500, tipCents: 100, source: 'Uber', payment: PaymentMethod.cash),
      Trip(id: '3', at: at, cents: 1000, tipCents: 50, source: 'Taxi', payment: PaymentMethod.card),
      Trip(id: '4', at: at, cents: 1000, source: 'Bolt', payment: PaymentMethod.platform),
    ]);
    expect(summary.tipsBySource, {'Uber': 300, 'Taxi': 50});
    expect(summary.tipCents, 350);
    expect(summary.totalCents, 5500);
  });

  testWidgets('Extras shows tips by source; kilometers stay hidden until enabled', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    final now = DateTime.now();
    await store.saveTrip(Trip(id: 'u', at: now, cents: 2000, tipCents: 300,
        source: 'Uber', payment: PaymentMethod.platform));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Extras'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tips-by-source')), findsOneWidget);
    expect(find.text('Uber'), findsOneWidget);

    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Weitere Angaben (optional)'));
    await tester.tap(find.text('Weitere Angaben (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrtstrecke (optional)'), findsNothing);
    await store.setKilometersEnabled(true);
    await tester.pumpAndSettle();
    expect(store.kilometersEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Cash count and statistics use cash fares, tips and shift days', () {
    final summary = TripSummary([
      Trip(id: '1', at: DateTime(2026, 10, 5, 18), cents: 2000, tipCents: 100, source: 'Taxi', payment: PaymentMethod.cash),
      Trip(id: '2', at: DateTime(2026, 10, 5, 19), cents: 1500, source: 'Uber', payment: PaymentMethod.cash),
      Trip(id: '3', at: DateTime(2026, 10, 5, 20), cents: 3000, tipCents: 500, source: 'Uber', payment: PaymentMethod.platform),
      Trip(id: '4', at: DateTime(2026, 10, 12, 9), cents: 1000, source: 'Taxi', payment: PaymentMethod.card),
    ]);
    expect(summary.expectedCashCents, 3600);
    expect(summary.bestDays.first, (DateTime(2026, 10, 5), 6500));
    expect(summary.averageByWeekday, {1: 3750}); // both Mondays
    expect(summary.revenueByHour[18], 2000);
  });

  testWidgets('Cash count shows the difference to the counted amount', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    await store.saveTrip(Trip(id: 'c', at: DateTime.now(), cents: 2000,
        source: 'Taxi', payment: PaymentMethod.cash));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extras'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('start-cash')), '5000');
    await tester.enterText(find.byKey(const Key('counted-cash')), '6500');
    await tester.pumpAndSettle();
    expect(find.textContaining('fehlen in der Kasse'), findsOneWidget);
    expect(find.byKey(const Key('statistics')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
