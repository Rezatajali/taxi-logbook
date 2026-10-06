import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logbook.dart';
import 'pauses.dart';

class LogbookStore extends ChangeNotifier {
  LogbookStore(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'taxi_logbook_v1';
  List<Trip> _trips = [];
  List<PauseRecord> _pauses = [];
  List<PauseRecord> get pauses => List.unmodifiable(_pauses);
  bool get pausesReady => true;
  List<String> _sources = ['Taxi', 'Uber', 'Bolt', 'FREENOW'];
  String _driverNumber = '';
  String get driverNumber => _driverNumber;
  String get driverLabel => driverNumber.isEmpty ? 'Fahrer' : 'Fahrer $driverNumber';
  bool saving = false;

  bool get isCloud => false;
  bool get loading => false;
  bool get ready => true;
  bool get pendingWrites => false;
  String? get syncError => null;
  String get storageLabel => 'Lokal';
  Future<void> retry() async {}

  List<Trip> get trips => List.unmodifiable(_trips);
  List<String> get sources => List.unmodifiable(_sources);

  void load() {
    final raw = preferences.getString(storageKey);
    if (raw == null) return;
    // Fail visibly instead of silently overwriting unreadable records.
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final trips = (json['trips'] as List)
        .map((t) => Trip.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList();
    final sources = (json['sources'] as List).cast<String>();
    if (sources.isEmpty || sources.any((s) => s.trim().isEmpty)) {
      throw const FormatException('Ungültige Quellen.');
    }
    _pauses = (json['pauses'] as List? ?? []).map((p) => PauseRecord.fromJson(Map<String, dynamic>.from(p as Map))).toList();
    _trips = trips;
    _sources = sources;
    _driverNumber = json['driverNumber'] as String? ?? '';
    notifyListeners();
  }

  Future<void> _persist(List<Trip> trips, List<String> sources, {String? driverNumber, List<PauseRecord>? pauses}) async {
    final nextNumber = driverNumber ?? _driverNumber;
    final nextPauses = pauses ?? _pauses;
    if (saving) throw StateError('Speicherung läuft bereits.');
    saving = true;
    notifyListeners();
    try {
      final success = await preferences.setString(storageKey, jsonEncode({
        'version': 2,
        'pauses': nextPauses.map((p) => p.toJson()).toList(),
        'driverNumber': nextNumber,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      }));
      if (!success) throw StateError('Speicherung nicht möglich.');
      // Update the visible state only after persistence succeeds.
      _pauses = nextPauses;
      _trips = trips;
      _sources = sources;
      _driverNumber = nextNumber;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> saveTrip(Trip trip) {
    final existing = _trips.where((t) => t.id == trip.id).firstOrNull;
    final updated = reviseTrip(existing, trip);
    return _persist([..._trips.where((t) => t.id != trip.id), updated], [..._sources]);
  }
  Future<void> deleteTrip(String id) => _persist(
    _trips.map((t) => t.id == id ? markTripDeleted(t) : t).toList(), [..._sources]);
  Future<void> savePause(PauseRecord pause) => _persist([..._trips], [..._sources],
    pauses: [..._pauses.where((p) => p.id != pause.id), pause]);

  Future<void> addSource(String input) async {
    final name = input.trim();
    if (name.isEmpty || name.length > 40) {
      throw ArgumentError('Die Quelle muss 1 bis 40 Zeichen lang sein.');
    }
    if (_sources.any((s) => s.toLowerCase() == name.toLowerCase())) return;
    await _persist([..._trips], [..._sources, name]);
  }

  Future<void> saveDriverNumber(String input) async {
    final number = input.trim();
    if (number.isNotEmpty && !RegExp(r'^\d{1,10}$').hasMatch(number)) {
      throw ArgumentError('Bitte 1 bis 10 Ziffern eingeben.');
    }
    await _persist([..._trips], [..._sources], driverNumber: number);
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'version': 2,
        'pauses': pauses.map((p) => p.toJson()).toList(),
        'driverNumber': driverNumber,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      });
}

