import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'expenses.dart';
import 'logbook.dart';
import 'store.dart';
import 'pauses.dart';
import 'shifts.dart';

class CloudRecords {
  const CloudRecords(this.trips, {this.pending = false, this.fromCache = false,
    this.skipped = 0});
  final List<Trip> trips;
  final bool pending;
  final bool fromCache;
  /// Documents that could not be read. They are shown as a warning instead of
  /// breaking the whole logbook stream.
  final int skipped;
}

/// Parses each document on its own so one malformed record (e.g. written by an
/// older app version or directly via the REST API) cannot hide all others.
(List<T>, int) parseDocuments<T>(Iterable<(String, Map<String, dynamic>)> docs,
    T Function(Map<String, dynamic>) parse) {
  final result = <T>[];
  var skipped = 0;
  for (final (id, data) in docs) {
    try {
      // Document ID is authoritative; it cannot redirect an edit.
      result.add(parse({...data, 'id': id}));
    } catch (_) {
      skipped++;
    }
  }
  return (result, skipped);
}

abstract class UserLogbookBackend {
  Stream<CloudRecords> watchTrips();
  Stream<CloudShifts> watchShifts();
  Future<void> saveShift(ShiftRecord shift, {List<PauseRecord> finishedPauses = const []});
  Stream<CloudPauses> watchPauses();
  Future<void> savePause(PauseRecord pause);
  Stream<List<Expense>> watchExpenses();
  Future<void> saveExpense(Expense expense);
  Future<void> deleteExpense(String id);
  Stream<List<String>> watchSources();
  Stream<String> watchDriverNumber();
  Future<void> saveDriverNumber(String number);
  Future<void> saveTrip(Trip trip);
  Future<void> deleteTrip(String id);
  Future<void> addSource(String source);
}

class CloudPauses {
  const CloudPauses(this.pauses, {this.pending = false, this.skipped = 0});
  final List<PauseRecord> pauses;
  final bool pending;
  final int skipped;
}

class CloudShifts {
  const CloudShifts(this.shifts, {this.pending = false, this.skipped = 0});
  final List<ShiftRecord> shifts;
  final bool pending;
  final int skipped;
}

Iterable<(String, Map<String, dynamic>)> _entries(QuerySnapshot<Map<String, dynamic>> snapshot) =>
    snapshot.docs.map((doc) => (doc.id, doc.data()));

// Bind paths once to the signed-in UID. A new account gets a new backend/store.
class FirestoreLogbookBackend implements UserLogbookBackend {
  FirestoreLogbookBackend(FirebaseFirestore db, String uid)
      : user = db.collection('users').doc(uid);
  final DocumentReference<Map<String, dynamic>> user;
  CollectionReference<Map<String, dynamic>> get trips => user.collection('trips');
  DocumentReference<Map<String, dynamic>> get settings =>
      user.collection('settings').doc('logbook');

  @override
  Stream<CloudShifts> watchShifts() => user.collection('shifts')
    .snapshots(includeMetadataChanges: true).map((snapshot) {
      final (shifts, skipped) = parseDocuments(_entries(snapshot), ShiftRecord.fromJson);
      return CloudShifts(shifts, pending: snapshot.metadata.hasPendingWrites, skipped: skipped);
    });
  @override
  Future<void> saveShift(ShiftRecord shift, {List<PauseRecord> finishedPauses = const []}) {
    final batch = user.firestore.batch();
    batch.set(user.collection('shifts').doc(shift.id), shift.toJson());
    for (final pause in finishedPauses) {
      batch.set(user.collection('pauses').doc(pause.id), pause.toJson());
    }
    return batch.commit();
  }
  @override
  Stream<CloudRecords> watchTrips() => trips
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        final (trips, skipped) = parseDocuments(_entries(snapshot), Trip.fromJson);
        return CloudRecords(trips,
          pending: snapshot.metadata.hasPendingWrites,
          fromCache: snapshot.metadata.isFromCache,
          skipped: skipped);
      });
  @override
  Stream<List<String>> watchSources() => settings.snapshots().map((snapshot) {
        final sources = snapshot.data()?['sources'];
        if (sources is! List) return <String>[];
        return sources.whereType<String>()
            .map((s) => s.trim()).where((s) => s.isNotEmpty && s.length <= 40).toList();
      });
  @override
  Stream<String> watchDriverNumber() => settings.snapshots().map(
      (snapshot) => switch (snapshot.data()?['driverNumber']) {
            final String number => number,
            _ => '',
          });
  @override
  Future<void> saveDriverNumber(String number) => settings.set(
      {'driverNumber': number}, SetOptions(merge: true));
  @override
  Future<void> saveTrip(Trip trip) => user.firestore.runTransaction((transaction) async {
    final ref = trips.doc(trip.id);
    final snapshot = await transaction.get(ref);
    final previous = snapshot.exists ? Trip.fromJson({...snapshot.data()!, 'id': ref.id}) : null;
    transaction.set(ref, reviseTrip(previous, trip).toJson());
  });
  @override
  Future<void> deleteTrip(String id) => user.firestore.runTransaction((transaction) async {
    final ref = trips.doc(id);
    final snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    final previous = Trip.fromJson({...snapshot.data()!, 'id': ref.id});
    // Already deleted: nothing to write (rules also reject edits of deleted trips).
    if (previous.deleted) return;
    transaction.set(ref, markTripDeleted(previous).toJson());
  });
  @override
  Stream<CloudPauses> watchPauses() => user.collection('pauses')
    .snapshots(includeMetadataChanges: true).map((snapshot) {
      final (pauses, skipped) = parseDocuments(_entries(snapshot), PauseRecord.fromJson);
      return CloudPauses(pauses, pending: snapshot.metadata.hasPendingWrites, skipped: skipped);
    });
  @override
  Future<void> savePause(PauseRecord pause) => user.collection('pauses').doc(pause.id).set(pause.toJson());
  @override
  Stream<List<Expense>> watchExpenses() => user.collection('expenses')
    .snapshots().map((snapshot) => parseDocuments(_entries(snapshot), Expense.fromJson).$1);
  @override
  Future<void> saveExpense(Expense expense) =>
      user.collection('expenses').doc(expense.id).set(expense.toJson());
  @override
  Future<void> deleteExpense(String id) => user.collection('expenses').doc(id).delete();
  @override
  Future<void> addSource(String source) => settings.set(
      {'sources': FieldValue.arrayUnion([source])}, SetOptions(merge: true));
}

