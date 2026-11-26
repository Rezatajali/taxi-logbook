import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/shift_rules.dart';
import 'package:taxi_logbook/shifts.dart';
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

  testWidgets('A new fare without a shift starts one automatically', (tester) async {
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
    expect(store.shifts.single.running, isTrue);
    expect(find.byKey(const Key('shift-auto-started')), findsOneWidget);
  });

  test('12 h + 1 h limit and 11 h rest', () {
    final start = DateTime(2026, 11, 26, 8);
    final shift = ShiftRecord(id: 's', start: start);
    Trip fare(DateTime at) => Trip(id: at.toString(), at: at, cents: 1000, source: 'Taxi', payment: PaymentMethod.cash);
    expect(shiftLatestEnd(shift), DateTime(2026, 11, 26, 20));
    // Still within 13 h: no automatic end.
    expect(automaticShiftEnd(shift, [], DateTime(2026, 11, 26, 20, 30)), isNull);
    // After 13 h: end at the last fare inside the shift ...
    expect(automaticShiftEnd(shift, [fare(DateTime(2026, 11, 26, 20, 40)), fare(DateTime(2026, 11, 27, 9))],
        DateTime(2026, 11, 26, 22)), DateTime(2026, 11, 26, 20, 40));
    // ... or at start + 12 h without fares.
    expect(automaticShiftEnd(shift, [], DateTime(2026, 11, 26, 22)), DateTime(2026, 11, 26, 20));
    final ended = shift.finish(DateTime(2026, 11, 26, 20));
    expect(restUntil([ended], DateTime(2026, 11, 26, 23)), DateTime(2026, 11, 27, 7));
    expect(restUntil([ended], DateTime(2026, 11, 27, 7, 1)), isNull);
  });

  testWidgets('A fare during the 11 h rest warns and starts no shift', (tester) async {
    phone(tester);
    final store = await freshStore();
    final now = DateTime.now();
    await store.saveShift(ShiftRecord(id: 'old', start: now.subtract(const Duration(hours: 10)),
        end: now.subtract(const Duration(hours: 2))));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '1500');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rest-warning')), findsOneWidget);
    expect(store.shifts, hasLength(1));
  });

  testWidgets('A shift running longer than 13 h is closed at its last fare', (tester) async {
    phone(tester);
    final store = await freshStore();
    final now = DateTime.now();
    final start = now.subtract(const Duration(hours: 14));
    final lastFare = DateTime(start.year, start.month, start.day, start.hour + 11, start.minute);
    await store.saveShift(ShiftRecord(id: 'long', start: start));
    await store.saveTrip(Trip(id: 'f', at: lastFare, cents: 2000, source: 'Taxi', payment: PaymentMethod.cash));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(store.shifts.single.running, isFalse);
    expect(store.shifts.single.end!.toLocal(), lastFare);
    expect(find.byKey(const Key('shift-auto-ended')), findsOneWidget);
  });

  testWidgets('After 12 h a dialog says stop; OK ends the shift', (tester) async {
    phone(tester);
    final store = await freshStore();
    final start = DateTime.now().subtract(const Duration(hours: 12, minutes: 20));
    await store.saveShift(ShiftRecord(id: 'twelve', start: start));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-limit-dialog')), findsOneWidget);
    expect(store.shifts.single.running, isTrue);
    await tester.tap(find.byKey(const Key('shift-limit-ok')));
    await tester.pumpAndSettle();
    expect(store.shifts.single.running, isFalse);
    expect(find.byKey(const Key('shift-limit-dialog')), findsNothing);
    expect(find.byKey(const Key('shift-ended-ok')), findsOneWidget);
  });
}
