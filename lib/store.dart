import 'l10n.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'expenses.dart';
import 'logbook.dart';
import 'pauses.dart';
import 'shifts.dart';

class LogbookStore extends ChangeNotifier {
  LogbookStore(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'taxi_logbook_v1';
  List<Trip> _trips = [];
  List<ShiftRecord> _shifts = [];
  List<ShiftRecord> get shifts => List.unmodifiable(_shifts);
  bool get shiftsReady => true;
  List<PauseRecord> _pauses = [];
  List<PauseRecord> get pauses => List.unmodifiable(_pauses);
  bool get pausesReady => true;
  List<Expense> _expenses = [];
  List<Expense> get expenses => List.unmodifiable(_expenses);
  bool get expensesReady => true;
  List<String> _sources = ['Taxi', 'Uber', 'Bolt', 'FREENOW'];
  String _driverNumber = '';
  String get driverNumber => _driverNumber;
  /// Kilometers per fare are optional and hidden unless the driver turns them on.
  static const kilometersKey = 'kilometers_enabled';
  bool get kilometersEnabled => preferences.getBool(kilometersKey) ?? false;
  Future<void> setKilometersEnabled(bool value) async {
    await preferences.setBool(kilometersKey, value);
    notifyListeners();
  }
  String get driverLabel => driverNumber.isEmpty ? tr('Fahrer') : 'Fahrer $driverNumber';
  bool saving = false;

  bool get isCloud => false;
  bool get loading => false;
  // Unreadable local data must never be overwritten by a later save.
  String? _loadError;
  bool get ready => _loadError == null;
  bool get pendingWrites => false;
  String? get syncError => _loadError;
  /// Non-blocking notice, e.g. records that could not be read.
  String? get dataWarning => null;
  String get storageLabel => _loadError == null ? tr('Lokal') : 'Lokal (gesperrt)';
  Future<void> retry() async {}

  List<Trip> get trips => List.unmodifiable(_trips);
  List<String> get sources => List.unmodifiable(_sources);

  void load() {
    try {
      _load();
      _loadError = null;
    } catch (_) {
      // Fail visibly and read-only instead of silently overwriting records.
      // Cloud sign-in stays available because startup no longer aborts.
      _loadError = 'Lokale Einträge sind beschädigt und können nicht gelesen '
          'werden. Lokale Änderungen sind gesperrt, damit nichts überschrieben wird.';
    }
    notifyListeners();
  }

  void _load() {
    final raw = preferences.getString(storageKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final trips = (json['trips'] as List)
        .map((t) => Trip.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList();
    final sources = (json['sources'] as List).cast<String>();
    if (sources.isEmpty || sources.any((s) => s.trim().isEmpty)) {
      throw const FormatException('Ungültige Quellen.');
    }
    _pauses = (json['pauses'] as List? ?? []).map((p) => PauseRecord.fromJson(Map<String, dynamic>.from(p as Map))).toList();
    _shifts = (json['shifts'] as List? ?? []).map((v) => ShiftRecord.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    _expenses = (json['expenses'] as List? ?? []).map((v) => Expense.fromJson(Map<String, dynamic>.from(v as Map))).toList();
    _trips = trips;
    _sources = sources;
    _driverNumber = json['driverNumber'] as String? ?? '';
  }

  Future<void> _persist(List<Trip> trips, List<String> sources, {String? driverNumber, List<PauseRecord>? pauses, List<ShiftRecord>? shifts,
      List<Expense>? expenses}) async {
    final nextExpenses = expenses ?? _expenses;
    final nextNumber = driverNumber ?? _driverNumber;
    final nextPauses = pauses ?? _pauses;
    final nextShifts = shifts ?? _shifts;
    if (_loadError != null) throw StateError(_loadError!);
    if (saving) throw StateError('Speicherung läuft bereits.');
    saving = true;
    notifyListeners();
    try {
      final success = await preferences.setString(storageKey, jsonEncode({
        'version': 3,
        'shifts': nextShifts.map((s) => s.toJson()).toList(),
        'pauses': nextPauses.map((p) => p.toJson()).toList(),
        'expenses': nextExpenses.map((e) => e.toJson()).toList(),
        'driverNumber': nextNumber,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      }));
      if (!success) throw StateError('Speicherung nicht möglich.');
      // Update the visible state only after persistence succeeds.
      _shifts = nextShifts;
      _pauses = nextPauses;
      _expenses = nextExpenses;
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

  Future<void> saveExpense(Expense expense) => _persist([..._trips], [..._sources],
    expenses: [..._expenses.where((e) => e.id != expense.id), expense]);
  Future<void> deleteExpense(String id) => _persist([..._trips], [..._sources],
    expenses: _expenses.where((e) => e.id != id).toList());

  Future<void> saveShift(ShiftRecord shift) {
    validateShift(shifts, shift);
    return _persist([..._trips], [..._sources],
      shifts: [..._shifts.where((s) => s.id != shift.id), shift]);
  }
  Future<void> finishShift(ShiftRecord shift, DateTime end) {
    final finished = shift.finish(end);
    validateShift(shifts, finished);
    return _persist([..._trips], [..._sources],
      shifts: [..._shifts.where((s) => s.id != shift.id), finished],
      pauses: _pauses.map((p) => p.running && p.start.isBefore(end)
        ? p.finish(end) : p).toList());
  }

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
        'version': 3,
        'shifts': shifts.map((s) => s.toJson()).toList(),
        'pauses': pauses.map((p) => p.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'driverNumber': driverNumber,
        'trips': trips.map((t) => t.toJson()).toList(),
        'sources': sources,
      });
}

