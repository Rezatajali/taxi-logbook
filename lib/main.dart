import 'l10n.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_screen.dart';
import 'auth_service.dart';
import 'cloud_store.dart';
import 'firebase_web_options.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logbook.dart';
import 'store.dart';
import 'currency_input.dart';
import 'help_screen.dart';
import 'legal_screen.dart';
import 'palette.dart';
import 'extras_page.dart';
import 'install_screen.dart';
import 'pause_screen.dart';
import 'pdf_report.dart';
import 'package:printing/printing.dart';
import 'shifts.dart';
import 'shift_rules.dart';

// Colours follow the active light/dark palette (see palette.dart).
Color get ink => palette.ink;
Color get accent => palette.accent;
Color get canvas => palette.canvas;
Color get surface => palette.surface;
Color get primary => palette.primary;
Color get muted => palette.muted;
final euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');
String money(num cents) => euro.format(cents / 100);
String km(double value) => NumberFormat('0.0', 'de_DE').format(value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = LogbookStore(await SharedPreferences.getInstance());
    store.load();
    loadThemeMode(store.preferences);
    loadLanguage(store.preferences);
    Widget? home;
    if (kIsWeb) {
      await Firebase.initializeApp(options: firebaseWebOptions);
      await FirebaseAuth.instance.setLanguageCode('de');
      home = AuthGate(
        auth: FirebaseDriverAuth(FirebaseAuth.instance), localStore: store,
        createStore: (account) => CloudLogbookStore(store.preferences,
          FirestoreLogbookBackend(FirebaseFirestore.instance, account.uid)),
        homeBuilder: (data, account, exit, deleteAccount) => LogbookHome(store: data,
          accountEmail: account?.email, onExit: exit, onDeleteAccount: deleteAccount,
          onChangePassword: account == null ? null
              : () => FirebaseAuth.instance.sendPasswordResetEmail(email: account.email)),
      );
    }
    runApp(LogbookApp(store: store, home: home));
  } catch (_) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 20),
                const Text('Die App konnte nicht gestartet werden.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'Bitte die App neu öffnen. Vorhandene Daten werden nicht '
                  'überschrieben. Im Browser muss lokaler Speicher erlaubt sein.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class LogbookApp extends StatelessWidget {
  const LogbookApp({super.key, required this.store, this.home});
  final Widget? home;
  final LogbookStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeMode, language]),
    builder: (context, _) {
      palette = paletteFor(themeMode.value, MediaQuery.platformBrightnessOf(context));
      return MaterialApp(
        // Rebuild every page when the theme or the language changes.
        key: ValueKey('${palette.brightness}-${language.value}'),
        title: 'Taxi Logbuch',
        debugShowCheckedModeBanner: false,
        locale: language.value.locale,
        supportedLocales: [for (final l in AppLanguage.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(palette),
        home: home ?? LogbookHome(store: store),
      );
    },
  );
}

class LogbookHome extends StatefulWidget {
  const LogbookHome({super.key, required this.store, this.accountEmail, this.onExit,
    this.onDeleteAccount, this.onChangePassword});
  /// Sends a password-reset email to the signed-in driver.
  final Future<void> Function()? onChangePassword;
  final String? accountEmail;
  final VoidCallback? onExit;
  final Future<void> Function(String password)? onDeleteAccount;
  final LogbookStore store;
  @override
  State<LogbookHome> createState() => _LogbookHomeState();
}

