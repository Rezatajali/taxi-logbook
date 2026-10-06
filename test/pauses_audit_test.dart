import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/pauses.dart';
import 'package:taxi_logbook/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Pausen survive reload and overlapping midnight entries count once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LogbookStore(prefs)..load();
    final start = DateTime(2026, 10, 5, 23, 50);
    await store.savePause(PauseRecord(id: 'timer', start: start, origin: PauseOrigin.timer));
    final restored = LogbookStore(prefs)..load();
    expect(restored.pauses.single.running, true);
    await restored.savePause(restored.pauses.single.finish(DateTime(2026, 10, 6, 0, 20)));
    await restored.savePause(PauseRecord(id: 'manual', start: DateTime(2026, 10, 6, 0, 10),
      end: DateTime(2026, 10, 6, 0, 30)));
    expect(pauseDurationForDay(restored.pauses, DateTime(2026, 10, 5), DateTime(2026, 10, 7)),
      const Duration(minutes: 10));
    expect(pauseDurationForDay(restored.pauses, DateTime(2026, 10, 6), DateTime(2026, 10, 7)),
      const Duration(minutes: 30));
    expect((jsonDecode(restored.exportJson()) as Map)['pauses'], hasLength(2));
    expect(qualifiesAsGpsPause(const Duration(minutes: 15)), false);
    expect(qualifiesAsGpsPause(const Duration(minutes: 15, seconds: 1)), true);
    expect(() => PauseRecord(id: 'bad', start: start, end: start), throwsFormatException);
  });

  test('No-op saves preserve history; successive changes and deletion retain prior amounts', () {
    final original = Trip(id: '1', at: DateTime(2026, 10, 6), cents: 2270,
      source: 'Taxi', payment: PaymentMethod.cash);
    expect(reviseTrip(original, original).history, isEmpty);
    final edited = reviseTrip(original, Trip(id: '1', at: original.at, cents: 3000,
      source: 'Uber', payment: PaymentMethod.platform));
    final deleted = markTripDeleted(edited);
    final restored = Trip.fromJson(deleted.toJson());
    expect(restored.history.map((entry) => entry['cents']), [2270, 3000]);
    expect(restored.editedAt, isNotNull);
    expect(restored.deletedAt, isNotNull);
    expect(markTripDeleted(restored).history, hasLength(2));
    expect(TripSummary([restored]).byPayment[PaymentMethod.cash], 0);
    expect(TripSummary([restored]).workingDays, 0);
  });

  testWidgets('A driver starts, stops and manually records a pause on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schichten'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('start-pause')));
    await tester.tap(find.byKey(const Key('start-pause')));
    await tester.pumpAndSettle();
    expect(store.pauses.single.running, true);
    await tester.ensureVisible(find.byKey(ValueKey('stop-pause-${store.pauses.single.id}')));
    await tester.tap(find.byKey(ValueKey('stop-pause-${store.pauses.single.id}')));
    await tester.pumpAndSettle();
    expect(store.pauses.single.running, false);
    await tester.ensureVisible(find.byKey(const Key('manual-pause')));
    await tester.tap(find.byKey(const Key('manual-pause')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-manual-pause')));
    await tester.pumpAndSettle();
    expect(store.pauses, hasLength(2));
    expect(store.pauses.last.origin, PauseOrigin.manual);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Edited fares show yellow status and deleted fares stay struck through with history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    final original = Trip(id: 'audit', at: DateTime.now(), cents: 2270,
      source: 'Taxi', payment: PaymentMethod.cash);
    await store.saveTrip(original);
    await store.saveTrip(Trip(id: original.id, at: original.at, cents: 3000,
      source: 'Taxi', payment: PaymentMethod.cash));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    expect(find.text('Bearbeitet'), findsOneWidget);
    await store.deleteTrip(original.id);
    await tester.pumpAndSettle();
    expect(find.text('Gelöscht · nicht im Umsatz'), findsOneWidget);
    final amount = tester.widget<Text>(find.text(money(3000)));
    expect(amount.style?.decoration, TextDecoration.lineThrough);
    expect(find.byKey(const ValueKey('edit-audit')), findsNothing);
    await tester.ensureVisible(find.text('Änderungsverlauf'));
    await tester.tap(find.text('Änderungsverlauf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vorher: 22,70'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
