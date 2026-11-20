import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/cloud_store.dart';
import 'package:taxi_logbook/expenses.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/store.dart';
import 'package:taxi_logbook/pauses.dart';
import 'package:taxi_logbook/shifts.dart';

class FakeBackend implements UserLogbookBackend {
  final records = StreamController<CloudRecords>.broadcast(sync: true);
  final sourceRecords = StreamController<List<String>>.broadcast(sync: true);
  final trips = <String, Trip>{};
  final shifts = <String, ShiftRecord>{};
  final shiftRecords = StreamController<CloudShifts>.broadcast(sync: true);
  @override
  Stream<CloudShifts> watchShifts() => shiftRecords.stream;
  @override
  Future<void> saveShift(ShiftRecord shift, {List<PauseRecord> finishedPauses = const []}) async {
    shifts[shift.id] = shift;
    for (final pause in finishedPauses) { pauses[pause.id] = pause; }
    emit();
  }
  final expenses = <String, Expense>{};
  final expenseRecords = StreamController<List<Expense>>.broadcast(sync: true);
  @override
  Stream<List<Expense>> watchExpenses() => expenseRecords.stream;
  @override
  Future<void> saveExpense(Expense expense) async { expenses[expense.id] = expense; expenseRecords.add(expenses.values.toList()); }
  @override
  Future<void> deleteExpense(String id) async { expenses.remove(id); expenseRecords.add(expenses.values.toList()); }
  final pauses = <String, PauseRecord>{};
  final pauseRecords = StreamController<CloudPauses>.broadcast(sync: true);
  @override
  Stream<CloudPauses> watchPauses() => pauseRecords.stream;
  @override
  Future<void> savePause(PauseRecord pause) async { pauses[pause.id] = pause; pauseRecords.add(CloudPauses(pauses.values.toList())); }
  final sources = <String>[];
  final driverRecords = StreamController<String>.broadcast(sync: true);
  String driverNumber = '';
  @override
  Stream<String> watchDriverNumber() => driverRecords.stream;
  @override
  Future<void> saveDriverNumber(String number) async { driverNumber = number; driverRecords.add(number); }
  bool fail = false;
  void emit() { shiftRecords.add(CloudShifts(shifts.values.toList())); records.add(CloudRecords(trips.values.toList())); pauseRecords.add(CloudPauses(pauses.values.toList())); }
  @override
  Stream<CloudRecords> watchTrips() => records.stream;
  @override
  Stream<List<String>> watchSources() => sourceRecords.stream;
  @override
  Future<void> saveTrip(Trip trip) async {
    if (fail) throw StateError('denied');
    trips[trip.id] = reviseTrip(trips[trip.id], trip); emit();
  }
  @override
  Future<void> deleteTrip(String id) async { trips[id] = markTripDeleted(trips[id]!); emit(); }
  @override
  Future<void> addSource(String name) async { sources.add(name); sourceRecords.add(sources); }
  Future<void> close() async { await shiftRecords.close(); await pauseRecords.close(); await records.close(); await sourceRecords.close(); await driverRecords.close(); await expenseRecords.close(); }
}
Trip fare(String id, int cents) => Trip(id: id, at: DateTime(2026, 10, 5),
  cents: cents, source: 'Taxi', payment: PaymentMethod.cash);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Cloud records remain separate, export uses cloud data, and local data is not imported', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final local = LogbookStore(prefs)..load();
    await local.saveTrip(fare('old-local', 9999));
    final backendA = FakeBackend();
    final backendB = FakeBackend();
    final accountA = CloudLogbookStore(prefs, backendA)..load();
    final accountB = CloudLogbookStore(prefs, backendB)..load();
    backendA.emit(); backendB.emit();
    expect(accountA.trips, isEmpty);
    await accountA.saveDriverNumber('267');
    expect(accountA.driverNumber, '267');
    expect(accountB.driverNumber, isEmpty);
    await accountA.saveTrip(fare('one', 2270));
    await accountA.saveTrip(fare('two', 3500));
    await accountA.saveTrip(fare('one', 3000));
    expect(accountA.trips, hasLength(2));
    expect(accountB.trips, isEmpty);
    final pause = PauseRecord(id: 'break', start: DateTime.utc(2026, 10, 5, 12), origin: PauseOrigin.timer);
    await accountA.savePause(pause);
    expect(accountA.pauses.single.running, true);
    expect(accountB.pauses, isEmpty);
    await accountA.savePause(pause.finish(DateTime.utc(2026, 10, 5, 12, 30)));
    expect(accountA.pauses.single.end, isNotNull);
    final shift = ShiftRecord(id: 'work', start: DateTime.utc(2026, 10, 5, 8));
    await accountA.saveShift(shift);
    expect(accountA.shifts.single.running, true);
    expect(accountB.shifts, isEmpty);
    await accountA.finishShift(shift, DateTime.utc(2026, 10, 5, 16));
    expect(accountA.shifts.single.running, false);
    expect((jsonDecode(accountA.exportJson()) as Map)['trips'], hasLength(2));
    await accountA.deleteTrip('one');
    expect(TripSummary(accountA.trips).trips.single.id, 'two');
    expect((LogbookStore(prefs)..load()).trips.single.id, 'old-local');
    backendA.fail = true;
    await expectLater(accountA.saveTrip(fare('rejected', 100)), throwsStateError);
    expect(TripSummary(accountA.trips).trips.single.id, 'two');
    expect(accountA.pendingWrites, false);
    expect(accountA.syncError, isNotNull);
    accountA.dispose(); accountB.dispose(); local.dispose();
    await backendA.close(); await backendB.close();
  });
  test('A disposed account ignores late stream events after switching accounts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = FakeBackend();
    final old = CloudLogbookStore(prefs, backend)..load();
    backend.emit();
    old.dispose();
    backend.trips['late'] = fare('late', 100); backend.emit();
    expect(old.trips, isEmpty);
    await backend.close();
  });

  test('One malformed cloud document does not hide the others', () {
    final (trips, skipped) = parseDocuments([
      ('good', fare('ignored-id', 2270).toJson()),
      ('bad', {'cents': 'not a number'}),
      ('negative', {...fare('x', 100).toJson(), 'cents': -5}),
    ], Trip.fromJson);
    expect(trips.single.id, 'good');
    expect(skipped, 2);
  });

  test('Skipped cloud records are reported without blocking writes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = FakeBackend();
    final store = CloudLogbookStore(prefs, backend)..load();
    backend.emit();
    expect(store.dataWarning, isNull);
    backend.records.add(CloudRecords([fare('one', 1000)], skipped: 1));
    expect(store.dataWarning, contains('1'));
    expect(store.ready, isTrue);
    store.dispose();
    await backend.close();
  });
}