class _LogbookHomeState extends State<LogbookHome> with WidgetsBindingObserver {
  Timer? workTimer;
  void updateWorkTimer() {
    if (widget.store.shifts.any((s) => s.running)) {
      workTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) { setState(() {}); enforceShiftRules(); }
      });
    } else {
      workTimer?.cancel();
      workTimer = null;
    }
  }
  @override
  void initState() {
    super.initState();
    widget.store.addListener(updateWorkTimer);
    updateWorkTimer();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => enforceShiftRules());
  }
  @override
  void didUpdateWidget(covariant LogbookHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(updateWorkTimer);
      widget.store.addListener(updateWorkTimer);
      updateWorkTimer();
    }
  }
  @override
  void dispose() {
    widget.store.removeListener(updateWorkTimer);
    workTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  // The selected day follows "today" until the driver picks another day, so an
  // app left open overnight (or for days) never files new fares under an old date.
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _dayFollowsToday = true;
  DateTime get day => _dayFollowsToday ? DateUtils.dateOnly(DateTime.now()) : _day;
  set day(DateTime value) {
    _day = DateUtils.dateOnly(value);
    _dayFollowsToday = DateUtils.isSameDay(value, DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: refresh "today" and the date-based views.
    if (state == AppLifecycleState.resumed && mounted) { setState(() {}); enforceShiftRules(); }
  }
  String? sourceFilter;
  PaymentMethod? paymentFilter;

  bool exportingPdf = false;

  Future<void> exportMonthPdf() async {
    setState(() => exportingPdf = true);
    try {
      final bytes = await buildMonthReport(trips: widget.store.trips,
        shifts: widget.store.shifts, month: month, driverLabel: widget.store.driverLabel);
      await Printing.sharePdf(bytes: bytes,
        filename: 'taxi-logbuch-${DateFormat('yyyy-MM').format(month)}.pdf');
    } catch (_) {
      if (mounted) message(tr('PDF konnte nicht erstellt werden.'));
    } finally {
      if (mounted) setState(() => exportingPdf = false);
    }
  }

  void message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> editTrip([Trip? trip]) async {
    final created = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => TripEditor(store: widget.store, trip: trip, initialDate: tab == 0 ? day : null),
    );
    if (created != null && mounted) offerShiftStart(created);
  }

  /// Shift rules after a new fare: start a shift automatically, unless the
  /// 11-hour rest after the last shift is not over yet.
  void offerShiftStart(Trip trip) {
    final store = widget.store;
    if (!store.shiftsReady || !store.ready) return;
    final now = DateTime.now();
    final inShift = store.shifts.any((s) => (s.running && !trip.at.isBefore(s.start)) ||
        (!trip.at.isBefore(s.start) && !trip.at.isAfter(s.end ?? now)));
    // Only for fares of the last 12 hours; older entries are corrections.
    if (inShift || now.difference(trip.at).abs() > maxShiftLength) return;
    final time = DateFormat('dd.MM. HH:mm');
    final rest = restUntil(store.shifts, trip.at);
    if (rest != null) {
      showMessage(const Key('rest-warning'),
        '${tr('Ruhezeit nicht eingehalten: neue Schicht erst ab')} ${time.format(rest.toLocal())}.');
      return;
    }
    final start = trip.at.isAfter(now) ? now : trip.at;
    final shift = ShiftRecord(id: 'shift-${now.microsecondsSinceEpoch}', start: start.toUtc(),
      origin: ShiftOrigin.timer);
    store.saveShift(shift).then((_) {
      if (mounted) {
        showMessage(const Key('shift-auto-started'),
          '${tr('Schicht automatisch gestartet. Spätestens Ende:')} ${time.format(shiftLatestEnd(shift).toLocal())}');
      }
    }).catchError((_) {});
  }

  void showMessage(Key key, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(key: key, duration: const Duration(seconds: 6), content: Text(text)));

  bool _enforcing = false;
  final _limitShown = <String>{};
  final _limitRoutes = <String, Route<void>>{};

  void _closeLimitDialog(String shiftId) {
    final route = _limitRoutes.remove(shiftId);
    if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
  }

  /// "12 hours reached" dialog. OK ends the shift now (at most start + 13 h).
  Future<void> showShiftLimitDialog(ShiftRecord shift) async {
    final route = DialogRoute<void>(context: context, barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('shift-limit-dialog'),
        icon: const Icon(Icons.timer_off_outlined),
        title: Text(tr('12 Stunden erreicht')),
        content: Text(tr('Du darfst heute nicht weiterarbeiten. Mit OK wird die Schicht beendet. Ohne OK wird sie nach spätestens 1 Stunde automatisch beendet.')),
        actions: [
          FilledButton(key: const Key('shift-limit-ok'), onPressed: () async {
            Navigator.pop(dialogContext);
            final current = widget.store.shifts.where((s) => s.id == shift.id && s.running).firstOrNull;
            if (current == null) return;
            final now = DateTime.now();
            final hard = shiftHardEnd(current);
            final end = now.isAfter(hard) ? hard : now;
            try {
              await widget.store.finishShift(current, end.toUtc());
              if (mounted) {
                showMessage(const Key('shift-ended-ok'),
                  '${tr('Schicht beendet. Ende:')} ${DateFormat('dd.MM. HH:mm').format(end)}');
              }
            } catch (_) {
              // The automatic close after the tolerance hour still applies.
            }
          }, child: const Text('OK')),
        ],
      ));
    _limitRoutes[shift.id] = route;
    await Navigator.of(context).push(route);
    _limitRoutes.remove(shift.id);
  }

  /// Closes running shifts after 12 h + 1 h tolerance (end = last fare).
  Future<void> enforceShiftRules() async {
    final store = widget.store;
    if (_enforcing || !store.ready || !store.shiftsReady || !store.pausesReady || store.saving) return;
    _enforcing = true;
    try {
      final now = DateTime.now();
      for (final shift in store.shifts.where((s) => s.running).toList()) {
        final end = automaticShiftEnd(shift, store.trips, now);
        if (end == null) {
          // 12 hours reached: tell the driver to stop. Without OK the shift is
          // closed automatically once the 1-hour tolerance is over.
          if (!now.isBefore(shiftLatestEnd(shift)) && _limitShown.add(shift.id) && mounted) {
            showShiftLimitDialog(shift);
          }
          continue;
        }
        _closeLimitDialog(shift.id);
        await store.finishShift(shift, end.toUtc());
        if (mounted) {
          showMessage(const Key('shift-auto-ended'),
            '${tr('Schicht nach 12 Stunden automatisch beendet. Ende:')} '
            '${DateFormat('dd.MM. HH:mm').format(end.toLocal())}');
        }
      }
    } catch (_) {
      // Retried on the next timer tick or when the app is opened again.
    } finally {
      _enforcing = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                child: Image.asset('branding/logo.png', width: 40, height: 40)),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.store.driverNumber.isEmpty ? 'Taxi Logbuch' : widget.store.driverLabel, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            actions: [
              IconButton(tooltip: tr('Hilfe · Anleitung'), icon: const Icon(Icons.help_outline),
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()))),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  child: Column(children: [
                  if (widget.store.loading) const Padding(
                    padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                  if (widget.store.syncError != null) Card(child: Padding(
                    padding: const EdgeInsets.all(16), child: Column(children: [
                      Text(widget.store.syncError!),
                      TextButton(onPressed: widget.store.retry, child: Text(tr('Erneut versuchen'))),
                    ]))),
                  if (widget.store.dataWarning != null) Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(widget.store.dataWarning!, key: const Key('data-warning')))),
                  if (widget.store.pendingWrites) Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(tr('Änderungen warten auf Synchronisierung. Bitte Internetverbindung herstellen.'))),
                  switch (tab) {
                    0 => tripsPage(),
                    1 => PausesPanel(store: widget.store),
                    2 => monthPage(),
                    3 => ExtrasPage(store: widget.store),
                    _ => settingsPage(),
                  },
                ]),
                ),
              ),
            ),
          ),
          floatingActionButton: tab != 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: (widget.store.saving || !widget.store.ready) ? null : () => editTrip(),
                  backgroundColor: primary,
                  foregroundColor: palette.onPrimary,
                  icon: Icon(Icons.add),
                  label: Text(tr('Fahrt erfassen')),
                ),
          bottomNavigationBar: NavigationBar(
            backgroundColor: surface,
            indicatorColor: primary.withValues(alpha: 0.18),
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: [
              NavigationDestination(icon: Icon(Icons.local_taxi_outlined),
                  selectedIcon: Icon(Icons.local_taxi), label: tr('Fahrten')),
              NavigationDestination(icon: Icon(Icons.pause_circle_outline), label: tr('Schichten')),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: tr('Monat')),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: tr('Extras')),
              NavigationDestination(icon: Icon(Icons.person_outline), label: tr('Profil')),
            ],
          ),
        ),
      );

  Widget title(String text, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: muted)),
        ]),
      );

  Widget heroCard(String label, int total, String detail) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [palette.heroStart, palette.heroEnd]),
          border: Border.all(color: primary.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(money(total), style: const TextStyle(
                color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Text(detail, style: TextStyle(color: primary)),
          const SizedBox(height: 8),
          Text(tr('Umsatz vor Kosten und Provisionen'),
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget panel(String heading, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget metrics(List<(String, String, IconData)> values) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: LayoutBuilder(builder: (context, constraints) {
          // Up to three tiles fit side by side on a phone.
          final columns = constraints.maxWidth >= 640 || values.length <= 3 ? values.length : 2;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final value in values)
              Container(
                width: width,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Icon(value.$3, color: primary, size: 22),
                  const SizedBox(height: 12),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value.$2, style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: ink))),
                  const SizedBox(height: 4),
                  Text(value.$1, style: TextStyle(
                      fontSize: 12, color: muted)),
                ]),
              ),
          ]);
        }),
      );

  Widget emptyState(String heading, String detail) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.receipt_long_outlined, size: 36, color: ink),
          const SizedBox(height: 12),
          Text(heading, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(detail, style: TextStyle(color: muted)),
        ]),
      );

  Widget breakdown(Map<String, int> entries, int total) =>
      Column(children: entries.entries.map((entry) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(entry.key)),
            Text(money(entry.value),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : entry.value / total,
              minHeight: 6,
              color: primary,
              backgroundColor: canvas,
            ),
          ),
        ]),
      )).toList());

  Future<void> deleteTrip(Trip trip) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Fahrt löschen?')),
      content: Text('${money(trip.cents)} · ${trip.source} wird entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen'))),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try { await widget.store.deleteTrip(trip.id); }
    catch (_) { if (mounted) message(tr('Löschen nicht möglich. Bitte erneut versuchen.')); }
  }

  Future<void> showHistory(Trip trip) => showDialog<void>(context: context,
    builder: (context) => AlertDialog(title: Text(tr('Änderungsverlauf')),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final entry in trip.history.reversed) Padding(padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${entry['action']} · ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(entry['changedAt'] as String).toLocal())}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Vorher: ${money(entry['cents'] as int)} · ${entry['source']} · '
              '${PaymentMethod.values.byName(entry['payment'] as String).label}'),
            Text('Fahrt: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(entry['at'] as String))}'),
            if (entry['kilometers'] != null) Text('Strecke: ${entry['kilometers']} km'),
            if ((entry['note'] as String? ?? '').isNotEmpty) Text('Notiz: ${entry['note']}'),
          ])),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Schließen')))]));

  Widget tripTile(Trip trip) {
    final color = trip.deleted ? Colors.red.shade300 : trip.editedAt != null ? accent : ink;
    final style = TextStyle(fontWeight: FontWeight.w800, color: color,
      decoration: trip.deleted ? TextDecoration.lineThrough : null);
    final editable = !trip.deleted && widget.store.ready && !widget.store.saving;
    return Container(margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(color: palette.tile,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: trip.deleted || trip.editedAt != null
          ? color.withValues(alpha: 0.45) : palette.border)),
      child: Column(children: [
      ListTile(contentPadding: EdgeInsets.zero,
        title: Text(widget.store.driverLabel, style: style),
        // Fares after midnight belong to the shift day; show their real date.
        subtitle: Text('${DateFormat(sameDay(trip.at, day) ? 'HH:mm' : 'dd.MM. HH:mm').format(trip.at)} · ${trip.source} · '
          '${trip.payment.label}${trip.kilometers == null ? '' : ' · ${km(trip.kilometers!)} km'}',
          style: TextStyle(color: trip.deleted ? color : null,
            decoration: trip.deleted ? TextDecoration.lineThrough : null)),
        trailing: Text(money(trip.cents), style: style.copyWith(fontSize: 22)),
        onTap: editable ? () => editTrip(trip) : null),
      if (trip.deleted || trip.editedAt != null) Align(alignment: Alignment.centerLeft,
        child: Text(trip.deleted ? tr('Gelöscht · nicht im Umsatz') : tr('Bearbeitet'),
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
      if (!trip.deleted) Row(children: [
        Expanded(child: OutlinedButton.icon(key: ValueKey('edit-${trip.id}'),
          onPressed: editable ? () => editTrip(trip) : null,
          icon: const Icon(Icons.edit_outlined, size: 18), label: Text(tr('Bearbeiten')))),
        const SizedBox(width: 12),
        Expanded(child: TextButton.icon(key: ValueKey('delete-${trip.id}'),
          onPressed: editable ? () => deleteTrip(trip) : null,
          icon: const Icon(Icons.delete_outline, size: 18), label: Text(tr('Löschen')),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade300,
            minimumSize: const Size(0, 48)))),
      ]),
      if (trip.history.isNotEmpty) Align(alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: () => showHistory(trip),
          icon: const Icon(Icons.history, size: 18), label: Text(tr('Änderungsverlauf')))),
    ]));
  }

  static const _ignoredRepairsKey = 'ignored_date_repairs';

  List<(Trip, DateTime)> get pendingDateRepairs {
    final ignored = widget.store.preferences.getStringList(_ignoredRepairsKey) ?? const [];
    return misdatedTrips(widget.store.trips).where((e) => !ignored.contains(e.$1.id)).toList();
  }

  /// Lets the driver move fares that were filed under an old date (#bugfix).
  Future<void> reviewDateRepairs() async {
    final repairs = pendingDateRepairs;
    final selected = await showDialog<Set<String>>(context: context,
      builder: (_) => DateRepairDialog(repairs: repairs));
    if (selected == null || !mounted) return;
    final store = widget.store;
    final skipped = [for (final r in repairs) if (!selected.contains(r.$1.id)) r.$1.id];
    var fixed = 0;
    try {
      for (final (trip, corrected) in repairs.where((r) => selected.contains(r.$1.id))) {
        await store.saveTrip(Trip.fromJson({...trip.toJson(), 'at': corrected.toIso8601String()}));
        fixed++;
      }
      await store.preferences.setStringList(_ignoredRepairsKey,
        [...?store.preferences.getStringList(_ignoredRepairsKey), ...skipped]);
      if (mounted) message('$fixed ${tr('Fahrten korrigiert.')}');
    } catch (_) {
      if (mounted) message(tr('Nicht gespeichert. Bitte erneut versuchen.'));
    }
    if (mounted) setState(() {});
  }

  Widget tripsPage() {
    final shifts = widget.store.shifts;
    final dayTrips = tripsOnDay(widget.store.trips, day, shifts);
    final daily = TripSummary(dayTrips, shifts: shifts);
    final trips = dayTrips.where((t) =>
        (sourceFilter == null || t.source == sourceFilter) &&
        (paymentFilter == null || t.payment == paymentFilter)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title(tr('Deine Fahrten'), tr('Dein Tag. Jede Fahrt im Blick.')),
      if (widget.store.ready && pendingDateRepairs.isNotEmpty) Card(
        key: const Key('date-repair-banner'),
        color: Colors.amber.withValues(alpha: 0.18),
        child: ListTile(
          leading: const Icon(Icons.event_busy_outlined),
          title: Text('${pendingDateRepairs.length} ${tr('Fahrten mit falschem Datum gefunden')}'),
          subtitle: Text(tr('Sie wurden an einem späteren Tag eingegeben. Bitte prüfen.')),
          trailing: FilledButton(onPressed: widget.store.saving ? null : reviewDateRepairs,
            child: Text(tr('Prüfen'))),
        )),
      Container(padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
        IconButton(tooltip: tr('Vorheriger Tag'), icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day - 1))),
        Expanded(child: TextButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(DateFormat('dd.MM.yyyy').format(day),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: day,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null && mounted) setState(() => day = picked);
          },
        )),
        IconButton(tooltip: tr('Nächster Tag'), icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day + 1))),
      ])),
      const SizedBox(height: 12),
      metrics([
        (tr('Tagesumsatz'), money(daily.totalCents), Icons.payments_outlined),
        (tr('Davon bar'), money(daily.cashCents), Icons.account_balance_wallet_outlined),
        (tr('Uber Bar'), money(daily.uberCashCents), Icons.local_taxi_outlined),
      ]),
      dailyGoal(daily.totalCents),
      const SizedBox(height: 16),
      Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(key: const Key('fare-filters'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          collapsedBackgroundColor: surface, backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Icon(Icons.tune_rounded, color: primary),
          title: Text(tr('Filter'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sourceFilter == null && paymentFilter == null
            ? tr('Alle Quellen und Zahlungen') : '${sourceFilter ?? 'Alle Quellen'} · ${paymentFilter?.label ?? 'Alle Zahlungen'}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
      DropdownButtonFormField<String>(
        key: ValueKey('source-filter-$sourceFilter'),
        initialValue: sourceFilter ?? '',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Quelle filtern')),
        items: [
          DropdownMenuItem(value: '', child: Text(tr('Alle Quellen'))),
          for (final s in widget.store.sources)
            DropdownMenuItem(value: s, child: Text(s)),
        ],
        onChanged: (value) => setState(() => sourceFilter = value == '' ? null : value),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(label: Text(tr('Alle Zahlungen')), selected: paymentFilter == null,
            onSelected: (_) => setState(() => paymentFilter = null)),
        for (final method in PaymentMethod.values)
          ChoiceChip(label: Text(method.label), selected: paymentFilter == method,
              onSelected: (_) => setState(() => paymentFilter = method)),
      ]),
            if (sourceFilter != null || paymentFilter != null) TextButton.icon(
              onPressed: () => setState(() { sourceFilter = null; paymentFilter = null; }),
              icon: const Icon(Icons.restart_alt), label: Text(tr('Filter zurücksetzen'))),
          ])),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text('${TripSummary(trips).trips.length} Fahrten',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        Text(money(TripSummary(trips).totalCents), style: TextStyle(color: muted)),
      ]),
      const SizedBox(height: 14),
          trips.isEmpty
            ? emptyState(tr('Keine passenden Fahrten.'), tr('Wähle einen anderen Tag oder erfasse eine Fahrt.'))
            : Column(children: trips.map(tripTile).toList()),
    ]);
  }

  Widget monthPage() {
    final summary = TripSummary(tripsInMonth(widget.store.trips, month, widget.store.shifts),
        shifts: widget.store.shifts);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title(tr('Dein Monatsbericht'), tr('Umsatz, Entwicklung und Quellen auf einen Blick.')),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: tr('Vorheriger Monat'), icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text(DateFormat('MMMM yyyy', dateLocale).format(month),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        IconButton(tooltip: tr('Nächster Monat'), icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 12),
      weekCompare(),
      heroCard(tr('Monatsumsatz'), summary.totalCents,
          '${summary.trips.length} Fahrten · ${summary.workingDays} Tage mit Fahrten'),
      metrics([
        (tr('Ø Tag mit Fahrten'), money(summary.averageWorkingDayCents), Icons.trending_up),
        (tr('Bar erhalten'), money(summary.cashCents), Icons.payments_outlined),
        (tr('Uber Bar'), money(summary.uberCashCents), Icons.local_taxi_outlined),
      ]),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        key: const Key('month-pdf'),
        onPressed: exportingPdf ? null : exportMonthPdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(tr('Monatsbericht als PDF')))),
      panel(tr('Umsatz pro Tag'), DailyChart(key: ValueKey(month),
          month: month, values: summary.dailyCents(month))),
      panel(tr('Umsatz nach Quelle'), summary.trips.isEmpty
          ? Text(tr('Mit deiner ersten Fahrt erscheint hier die Aufteilung.'))
          : breakdown(summary.bySource, summary.totalCents)),
      panel(tr('Umsatz nach Zahlungsart'), breakdown(summary.paymentBreakdown, summary.totalCents)),
      const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text('Der Durchschnitt berücksichtigt Tage mit mindestens einer '
            'erfassten Fahrt. Freie Tage werden nicht mitgerechnet.',
            style: TextStyle(fontSize: 12)),
      ),
    ]);
  }

  Future<void> addSource() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Neue Quelle')),
      content: TextField(controller: controller, autofocus: true, maxLength: 40,
          decoration: InputDecoration(labelText: tr('Name, z. B. Zentrale'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text),
            child: Text(tr('Hinzufügen'))),
      ],
    ));
    // The dialog's route can still animate out using its controller.
    if (value == null || !mounted) return;
    try {
      await widget.store.addSource(value);
    } catch (_) {
      if (mounted) message(tr('Quelle konnte nicht gespeichert werden. Bitte 1–40 Zeichen eingeben.'));
    }
  }

  Future<void> changeDriverNumber() async {
    final controller = TextEditingController(text: widget.store.driverNumber);
    final formKey = GlobalKey<FormState>();
    final number = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(tr('Deine Fahrernummer')),
      content: Form(key: formKey, child: TextFormField(
        key: Key('driver-number-input'), controller: controller,
        autofocus: true, keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        decoration: InputDecoration(labelText: tr('Fahrernummer'), hintText: 'z. B. 267'),
        validator: (value) => (value ?? '').trim().isEmpty || RegExp(r'^\d{1,10}$').hasMatch(value!.trim())
          ? null : tr('Bitte nur Ziffern eingeben.'),
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () {
          if (formKey.currentState!.validate()) Navigator.pop(dialogContext, controller.text.trim());
        }, child: Text(tr('Speichern'))),
      ],
    ));
    // Keep the controller alive while the closing dialog animates.
    if (number == null || !mounted) return;
    try {
      await widget.store.saveDriverNumber(number);
      if (mounted) message(tr('Fahrernummer gespeichert.'));
    } catch (_) {
      if (mounted) message(tr('Fahrernummer konnte nicht gespeichert werden.'));
    }
  }

  /// Password change: Firebase emails a link where the driver sets a new password.
  Future<void> changePassword() async {
    final email = widget.accountEmail!;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(tr('Passwort ändern')),
      content: Text('${tr('Wir senden dir einen Link zum Festlegen eines neuen Passworts an:')}\n\n$email'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Abbrechen'))),
        FilledButton(key: const Key('send-password-link'),
          onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Link senden'))),
      ],
    ));
    if (ok != true || !mounted) return;
    try {
      await widget.onChangePassword!();
      if (mounted) {
        message(tr('Link gesendet. Bitte E-Mail öffnen (auch Spam prüfen) und dort ein neues Passwort festlegen.'));
      }
    } catch (error) {
      if (mounted) message(authError(error));
    }
  }

  Future<void> changeDailyGoal() async {
    final store = widget.store;
    final controller = TextEditingController(text: store.dailyGoalCents == 0 ? ''
        : (store.dailyGoalCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    final value = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(tr('Tagesziel')),
      content: TextField(key: const Key('daily-goal-input'), controller: controller, autofocus: true,
        keyboardType: TextInputType.number, inputFormatters: const [CentsInputFormatter()],
        decoration: InputDecoration(labelText: tr('Betrag'), suffixText: '€',
          helperText: tr('Leer lassen zum Ausschalten.'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(tr('Speichern'))),
      ],
    ));
    if (value == null || !mounted) return;
    await store.setDailyGoalCents(value.trim().isEmpty ? 0 : (parseCents(value) ?? 0));
  }

  /// Progress toward the daily goal on the Fahrten page (#4).
  Widget dailyGoal(int revenue) {
    final goal = widget.store.dailyGoalCents;
    if (goal <= 0) return const SizedBox.shrink();
    final reached = revenue >= goal;
    return Container(
      key: const Key('daily-goal'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(reached ? Icons.emoji_events : Icons.flag_outlined, color: reached ? palette.money : primary),
          const SizedBox(width: 8),
          Expanded(child: Text(reached ? tr('Tagesziel erreicht!') : tr('Tagesziel'),
            style: const TextStyle(fontWeight: FontWeight.w800))),
          Text('${money(revenue)} / ${money(goal)}', style: TextStyle(color: muted)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
          value: (revenue / goal).clamp(0, 1).toDouble(), minHeight: 12,
          color: reached ? palette.money : primary,
          backgroundColor: primary.withValues(alpha: 0.15))),
      ]),
    );
  }

  /// This week vs. last week on the month page (#5).
  Widget weekCompare() {
    final store = widget.store;
    final start = weekStart(DateTime.now());
    final thisWeek = weekRevenue(store.trips, start, store.shifts);
    final lastWeek = weekRevenue(store.trips, DateTime(start.year, start.month, start.day - 7), store.shifts);
    final change = lastWeek == 0 ? null : ((thisWeek - lastWeek) * 100 / lastWeek).round();
    return Container(
      key: const Key('week-compare'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Diese Woche'), style: TextStyle(color: muted, fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(money(thisWeek),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink))),
        ])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Letzte Woche'), style: TextStyle(color: muted, fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(money(lastWeek),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: muted))),
        ])),
        if (change != null) Text('${change >= 0 ? '▲' : '▼'} ${change.abs()} %',
          style: TextStyle(fontWeight: FontWeight.w800,
            color: change >= 0 ? palette.money : Theme.of(context).colorScheme.error)),
      ]),
    );
  }

  Widget settingsPage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title(tr('Dein Logbuch'), tr('Deine Fahrernummer und dein Konto.')),
        panel(tr('Sprache'), Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in AppLanguage.values)
            ChoiceChip(key: ValueKey('language-${l.name}'), label: Text(l.label),
              selected: language.value == l,
              onSelected: (_) => saveLanguage(widget.store.preferences, l)),
        ])),
        panel(tr('Darstellung'), SizedBox(width: double.infinity, child: SegmentedButton<ThemeMode>(
          key: Key('theme-mode'),
          segments: [
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text(tr('Auto'))),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text(tr('Hell'))),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text(tr('Dunkel'))),
          ],
          selected: {themeMode.value},
          onSelectionChanged: (value) => saveThemeMode(widget.store.preferences, value.single),
        ))),
        Card(child: ListTile(leading: const Icon(Icons.menu_book_outlined),
          title: Text(tr('Hilfe · Anleitung')), subtitle: Text(tr('Mit Bildern Schritt für Schritt')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const HelpScreen())))),
        Card(child: ListTile(leading: const Icon(Icons.add_to_home_screen),
          title: Text(tr('App aufs Handy holen')),
          subtitle: Text(tr('Symbol auf dem Home-Bildschirm – iPhone und Android')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const InstallScreen())))),
        Card(child: ListTile(key: const Key('daily-goal-setting'),
          leading: const Icon(Icons.flag_outlined),
          title: Text(tr('Tagesziel')),
          subtitle: Text(widget.store.dailyGoalCents == 0 ? tr('Aus') : money(widget.store.dailyGoalCents)),
          trailing: const Icon(Icons.chevron_right),
          onTap: changeDailyGoal)),
        panel(tr('Deine Fahrernummer'), Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.store.driverNumber.isEmpty ? tr('Noch keine Nummer eingetragen') : widget.store.driverLabel,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton.icon(key: const Key('change-driver-number'),
              onPressed: widget.store.saving || !widget.store.ready ? null : changeDriverNumber,
              icon: const Icon(Icons.badge_outlined), label: Text(tr('Nummer ändern'))),
          ])),
        if (widget.onExit != null) panel(widget.store.isCloud ? tr('Dein Konto') : tr('Lokale Vorschau'),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.accountEmail != null) Text(widget.accountEmail!),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: widget.store.saving || widget.store.pendingWrites
              ? null : widget.onExit, icon: const Icon(Icons.logout),
              label: Text(widget.store.isCloud ? tr('Abmelden') : tr('Zur Anmeldung'))),
            if (widget.onChangePassword != null && widget.accountEmail != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(key: const Key('change-password'),
                onPressed: changePassword,
                icon: const Icon(Icons.lock_reset_outlined), label: Text(tr('Passwort ändern'))),
            ],
            if (widget.onDeleteAccount != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(key: const Key('delete-account'),
                onPressed: widget.store.saving ? null : () => showDialog<void>(context: context,
                  builder: (_) => DeleteAccountDialog(onDelete: widget.onDeleteAccount!)),
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                icon: const Icon(Icons.delete_forever_outlined), label: Text(tr('Konto löschen'))),
            ],
          ])),
        Card(child: ListTile(leading: const Icon(Icons.gavel_outlined),
          title: Text(tr('Impressum · Datenschutz')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const LegalScreen())))),
        Padding(padding: const EdgeInsets.only(top: 16), child: Chip(
          avatar: const Icon(Icons.cloud_done_outlined, size: 18), label: Text(widget.store.storageLabel))),
        panel(widget.store.isCloud ? tr('Cloud-Speicherung') : tr('Speicherung auf diesem Gerät'),
          Text(widget.store.isCloud
            ? 'Jede Fahrt wird separat in deinem Konto gespeichert. Mit derselben '
              'E-Mail kannst du deine Fahrten auf anderen Geräten öffnen. '
              'Bei „Offline / Cache“ stammen Daten aus dem Zwischenspeicher; '
              'ausstehende Änderungen benötigen eine Internetverbindung.'
            : 'Diese Vorschau speichert nur lokal in diesem Browser. Einträge '
              'werden nicht automatisch in ein Cloud-Konto übernommen. '
              'Bitte eine Exportkopie sichern. Die Android-Testversion ist '
              'bis zur eigenen Firebase-Registrierung ebenfalls lokal.')),
        panel(tr('Deine Fahrtquellen'), Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8,
                children: widget.store.sources.map((s) => Chip(label: Text(s))).toList()),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: (widget.store.saving || !widget.store.ready) ? null : addSource,
                icon: const Icon(Icons.add), label: Text(tr('Quelle hinzufügen'))),
          ],
        )),
        panel(tr('Daten exportieren'), Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alle Fahrten, Änderungsverläufe, Pausen und Quellen als JSON in die Zwischenablage '
                'kopieren und anschließend in einer Datei sichern.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: widget.store.exportJson()));
                  if (mounted) message(tr('Export kopiert. Bitte in einer Datei sichern.'));
                } catch (_) {
                  if (mounted) message(tr('Kopieren nicht möglich.'));
                }
              },
              icon: const Icon(Icons.copy_all_outlined), label: Text(tr('Export kopieren')),
            ),
          ],
        )),
        Card(child: SwitchListTile(
          key: const Key('kilometers-switch'),
          secondary: const Icon(Icons.route_outlined),
          title: Text(tr('Kilometer pro Fahrt erfassen')),
          subtitle: const Text('Standardmäßig aus. Eingeschaltet erscheint im '
              'Fahrtformular ein Feld für die Strecke.'),
          value: widget.store.kilometersEnabled,
          onChanged: (value) => widget.store.setKilometersEnabled(value),
        )),
      ]);
}