class CloudLogbookStore extends LogbookStore {
  CloudLogbookStore(super.preferences, this.backend);
  final UserLogbookBackend backend;
  static const defaults = ['Taxi', 'Uber', 'Bolt', 'FREENOW'];
  List<Trip> _cloudTrips = [];
  List<ShiftRecord> _cloudShifts = [];
  bool _shiftsReady = false;
  bool _shiftPending = false;
  StreamSubscription<CloudShifts>? _shiftSubscription;
  @override
  List<ShiftRecord> get shifts => List.unmodifiable(_cloudShifts);
  @override
  bool get shiftsReady => _shiftsReady;
  List<Expense> _cloudExpenses = [];
  bool _expensesReady = false;
  StreamSubscription<List<Expense>>? _expenseSubscription;
  @override
  List<Expense> get expenses => List.unmodifiable(_cloudExpenses);
  @override
  bool get expensesReady => _expensesReady;
  List<PauseRecord> _cloudPauses = [];
  bool _pausesReady = false;
  bool _pausePending = false;
  StreamSubscription<CloudPauses>? _pauseSubscription;
  @override
  List<PauseRecord> get pauses => List.unmodifiable(_cloudPauses);
  @override
  bool get pausesReady => _pausesReady;
  List<String> _cloudSources = [...defaults];
  StreamSubscription<CloudRecords>? _tripSubscription;
  StreamSubscription<List<String>>? _sourceSubscription;
  String _cloudDriverNumber = '';
  StreamSubscription<String>? _driverSubscription;
  bool _loading = true;
  bool _ready = false;
  bool _pending = false;
  int _pendingOperations = 0;
  bool _cached = true;
  bool _disposed = false;
  String? _error;
  int _generation = 0;
  int _skippedTrips = 0;
  int _skippedShifts = 0;
  int _skippedPauses = 0;

  @override
  String? get dataWarning {
    final skipped = _skippedTrips + _skippedShifts + _skippedPauses;
    return skipped == 0 ? null
        : '$skipped Cloud-Eintrag/Einträge konnten nicht gelesen werden und werden nicht angezeigt.';
  }

