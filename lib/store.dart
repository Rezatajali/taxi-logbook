import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logbook.dart';

class LogbookStore extends ChangeNotifier {
  LogbookStore(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'taxi_logbook_v1';
  List<Trip> _trips = [];
  List<String> _sources = ['Taxi', 'Uber', 'Bolt', 'FREENOW'];
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
    _trips = trips;
    _sources = sources;
    notifyListeners();
  }

  Future<void> _persist(List<Trip> trips, List<String> sources) async {
    if (saving) throw StateError('Speicherung läuft bereits.');
    saving = true;
    notifyListeners();
    try {
      final success = await preferences.setString(storageKey, jsonEncode({
        'version': 1,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      }));
      if (!success) throw StateError('Speicherung nicht möglich.');
      // Update the visible state only after persistence succeeds.
      _trips = trips;
      _sources = sources;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> saveTrip(Trip trip) => _persist(
        [..._trips.where((t) => t.id != trip.id), trip], [..._sources]);
  Future<void> deleteTrip(String id) =>
      _persist(_trips.where((t) => t.id != id).toList(), [..._sources]);

  Future<void> addSource(String input) async {
    final name = input.trim();
    if (name.isEmpty || name.length > 40) {
      throw ArgumentError('Die Quelle muss 1 bis 40 Zeichen lang sein.');
    }
    if (_sources.any((s) => s.toLowerCase() == name.toLowerCase())) return;
    await _persist([..._trips], [..._sources, name]);
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      });
}