class DailyChart extends StatefulWidget {
  const DailyChart({super.key, required this.month, required this.values});
  final DateTime month;
  final List<int> values;
  @override
  State<DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<DailyChart> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final maximum = widget.values.fold<int>(0, (a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(selected == null
          ? tr('Tippe auf einen Tag für den Betrag.')
          : '${selected! + 1}. ${DateFormat('MMMM', dateLocale).format(widget.month)}: '
              '${money(widget.values[selected!])}'),
      const SizedBox(height: 20),
      Text('Skala bis ${money(maximum)}', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: 190,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < widget.values.length; i++)
              Semantics(
                button: true,
                label: 'Tag ${i + 1}: ${money(widget.values[i])}',
                child: InkWell(
                  onTap: () => setState(() => selected = i),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 32, child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 18,
                        height: maximum == 0 || widget.values[i] == 0
                            ? 3 : (widget.values[i] / maximum * 145).clamp(3, 145).toDouble(),
                        decoration: BoxDecoration(
                          color: selected == i ? accent : widget.values[i] == 0
                              ? palette.border : primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 8),
                    ],
                  )),
                ),
              ),
          ]),
        ),
      ),
      if (maximum == 0) Text(tr('Für diesen Monat sind noch keine Umsätze erfasst.')),
    ]);
  }
}

