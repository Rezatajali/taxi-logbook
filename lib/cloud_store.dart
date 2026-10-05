import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'logbook.dart';
import 'store.dart';

class CloudRecords {
  const CloudRecords(this.trips, {this.pending = false, this.fromCache = false});
  final List<Trip> trips;
  final bool pending;
  final bool fromCache;
}

abstract class UserLogbookBackend {
  Stream<CloudRecords> watchTrips();
  Stream<List<String>> watchSources();
  Stream<String> watchDriverNumber();
  Future<void> saveDriverNumber(String number);
  Future<void> saveTrip(Trip trip);
  Future<void> deleteTrip(String id);
  Future<void> addSource(String source);
}

// Bind paths once to the signed-in UID. A new account gets a new backend/store.
class FirestoreLogbookBackend implements UserLogbookBackend {
  FirestoreLogbookBackend(FirebaseFirestore db, String uid)
      : user = db.collection('users').doc(uid);
  final DocumentReference<Map<String, dynamic>> user;
  CollectionReference<Map<String, dynamic>> get trips => user.collection('trips');
  DocumentReference<Map<String, dynamic>> get settings =>
      user.collection('settings').doc('logbook');

  @override
  Stream<CloudRecords> watchTrips() => trips
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) => CloudRecords(
            snapshot.docs.map((doc) {
              final json = doc.data();
              // Document ID is authoritative; it cannot redirect an edit.
              json['id'] = doc.id;
              return Trip.fromJson(json);
            }).toList(),
            pending: snapshot.metadata.hasPendingWrites,
            fromCache: snapshot.metadata.isFromCache,
          ));
  @override
  Stream<List<String>> watchSources() => settings.snapshots().map((snapshot) {
        final sources = snapshot.data()?['sources'];
        return sources == null ? <String>[] : List<String>.from(sources as List);
      });
  @override
  Stream<String> watchDriverNumber() => settings.snapshots().map(
      (snapshot) => snapshot.data()?['driverNumber'] as String? ?? '');
  @override
  Future<void> saveDriverNumber(String number) => settings.set(
      {'driverNumber': number}, SetOptions(merge: true));
  @override
  Future<void> saveTrip(Trip trip) => trips.doc(trip.id).set(trip.toJson());
  @override
  Future<void> deleteTrip(String id) => trips.doc(id).delete();
  @override
  Future<void> addSource(String source) => settings.set(
      {'sources': FieldValue.arrayUnion([source])}, SetOptions(merge: true));
}

class CloudLogbookStore extends LogbookStore {
  CloudLogbookStore(super.preferences, this.backend);
  final UserLogbookBackend backend;
  static const defaults = ['Taxi', 'Uber', 'Bolt', 'FREENOW'];
  List<Trip> _cloudTrips = [];
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
  bool get pendingWrites => _pending || _pendingOperations > 0;
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
    _sourceSubscription?.cancel();
    _driverSubscription?.cancel();
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
      _cloudSources = [...{..._cloudSources, ...records.trips.map((t) => t.source)}];
      _pending = records.pending;
      _cached = records.fromCache;
      _ready = true;
      _loading = false;
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

  Future<void> _write(Future<void> Function() action) async {
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
      await operation.timeout(const Duration(seconds: 20), onTimeout: () {});
    } finally {
      saving = false;
      _notify();
    }
  }
  @override
  Future<void> saveTrip(Trip trip) => _write(() => backend.saveTrip(trip));
  @override
  Future<void> deleteTrip(String id) => _write(() => backend.deleteTrip(id));
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
    _sourceSubscription?.cancel();
    _driverSubscription?.cancel();
    super.dispose();
  }
}
