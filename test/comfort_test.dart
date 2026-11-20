import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

Future<LogbookStore> freshStore([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return LogbookStore(await SharedPreferences.getInstance())..load();
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('Week revenue uses Monday-based weeks', () {
    expect(weekStart(DateTime(2026, 11, 20)), DateTime(2026, 11, 16)); // Friday -> Monday
    final trips = [
      Trip(id: 'a', at: DateTime(2026, 11, 16, 10), cents: 1000, source: 'Taxi', payment: PaymentMethod.cash),
      Trip(id: 'b', at: DateTime(2026, 11, 22, 23), cents: 500, source: 'Taxi', payment: PaymentMethod.cash),
      Trip(id: 'c', at: DateTime(2026, 11, 23, 9), cents: 700, source: 'Taxi', payment: PaymentMethod.cash),
    ];
    expect(weekRevenue(trips, DateTime(2026, 11, 16)), 1500);
    expect(weekRevenue(trips, DateTime(2026, 11, 23)), 700);
  });

  testWidgets('Daily goal shows progress once set', (tester) async {
    phone(tester);
    final store = await freshStore({LogbookStore.dailyGoalKey: 20000});
    await store.saveTrip(Trip(id: 'a', at: DateTime.now(), cents: 5000, source: 'Taxi', payment: PaymentMethod.cash));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-goal')), findsOneWidget);
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('week-compare')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A new fare without a shift offers to start one', (tester) async {
    phone(tester);
    final store = await freshStore();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '1500');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-reminder')), findsOneWidget);
    await tester.tap(find.text('Schicht anfangen').last);
    await tester.pumpAndSettle();
    expect(store.shifts.single.running, isTrue);
  });
}