class TripEditor extends StatefulWidget {
  const TripEditor({super.key, required this.store, this.trip, this.initialDate});
  final DateTime? initialDate;
  final LogbookStore store;
  final Trip? trip;
  @override
  State<TripEditor> createState() => _TripEditorState();
}

class _TripEditorState extends State<TripEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount;
  late final TextEditingController tip;
  late final TextEditingController distance;
  late final TextEditingController note;
  late DateTime at;
  late String tripId;
  late String source;
  late PaymentMethod payment;
  bool busy = false;
  String? error;

  FareType get selectedType => fareTypes.firstWhere(
      (type) => type.matches(source, payment),
      orElse: () => FareType('$source · ${payment.label}', source, payment));

  Future<void> chooseType() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final current = selectedType;
    final choices = [
      ...fareTypes,
      for (final name in widget.store.sources)
        if (!fareTypes.any((type) => type.source == name))
          FareType(name, name, PaymentMethod.platform),
    ];
    if (!choices.any((type) => type.matches(source, payment))) {
      choices.add(current);
    }
    final index = choices.indexWhere((type) => type.matches(source, payment));
    final picked = await showModalBottomSheet<FareType>(
      context: context,
      useSafeArea: true,
      backgroundColor: surface,
      builder: (_) => FareTypePicker(choices: choices, initialIndex: index < 0 ? 0 : index),
    );
    if (picked != null && mounted) {
      setState(() { source = picked.source; payment = picked.payment; });
    }
  }

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    tripId = trip?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    amount = TextEditingController(text: trip == null ? ''
        : (trip.cents / 100).toStringAsFixed(2).replaceAll('.', ','));
    tip = TextEditingController(text: (trip?.tipCents ?? 0) == 0 ? ''
        : (trip!.tipCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    distance = TextEditingController(text: trip?.kilometers == null ? ''
        : trip!.kilometers.toString().replaceAll('.', ','));
    note = TextEditingController(text: trip?.note ?? '');
    final now = DateTime.now();
    final date = widget.initialDate ?? now;
    at = trip?.at ?? DateTime(date.year, date.month, date.day, now.hour, now.minute);
    source = trip?.source ?? widget.store.sources.first;
    payment = trip?.payment ?? PaymentMethod.cash;
  }

  @override
  void dispose() {
    amount.dispose();
    tip.dispose();
    distance.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final saved = Trip(
        id: tripId,
        at: at,
        cents: parseCents(amount.text)!,
        tipCents: tip.text.trim().isEmpty ? 0 : parseCents(tip.text)!,
        source: source,
        payment: payment,
        kilometers: parseKilometers(distance.text),
        note: note.text.trim(),
      );
      await widget.store.saveTrip(saved);
      if (mounted) Navigator.pop(context, widget.trip == null ? saved : null);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = tr('Nicht gespeichert. Bitte erneut versuchen.');
        });
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Fahrt löschen?')),
      content: Text(tr('Die Fahrt bleibt als gelöscht sichtbar und zählt nicht mehr zum Umsatz.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen'))),
      ],
    ));
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.store.deleteTrip(widget.trip!.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { busy = false; error = tr('Löschen nicht möglich.'); });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(key: form, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: Text(widget.trip == null ? tr('Fahrt erfassen') : tr('Fahrt bearbeiten'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink))),
              IconButton(tooltip: tr('Schließen'), onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: TextFormField(
                key: const Key('amount'),
                controller: amount,
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: const [CentsInputFormatter()],
                decoration: InputDecoration(labelText: tr('Betrag'), suffixText: '€',
                  hintText: '0,00', helperText: '2270 → 22,70 €'),
                validator: (v) => parseCents(v ?? '') == null
                    ? tr('Betrag größer als 0; maximal 2 Nachkommastellen.') : null,
              )),
              const SizedBox(width: 12),
              SizedBox(width: 130, child: InkWell(
                key: const Key('fare-type-button'),
                onTap: busy ? null : chooseType,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: InputDecoration(labelText: tr('Art')),
                  child: Row(children: [
                    Expanded(child: Text(selectedType.label, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    Icon(Icons.unfold_more_rounded, size: 20, color: primary),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('tip'),
              controller: tip,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: const [CentsInputFormatter()],
              decoration: InputDecoration(labelText: tr('Trinkgeld (optional)'),
                suffixText: '€', prefixIcon: Icon(Icons.volunteer_activism_outlined)),
              validator: (v) => (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                  ? tr('Trinkgeld größer als 0 oder leer lassen.') : null,
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(key: const Key('trip-date'),
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(DateFormat('dd.MM.yyyy').format(at),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                onPressed: busy ? null : () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final date = await showDatePicker(context: context,
                    initialDate: at, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (date != null && mounted) {
                    setState(() => at = DateTime(date.year, date.month, date.day, at.hour, at.minute));
                  }
                },
              ),
              OutlinedButton.icon(key: const Key('trip-time'),
                icon: const Icon(Icons.schedule_outlined),
                label: Text(DateFormat('HH:mm').format(at)),
                onPressed: busy ? null : () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final time = await showTimePicker(context: context,
                    initialTime: TimeOfDay.fromDateTime(at));
                  if (time != null && mounted) {
                    setState(() => at = DateTime(at.year, at.month, at.day, time.hour, time.minute));
                  }
                },
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: busy ? null : save,
              icon: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(tr('Fahrt speichern')),
            )),
            if (widget.trip != null) Center(child: TextButton.icon(
              onPressed: busy ? null : delete,
              icon: const Icon(Icons.delete_outline), label: Text(tr('Fahrt löschen')),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            )),

            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(tr('Weitere Angaben (optional)'), style: TextStyle(fontSize: 16)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(source),
                    initialValue: source,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Fahrtquelle')),
                    items: widget.store.sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: busy ? null : (value) => setState(() => source = value!),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final method in PaymentMethod.values)
                      ChoiceChip(label: Text(method.label), selected: payment == method,
                          onSelected: busy ? null : (_) => setState(() => payment = method)),
                  ]),
            if (widget.store.kilometersEnabled || widget.trip?.kilometers != null) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: distance,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Fahrtstrecke (optional)'), suffixText: 'km'),
              validator: (v) => (v ?? '').trim().isNotEmpty && parseKilometers(v!) == null
                  ? tr('Bitte eine Strecke größer als 0 und bis 10.000 km eingeben.') : null,
            ),
            ],
            const SizedBox(height: 16),
            TextFormField(controller: note, enabled: !busy, maxLength: 250,
                decoration: InputDecoration(labelText: tr('Notiz (optional)'))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 16),
          ],
        )),
      ),
    ),
  );
}

