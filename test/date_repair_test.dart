import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

Trip entered(DateTime enteredAt, DateTime at) => Trip(
  id: enteredAt.microsecondsSinceEpoch.toString(), at: at, cents: 1300,
  source: 'Taxi', payment: PaymentMethod.cash);

void main() {
  test('Fares filed under a stale day are found with the entry date as fix', () {
    // App opened on 20.11., fare entered on 23.11. at 14:32 -> stored as 20.11. 14:32.
    final stale = entered(DateTime(2026, 11, 23, 14, 32, 10), DateTime(2026, 11, 20, 14, 32));
    // Normal fare entered right away.
    final normal = entered(DateTime(2026, 11, 23, 15, 1), DateTime(2026, 11, 23, 15, 1));
    // Forgotten fare entered next day with a different, chosen time.
    final chosenTime = entered(DateTime(2026, 11, 24, 9, 0), DateTime(2026, 11, 23, 22, 15));
    // Old ids that are not timestamps are ignored.
    final legacy = Trip(id: 'abc', at: DateTime(2026, 11, 20), cents: 100, source: 'Taxi', payment: PaymentMethod.cash);
    final found = misdatedTrips([stale, normal, chosenTime, legacy]);
    expect(found.map((e) => e.$1.id), [stale.id]);
    expect(found.single.$2, DateTime(2026, 11, 23, 14, 32));
  });

  testWidgets('The driver can move misdated fares to the right day', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    final now = DateTime.now();
    final enteredAt = DateTime(now.year, now.month, now.day, 10, 5);
    final staleAt = DateTime(now.year, now.month, now.day - 3, 10, 5);
    await store.saveTrip(entered(enteredAt, staleAt));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('date-repair-banner')), findsOneWidget);
    await tester.tap(find.text('Prüfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-date-repair')));
    await tester.pumpAndSettle();
    expect(store.trips.single.at, DateTime(now.year, now.month, now.day, 10, 5));
    expect(store.trips.single.history, hasLength(1)); // old date kept in history
    expect(find.byKey(const Key('date-repair-banner')), findsNothing);
  });
}