  @override
  String get driverNumber => _cloudDriverNumber;
  @override
  List<Trip> get trips => List.unmodifiable(_cloudTrips);
  @override
  List<String> get sources => List.unmodifiable(_cloudSources);
  @override
  bool get isCloud => true;
  @override
  bool get loading => _loading;
  @override
  bool get ready => _ready && _error == null;
  @override
  bool get pendingWrites => _pending || _shiftPending || _pausePending || _pendingOperations > 0;
  @override
  String? get syncError => _error;
  @override
  String get storageLabel => _error != null ? 'Verbindung prüfen'
      : _loading ? 'Laden …'
      : pendingWrites ? 'Synchronisiert …'
      : _cached ? 'Offline / Cache' : 'Cloud';

  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void load() {
    final generation = ++_generation;
    _tripSubscription?.cancel();
    _pauseSubscription?.cancel();
    _expenseSubscription?.cancel();
    _shiftSubscription?.cancel();
    _sourceSubscription?.cancel();
    _driverSubscription?.cancel();
    _shiftsReady = false;
    _expensesReady = false;
    _pausesReady = false;
    _loading = true;
    _error = null;
    _notify();
    bool active() => !_disposed && generation == _generation;
    void failed(Object error) {
      if (!active()) return;
      _loading = false;
      _error = 'Cloud-Daten konnten nicht geladen werden. Prüfe die Verbindung '
          'und versuche es erneut.';
      if (error is FirebaseException && error.code == 'permission-denied') {
        _error = 'Kein Zugriff auf die Cloud-Daten. Bitte die Firestore-Regeln prüfen.';
      }
      _notify();
    }
    _tripSubscription = backend.watchTrips().listen((records) {
      if (!active()) return;
      _cloudTrips = records.trips;
      _skippedTrips = records.skipped;
      _cloudSources = [...{..._cloudSources, ...records.trips.map((t) => t.source)}];
      _pending = records.pending;
      _cached = records.fromCache;
      _ready = true;
      _loading = false;
      _notify();
    }, onError: failed);
    _shiftSubscription = backend.watchShifts().listen((records) {
      if (!active()) return;
      _cloudShifts = records.shifts;
      _skippedShifts = records.skipped;
      _shiftPending = records.pending;
      _shiftsReady = true;
      _notify();
    }, onError: failed);
    _expenseSubscription = backend.watchExpenses().listen((records) {
      if (!active()) return;
      _cloudExpenses = records;
      _expensesReady = true;
      _notify();
    }, onError: failed);
    _pauseSubscription = backend.watchPauses().listen((records) {
      if (!active()) return;
      _cloudPauses = records.pauses;
      _skippedPauses = records.skipped;
      _pausePending = records.pending;
      _pausesReady = true;
      _notify();
    }, onError: failed);
    _driverSubscription = backend.watchDriverNumber().listen((number) {
      if (!active()) return;
      _cloudDriverNumber = number;
      _notify();
    }, onError: failed);
    _sourceSubscription = backend.watchSources().listen((values) {
      if (!active()) return;
      _cloudSources = [...{...defaults, ...values,
        ..._cloudTrips.map((trip) => trip.source)}];
      _notify();
    }, onError: failed);
  }

  @override
  Future<void> retry() async { load(); }

  Future<void> _write(Future<void> Function() action, {bool queued = true}) async {
    if (_disposed || !ready || saving) {
      throw StateError('Cloud-Daten sind noch nicht bereit.');
    }
    saving = true;
    _notify();
    try {
      // FlutterFire queues offline writes. A timeout is not a failed save:
      // snapshots show the pending change, and the original future stays alive.
      _pendingOperations++;
      final operation = Future<void>.sync(action).then((_) {
        _pendingOperations--;
        _notify();
      }, onError: (Object error, StackTrace stack) {
        _pendingOperations--;
        _error = 'Eine Änderung konnte nicht synchronisiert werden. Bitte erneut versuchen.';
        _notify();
        Error.throwWithStackTrace(error, stack);
      });
      if (queued) {
        await operation.timeout(const Duration(seconds: 20), onTimeout: () {});
      } else {
        // Transactions require an online read; never report them saved on timeout.
        await operation;
      }
    } finally {
      saving = false;
      _notify();
    }
  }
  @override
  Future<void> saveShift(ShiftRecord shift) {
    if (!shiftsReady) throw StateError('Schichten werden noch geladen.');
    validateShift(shifts, shift);
    return _write(() => backend.saveShift(shift));
  }
  @override
  Future<void> finishShift(ShiftRecord shift, DateTime end) {
    if (!shiftsReady || !pausesReady) throw StateError('Zeiten werden noch geladen.');
    final finished = shift.finish(end);
    validateShift(shifts, finished);
    final breaks = pauses.where((p) => p.running && p.start.isBefore(end))
      .map((p) => p.finish(end)).toList();
    return _write(() => backend.saveShift(finished, finishedPauses: breaks));
  }
  @override
  Future<void> savePause(PauseRecord pause) {
    if (!pausesReady) throw StateError('Pausen werden noch geladen.');
    return _write(() => backend.savePause(pause));
  }
  @override
  Future<void> saveExpense(Expense expense) => _write(() => backend.saveExpense(expense));
  @override
  Future<void> deleteExpense(String id) => _write(() => backend.deleteExpense(id));
  @override
  Future<void> saveTrip(Trip trip) => _write(() => backend.saveTrip(trip), queued: false);
  @override
  Future<void> deleteTrip(String id) => _write(() => backend.deleteTrip(id), queued: false);
  @override
  Future<void> addSource(String input) async {
    final name = input.trim();
    if (name.isEmpty || name.length > 40) {
      throw ArgumentError('Die Quelle muss 1 bis 40 Zeichen lang sein.');
    }
    if (sources.any((s) => s.toLowerCase() == name.toLowerCase())) return;
    await _write(() => backend.addSource(name));
  }
  @override
  Future<void> saveDriverNumber(String input) async {
    final number = input.trim();
    if (number.isNotEmpty && !RegExp(r'^\d{1,10}$').hasMatch(number)) {
      throw ArgumentError('Bitte 1 bis 10 Ziffern eingeben.');
    }
    await _write(() => backend.saveDriverNumber(number));
  }
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tripSubscription?.cancel();
    _pauseSubscription?.cancel();
    _expenseSubscription?.cancel();
    _shiftSubscription?.cancel();
    _sourceSubscription?.cancel();
    _driverSubscription?.cancel();
    super.dispose();
  }
}