class FareTypePicker extends StatefulWidget {
  const FareTypePicker({super.key, required this.choices, required this.initialIndex});
  final List<FareType> choices;
  final int initialIndex;
  @override
  State<FareTypePicker> createState() => _FareTypePickerState();
}

class _FareTypePickerState extends State<FareTypePicker> {
  late int index;
  late final FixedExtentScrollController controller;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    controller = FixedExtentScrollController(initialItem: index);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
          Expanded(child: Text(tr('Art auswählen'), textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton(key: const Key('apply-fare-type'),
              onPressed: () => Navigator.pop(context, widget.choices[index]),
              child: Text(tr('Fertig'))),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 210, child: CupertinoPicker(
          key: const Key('fare-type-wheel'),
          scrollController: controller,
          itemExtent: 48,
          useMagnifier: true,
          magnification: 1.1,
          onSelectedItemChanged: (value) => index = value,
          children: widget.choices.map((type) => Center(child: Text(type.label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 21)))).toList(),
        )),
      ]),
    ),
  );
}

/// Asks for the password and deletes the account with all its data.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.onDelete});
  final Future<void> Function(String password) onDelete;
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() { password.dispose(); super.dispose(); }

  Future<void> delete() async {
    if (password.text.isEmpty || busy) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.onDelete(password.text);
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() { busy = false; error = authError(failure); });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Konto löschen?')),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Alle Fahrten, Schichten, Pausen, Kosten und dein Konto werden endgültig gelöscht. Das kann nicht rückgängig gemacht werden.')),
      const SizedBox(height: 16),
      TextField(key: const Key('delete-password'), controller: password, obscureText: true,
        enabled: !busy, decoration: InputDecoration(labelText: tr('Passwort zur Bestätigung'))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
      FilledButton(key: const Key('confirm-delete-account'), onPressed: busy ? null : delete,
        style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
        child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(tr('Endgültig löschen'))),
    ],
  );
}

