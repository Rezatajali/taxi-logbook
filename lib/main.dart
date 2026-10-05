import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logbook.dart';
import 'store.dart';

const ink = Color(0xFF153E35);
const accent = Color(0xFFF3C45D);
const canvas = Color(0xFFF5F6F2);
final euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');
String money(num cents) => euro.format(cents / 100);
String km(double value) => NumberFormat('0.0', 'de_DE').format(value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = LogbookStore(await SharedPreferences.getInstance());
    store.load();
    runApp(LogbookApp(store: store));
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
                const Text('Lokale Daten können nicht geladen werden.',
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
  const LogbookApp({super.key, required this.store});
  final LogbookStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Taxi Logbuch',
        debugShowCheckedModeBanner: false,
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: ink),
          scaffoldBackgroundColor: canvas,
          appBarTheme: const AppBarTheme(
            backgroundColor: canvas,
            foregroundColor: ink,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: canvas,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        home: LogbookHome(store: store),
      );
}

class LogbookHome extends StatefulWidget {
  const LogbookHome({super.key, required this.store});
  final LogbookStore store;
  @override
  State<LogbookHome> createState() => _LogbookHomeState();
}

class _LogbookHomeState extends State<LogbookHome> {
  int tab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime day = DateUtils.dateOnly(DateTime.now());
  String? sourceFilter;
  PaymentMethod? paymentFilter;

