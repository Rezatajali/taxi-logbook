import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/pauses.dart';
import 'package:taxi_logbook/shifts.dart';
import 'package:taxi_logbook/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Actual work clips and merges breaks, while short-shift credit is separate', () {
    final start = DateTime(2026, 10, 6, 8);
    final shifts = [ShiftRecord(id: '1', start: start, end: start.add(const Duration(hours: 5)))];
    final pauses = [PauseRecord(id: '1', start: start.add(const Duration(hours: 1)),
      end: start.add(const Duration(hours: 1, minutes: 30))),
      PauseRecord(id: 'outside', start: start.subtract(const Duration(hours: 1)), end: start),
      PauseRecord(id: 'overlap', start: start.add(const Duration(hours: 1, minutes: 10)),
        end: start.add(const Duration(hours: 1, minutes: 20)))];
    final totals = workTotalsForDay(shifts, pauses, start, DateTime(2026, 10, 7));
    expect(totals.gross, const Duration(hours: 5));
    expect(totals.breaks, const Duration(minutes: 30));
    expect(totals.net, const Duration(hours: 4, minutes: 30));
    expect(totals.credited, const Duration(hours: 5));
    expect(requiredRecordedBreak(const Duration(hours: 6)), Duration.zero);
    expect(requiredRecordedBreak(const Duration(hours: 6, seconds: 1)), const Duration(minutes: 30));
    expect(requiredRecordedBreak(const Duration(hours: 9, seconds: 1)), const Duration(minutes: 45));
  });
  test('Night shifts split by local day and monthly hours include days without fares', () {
    final start = DateTime(2026, 10, 31, 22);
    final end = DateTime(2026, 11, 1, 6);
    final shifts = [ShiftRecord(id: 'night', start: start, end: end)];
    final pauses = [PauseRecord(id: 'cross', start: DateTime(2026, 10, 31, 23, 45),
      end: DateTime(2026, 11, 1, 0, 15))];
    final october = workTotals(shifts, pauses, DateTime(2026, 10), DateTime(2026, 11), end);
    final november = workTotalsForDay(shifts, pauses, DateTime(2026, 11, 1), end);
    expect(october.net, const Duration(hours: 1, minutes: 45));
    expect(november.net, const Duration(hours: 5, minutes: 45));
    expect(october.credited, october.net);
    expect(november.credited, november.net);
    expect(() => validateShift(shifts, ShiftRecord(id: 'overlap', start: start, end: end)), throwsFormatException);
    validateShift(shifts, ShiftRecord(id: 'next', start: end));
  });
  test('Shift end persists and atomically closes an active pause', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LogbookStore(prefs)..load();
    final start = DateTime.utc(2026, 10, 6, 8);
    final shift = ShiftRecord(id: 'work', start: start, origin: ShiftOrigin.timer);
    await store.saveShift(shift);
    await store.savePause(PauseRecord(id: 'rest', start: start.add(const Duration(hours: 3))));
    final restored = LogbookStore(prefs)..load();
    expect(restored.shifts.single.running, true);
    await restored.finishShift(restored.shifts.single, start.add(const Duration(hours: 4)));
    final finished = LogbookStore(prefs)..load();
    expect(finished.shifts.single.running, false);
    expect(finished.pauses.single.end, finished.shifts.single.end);
    expect((jsonDecode(finished.exportJson()) as Map)['shifts'], hasLength(1));
    expect(workWarning(const WorkTotals(Duration(hours: 12), Duration(hours: 3), Duration.zero)), contains('12-Stunden'));
    expect(workWarning(const WorkTotals(Duration(hours: 10), Duration.zero, Duration.zero)), contains('10 Stunden'));
    expect(workWarning(const WorkTotals(Duration(hours: 8, minutes: 1), Duration.zero, Duration.zero)), contains('8 Stunden'));
  });
  testWidgets('Phone driver starts/ends a shift, enters one manually, and sees monthly times', (tester) async {
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
    await tester.ensureVisible(find.byKey(const Key('start-shift')));
    await tester.tap(find.byKey(const Key('start-shift')));
    await tester.pumpAndSettle();
    expect(store.shifts.single.running, true);
    await tester.ensureVisible(find.byKey(ValueKey('finish-shift-${store.shifts.single.id}')));
    await tester.tap(find.byKey(ValueKey('finish-shift-${store.shifts.single.id}')));
    await tester.pumpAndSettle();
    expect(store.shifts.single.running, false);
    // Default manual interval ends at the current minute, before the just-ended timer.
    await tester.ensureVisible(find.byKey(const Key('manual-shift')));
    await tester.tap(find.byKey(const Key('manual-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-manual-pause')));
    await tester.pumpAndSettle();
    expect(store.shifts, hasLength(2));
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Arbeitszeiten im Monat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('A 12-hour warning remains visible away from the shifts page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    await store.saveShift(ShiftRecord(id: 'long', start: DateTime.now().subtract(const Duration(hours: 12))));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-warning')), findsOneWidget);
    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('work-warning')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