/// Lists fares filed under an old date with their suggested date; all checked.
class DateRepairDialog extends StatefulWidget {
  const DateRepairDialog({super.key, required this.repairs});
  final List<(Trip, DateTime)> repairs;
  @override
  State<DateRepairDialog> createState() => _DateRepairDialogState();
}

class _DateRepairDialogState extends State<DateRepairDialog> {
  late final Set<String> selected = {for (final r in widget.repairs) r.$1.id};

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd.MM. HH:mm');
    return AlertDialog(
      title: Text(tr('Datum korrigieren')),
      content: SizedBox(width: 420, child: ListView(shrinkWrap: true, children: [
        Text(tr('Diese Fahrten wurden später eingegeben, als ihr Datum sagt. Ausgewählte Fahrten werden auf den Tag der Eingabe verschoben (Uhrzeit bleibt).')),
        const SizedBox(height: 8),
        for (final (trip, corrected) in widget.repairs) CheckboxListTile(
          key: ValueKey('repair-${trip.id}'),
          contentPadding: EdgeInsets.zero,
          value: selected.contains(trip.id),
          onChanged: (value) => setState(() =>
              value == true ? selected.add(trip.id) : selected.remove(trip.id)),
          title: Text('${money(trip.cents)} · ${trip.source}'),
          subtitle: Text('${date.format(trip.at)}  →  ${date.format(corrected)}'),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
        FilledButton(key: const Key('apply-date-repair'),
          onPressed: () => Navigator.pop(context, selected), child: Text(tr('Korrigieren'))),
      ],
    );
  }
}
