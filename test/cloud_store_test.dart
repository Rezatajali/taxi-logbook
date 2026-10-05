import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/cloud_store.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/store.dart';

class FakeBackend implements UserLogbookBackend {
  final records = StreamController<CloudRecords>.broadcast(sync: true);
  final sourceRecords = StreamController<List<String>>.broadcast(sync: true);
  final trips = <String, Trip>{};
  final sources = <String>[];
  final driverRecords = StreamController<String>.broadcast(sync: true);
  String driverNumber = '';
  @override
  Stream<String> watchDriverNumber() => driverRecords.stream;
  @override
  Future<void> saveDriverNumber(String number) async { driverNumber = number; driverRecords.add(number); }
  bool fail = false;
  void emit() => records.add(CloudRecords(trips.values.toList()));
  @override
  Stream<CloudRecords> watchTrips() => records.stream;
  @override
  Stream<List<String>> watchSources() => sourceRecords.stream;
  @override
  Future<void> saveTrip(Trip trip) async {
    if (fail) throw StateError('denied');
    trips[trip.id] = trip; emit();
  }
  @override
  Future<void> deleteTrip(String id) async { trips.remove(id); emit(); }
  @override
  Future<void> addSource(String name) async { sources.add(name); sourceRecords.add(sources); }
  Future<void> close() async { await records.close(); await sourceRecords.close(); await driverRecords.close(); }
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
    expect((jsonDecode(accountA.exportJson()) as Map)['trips'], hasLength(2));
    await accountA.deleteTrip('one');
    expect(accountA.trips.single.id, 'two');
    expect((LogbookStore(prefs)..load()).trips.single.id, 'old-local');
    backendA.fail = true;
    await expectLater(accountA.saveTrip(fare('rejected', 100)), throwsStateError);
    expect(accountA.trips.single.id, 'two');
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
}