  void message(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> editTrip([Trip? trip]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => TripEditor(store: widget.store, trip: trip),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Row(children: [
              Icon(Icons.local_taxi_rounded, color: ink),
              SizedBox(width: 10),
              Expanded(child: Text('Taxi Logbuch', overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: const Icon(Icons.phone_android, size: 16),
                  label: const Text('Lokal'),
                  side: BorderSide.none,
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  child: switch (tab) {
                    0 => todayPage(),
                    1 => tripsPage(),
                    2 => monthPage(),
                    _ => settingsPage(),
                  },
                ),
              ),
            ),
          ),
          floatingActionButton: tab == 3
              ? null
              : FloatingActionButton.extended(
                  onPressed: widget.store.saving ? null : () => editTrip(),
                  backgroundColor: accent,
                  foregroundColor: ink,
                  icon: const Icon(Icons.add),
                  label: const Text('Fahrt erfassen'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard), label: 'Heute'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long), label: 'Fahrten'),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Monat'),
              NavigationDestination(icon: Icon(Icons.tune), label: 'Mehr'),
            ],
          ),
        ),
      );

  Widget title(String text, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
        ]),
      );

  Widget heroCard(String label, int total, String detail) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: ink,
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
          Text(detail, style: const TextStyle(color: accent)),
          const SizedBox(height: 8),
          const Text('Umsatz vor Kosten und Provisionen',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget panel(String heading, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE4E9E3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 16),
          child,
        ]),
      );

  Widget metrics(List<(String, String, IconData)> values) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 640 ? values.length : 2;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final value in values)
              Container(
                width: width,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Icon(value.$3, color: ink, size: 22),
                  const SizedBox(height: 12),
                  Text(value.$2, style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                  const SizedBox(height: 4),
                  Text(value.$1, style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700)),
                ]),
              ),
          ]);
        }),
      );

  Widget todayPage() {
    final now = DateTime.now();
    final trips = widget.store.trips.where((t) => sameDay(t.at, now)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final summary = TripSummary(trips);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title('Dein Tag im Überblick', DateFormat('EEEE, d. MMMM', 'de_DE').format(now)),
      heroCard('Umsatz heute', summary.totalCents, '${trips.length} Fahrten erfasst'),
      metrics([
        ('Bar erhalten', money(summary.cashCents), Icons.payments_outlined),
        ('Ohne Barzahlung', money(summary.totalCents - summary.cashCents),
            Icons.credit_card_outlined),
        ('Erfasste Fahrt-km', km(summary.totalKilometers), Icons.route_outlined),
        ('Umsatz / Fahrt-km', summary.eurosPerKilometer == null
            ? '—' : '${euro.format(summary.eurosPerKilometer)} / km',
            Icons.speed_outlined),
      ]),
      if (summary.tripsWithDistance > 0)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('€/km nur aus ${summary.tripsWithDistance} Fahrten mit '
              'Kilometerangabe. Leerfahrten sind nicht enthalten.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
      panel('Zahlungsarten', breakdown({
        for (final entry in summary.byPayment.entries)
          entry.key.label: entry.value,
      }, summary.totalCents)),
      panel('Letzte Fahrten', trips.isEmpty
          ? emptyState('Noch keine Fahrt heute.',
              'Tippe auf „Fahrt erfassen“, um deinen Umsatz festzuhalten.')
          : Column(children: trips.take(5).map(tripTile).toList())),
    ]);
  }

  Widget emptyState(String heading, String detail) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.receipt_long_outlined, size: 36, color: ink),
          const SizedBox(height: 12),
          Text(heading, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(detail, style: TextStyle(color: Colors.grey.shade700)),
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
              color: ink,
              backgroundColor: canvas,
            ),
          ),
        ]),
      )).toList());

  Widget tripTile(Trip trip) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: canvas,
          child: Icon(trip.payment == PaymentMethod.cash
              ? Icons.payments_outlined : Icons.credit_card, color: ink),
        ),
        title: Text(trip.source, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${DateFormat('HH:mm').format(trip.at)} · '
            '${trip.payment.label}${trip.kilometers == null ? '' : ' · ${km(trip.kilometers!)} km'}'),
        trailing: Text(money(trip.cents),
            style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
        onTap: () => editTrip(trip),
      );

  Widget tripsPage() {
    final trips = widget.store.trips.where((t) =>
        sameDay(t.at, day) &&
        (sourceFilter == null || t.source == sourceFilter) &&
        (paymentFilter == null || t.payment == paymentFilter)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title('Deine Fahrten', 'Alle Einträge lassen sich nachträglich bearbeiten.'),
      Row(children: [
        IconButton(tooltip: 'Vorheriger Tag', icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day - 1))),
        Expanded(child: TextButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(DateFormat('dd.MM.yyyy').format(day)),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: day,
                firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null && mounted) setState(() => day = picked);
          },
        )),
        IconButton(tooltip: 'Nächster Tag', icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day + 1))),
      ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: sourceFilter ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Quelle filtern'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Alle Quellen')),
          for (final s in widget.store.sources)
            DropdownMenuItem(value: s, child: Text(s)),
        ],
        onChanged: (value) => setState(() => sourceFilter = value == '' ? null : value),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(label: const Text('Alle Zahlungen'), selected: paymentFilter == null,
            onSelected: (_) => setState(() => paymentFilter = null)),
        for (final method in PaymentMethod.values)
          ChoiceChip(label: Text(method.label), selected: paymentFilter == method,
              onSelected: (_) => setState(() => paymentFilter = method)),
      ]),
      panel('${trips.length} Fahrten · ${money(TripSummary(trips).totalCents)}',
          trips.isEmpty
            ? emptyState('Keine passenden Fahrten.', 'Wähle einen anderen Tag oder erfasse eine Fahrt.')
            : Column(children: trips.map(tripTile).toList())),
    ]);
  }

  Widget monthPage() {
    final summary = TripSummary(tripsInMonth(widget.store.trips, month));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title('Dein Monatsbericht', 'Umsatz, Entwicklung und Quellen auf einen Blick.'),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: 'Vorheriger Monat', icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text(DateFormat('MMMM yyyy', 'de_DE').format(month),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        IconButton(tooltip: 'Nächster Monat', icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 12),
      heroCard('Monatsumsatz', summary.totalCents,
          '${summary.trips.length} Fahrten · ${summary.workingDays} Tage mit Fahrten'),
      metrics([
        ('Ø Tag mit Fahrten', money(summary.averageWorkingDayCents), Icons.trending_up),
        ('Bar erhalten', money(summary.cashCents), Icons.payments_outlined),
      ]),
      panel('Umsatz pro Tag', DailyChart(key: ValueKey(month),
          month: month, values: summary.dailyCents(month))),
      panel('Umsatz nach Quelle', summary.trips.isEmpty
          ? const Text('Mit deiner ersten Fahrt erscheint hier die Aufteilung.')
          : breakdown(summary.bySource, summary.totalCents)),
      panel('Umsatz nach Zahlungsart', breakdown({
        for (final entry in summary.byPayment.entries)
          entry.key.label: entry.value,
      }, summary.totalCents)),
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
      title: const Text('Neue Quelle'),
      content: TextField(controller: controller, autofocus: true, maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name, z. B. Zentrale')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Hinzufügen')),
      ],
    ));
    // The dialog's route can still animate out using its controller.
    if (value == null || !mounted) return;
    try {
      await widget.store.addSource(value);
    } catch (_) {
      if (mounted) message('Quelle konnte nicht gespeichert werden. Bitte 1–40 Zeichen eingeben.');
    }
  }

  Widget settingsPage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title('Dein Logbuch', 'Quellen und lokale Daten verwalten.'),
        panel('Speicherung auf diesem Gerät', const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diese erste Version speichert Daten lokal. Es gibt noch keine '
                'Anmeldung und keine Synchronisierung zwischen Geräten.'),
            SizedBox(height: 12),
            Text('Im Browser können gelöschte Website-Daten oder der private '
                'Modus zum Verlust der Einträge führen. Nutze die Exportfunktion '
                'für eine Kopie. Für den Mehrbenutzerbetrieb wird Firebase ergänzt.'),
          ],
        )),
        panel('Deine Fahrtquellen', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8,
                children: widget.store.sources.map((s) => Chip(label: Text(s))).toList()),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: widget.store.saving ? null : addSource,
                icon: const Icon(Icons.add), label: const Text('Quelle hinzufügen')),
          ],
        )),
        panel('Daten exportieren', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alle Fahrten und Quellen als JSON in die Zwischenablage '
                'kopieren und anschließend in einer Datei sichern.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: widget.store.exportJson()));
                  if (mounted) message('Export kopiert. Bitte in einer Datei sichern.');
                } catch (_) {
                  if (mounted) message('Kopieren nicht möglich.');
                }
              },
              icon: const Icon(Icons.copy_all_outlined), label: const Text('Export kopieren'),
            ),
          ],
        )),
        panel('Kilometer optional', const Text('Du kannst jede Fahrt ohne '
            'Kilometerangabe speichern. Die Kennzahl €/km verwendet ausschließlich '
            'Fahrten mit eingetragener Strecke und enthält keine Leerfahrten. '
            'GPS und Kilometerstände für die ganze Schicht folgen später.')),
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
          ? 'Tippe auf einen Tag für den Betrag.'
          : '${selected! + 1}. ${DateFormat('MMMM', 'de_DE').format(widget.month)}: '
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
                              ? const Color(0xFFE4E9E3) : ink,
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
      if (maximum == 0) const Text('Für diesen Monat sind noch keine Umsätze erfasst.'),
    ]);
  }
}

class TripEditor extends StatefulWidget {
  const TripEditor({super.key, required this.store, this.trip});
  final LogbookStore store;
  final Trip? trip;
  @override
  State<TripEditor> createState() => _TripEditorState();
}

class _TripEditorState extends State<TripEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount;
  late final TextEditingController distance;
  late final TextEditingController note;
  late DateTime at;
  late String source;
  late PaymentMethod payment;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final trip = widget.trip;
    amount = TextEditingController(text: trip == null ? ''
        : (trip.cents / 100).toStringAsFixed(2).replaceAll('.', ','));
    distance = TextEditingController(text: trip?.kilometers == null ? ''
        : trip!.kilometers.toString().replaceAll('.', ','));
    note = TextEditingController(text: trip?.note ?? '');
    at = trip?.at ?? DateTime.now();
    source = trip?.source ?? widget.store.sources.first;
    payment = trip?.payment ?? PaymentMethod.cash;
  }

  @override
  void dispose() {
    amount.dispose();
    distance.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.store.saveTrip(Trip(
        id: widget.trip?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        at: at,
        cents: parseCents(amount.text)!,
        source: source,
        payment: payment,
        kilometers: parseKilometers(distance.text),
        note: note.text.trim(),
      ));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Nicht gespeichert. Bitte erneut versuchen.';
        });
      }
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Fahrt löschen?'),
      content: const Text('Der Eintrag wird aus dem Logbuch entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
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
      if (mounted) setState(() { busy = false; error = 'Löschen nicht möglich.'; });
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
              Expanded(child: Text(widget.trip == null ? 'Fahrt erfassen' : 'Fahrt bearbeiten',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink))),
              IconButton(tooltip: 'Schließen', onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('amount'),
              controller: amount,
              autofocus: true,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fahrpreis', suffixText: '€', hintText: '22,70'),
              validator: (v) => parseCents(v ?? '') == null
                  ? 'Betrag größer als 0, mit höchstens 2 Nachkommastellen.' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: source,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Fahrtquelle'),
              items: widget.store.sources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: busy ? null : (value) => setState(() => source = value!),
            ),
            const SizedBox(height: 20),
            const Text('Zahlungsart', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final method in PaymentMethod.values)
                ChoiceChip(label: Text(method.label), selected: payment == method,
                    onSelected: busy ? null : (_) => setState(() => payment = method)),
            ]),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('dd.MM.yyyy · HH:mm').format(at)),
              onPressed: busy ? null : () async {
                final date = await showDatePicker(context: context,
                    initialDate: at, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (date == null || !context.mounted) {
                  return;
                }
                final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(at));
                if (time != null && mounted) {
                  setState(() => at = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: distance,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Fahrtstrecke (optional)', suffixText: 'km'),
              validator: (v) => (v ?? '').trim().isNotEmpty && parseKilometers(v!) == null
                  ? 'Bitte eine Strecke größer als 0 und bis 10.000 km eingeben.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(controller: note, enabled: !busy, maxLength: 250,
                decoration: const InputDecoration(labelText: 'Notiz (optional)')),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: busy ? null : save,
              icon: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Fahrt speichern'),
            )),
            if (widget.trip != null) Center(child: TextButton.icon(
              onPressed: busy ? null : delete,
              icon: const Icon(Icons.delete_outline), label: const Text('Fahrt löschen'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            )),
            const SizedBox(height: 16),
          ],
        )),
      ),
    ),
  );
}
