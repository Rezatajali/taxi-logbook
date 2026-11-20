import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'logbook.dart';
import 'currency_input.dart';
import 'store.dart';

final _euro = NumberFormat.currency(locale: 'de_DE', symbol: '€');
String _money(num cents) => _euro.format(cents / 100);

/// Extras: details drivers look at only when they want to (tips, …),
/// kept off the main Fahrten page.
class ExtrasPage extends StatefulWidget {
  const ExtrasPage({super.key, required this.store});
  final LogbookStore store;
  @override
  State<ExtrasPage> createState() => _ExtrasPageState();
}

class _ExtrasPageState extends State<ExtrasPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime cashDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final startCash = TextEditingController();
  final countedCash = TextEditingController();

  @override
  void dispose() {
    startCash.dispose();
    countedCash.dispose();
    super.dispose();
  }

  int _cents(TextEditingController c) => c.text.trim().isEmpty ? 0 : (parseCents(c.text) ?? 0);

  Widget cashCount() {
    final store = widget.store;
    final day = TripSummary(tripsOnDay(store.trips, cashDay, store.shifts), shifts: store.shifts);
    final expected = _cents(startCash) + day.expectedCashCents;
    final counted = countedCash.text.trim().isEmpty ? null : _cents(countedCash);
    final difference = counted == null ? null : counted - expected;
    final scheme = Theme.of(context).colorScheme;
    Widget field(Key key, TextEditingController c, String label) => TextField(
      key: key, controller: c, keyboardType: TextInputType.number,
      inputFormatters: const [CentsInputFormatter()],
      decoration: InputDecoration(labelText: label, suffixText: '€'),
      onChanged: (_) => setState(() {}),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(tooltip: 'Vorheriger Tag', icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => cashDay = DateTime(cashDay.year, cashDay.month, cashDay.day - 1))),
        Expanded(child: Text(DateFormat('EEEE, dd.MM.', 'de_DE').format(cashDay),
          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Nächster Tag', icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => cashDay = DateTime(cashDay.year, cashDay.month, cashDay.day + 1))),
      ]),
      row('Bar-Fahrten inkl. Uber Bar und Trinkgeld', day.expectedCashCents),
      const SizedBox(height: 8),
      field(const Key('start-cash'), startCash, 'Wechselgeld zu Schichtbeginn (optional)'),
      const SizedBox(height: 8),
      row('Soll in der Kasse', expected, bold: true),
      const SizedBox(height: 8),
      field(const Key('counted-cash'), countedCash, 'Gezählt'),
      if (difference != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          key: const Key('cash-difference'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
            color: (difference == 0 ? scheme.primary : difference > 0 ? Colors.amber : scheme.error)
                .withValues(alpha: 0.15)),
          child: Text(difference == 0 ? 'Passt genau ✓'
              : difference > 0 ? '${_money(difference)} zu viel in der Kasse'
              : '${_money(-difference)} fehlen in der Kasse',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        )),
    ]);
  }

  Widget bar(String label, int cents, int max) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 56, child: Text(label)),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
        value: max == 0 ? 0 : cents / max, minHeight: 10,
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)))),
      SizedBox(width: 90, child: Text(_money(cents), textAlign: TextAlign.right)),
    ]),
  );

  Widget statistics(TripSummary summary) {
    if (summary.trips.isEmpty) return const Text('Noch keine Fahrten in diesem Monat.');
    final best = summary.bestDays.take(3).toList();
    final weekdays = summary.averageByWeekday;
    final maxWeekday = weekdays.values.fold(0, (a, b) => a > b ? a : b);
    final hours = summary.revenueByHour;
    // Group hours into 3-hour blocks so the list stays short on a phone.
    final blocks = [for (var h = 0; h < 24; h += 3) (h, hours.sublist(h, h + 3).fold(0, (a, b) => a + b))];
    final maxBlock = blocks.fold(0, (a, b) => a > b.$2 ? a : b.$2);
    final heading = const TextStyle(fontWeight: FontWeight.w800);
    return Column(key: const Key('statistics'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Beste Tage', style: heading),
      for (final (index, entry) in best.indexed)
        row('${['🥇', '🥈', '🥉'][index]} ${DateFormat('EEE dd.MM.', 'de_DE').format(entry.$1)}', entry.$2),
      const SizedBox(height: 12),
      Text('Ø pro Wochentag', style: heading),
      for (var d = 1; d <= 7; d++)
        if (weekdays.containsKey(d)) bar(ExtrasPageWeekday.name(d), weekdays[d]!, maxWeekday),
      const SizedBox(height: 12),
      Text('Umsatz nach Uhrzeit', style: heading),
      for (final block in blocks)
        if (block.$2 > 0) bar('${block.$1.toString().padLeft(2, '0')}–${(block.$1 + 3).toString().padLeft(2, '0')}',
          block.$2, maxBlock),
    ]);
  }

  Widget section(String title, IconData icon, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        child,
      ])),
  );

  Widget row(String label, int cents, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
      Text(_money(cents), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final summary = TripSummary(tripsInMonth(store.trips, month, store.shifts), shifts: store.shifts);
    final tips = summary.tipsBySource.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final tipTrips = summary.trips.where((t) => t.tipCents > 0).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(bottom: 12),
        child: Text('Extras', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
      section('Kassensturz', Icons.point_of_sale_outlined, cashCount()),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: 'Vorheriger Monat', icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text(DateFormat('MMMM yyyy', 'de_DE').format(month),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        IconButton(tooltip: 'Nächster Monat', icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 8),
      section('Statistik', Icons.insights_outlined, statistics(summary)),
      section('Trinkgeld', Icons.volunteer_activism_outlined, tips.isEmpty
        ? const Text('Noch kein Trinkgeld in diesem Monat. Trage es beim Erfassen '
            'einer Fahrt im Feld „Trinkgeld (optional)“ ein.')
        : Column(key: const Key('tips-by-source'), children: [
            row('Gesamt ($tipTrips Fahrten)', summary.tipCents, bold: true),
            const Divider(),
            for (final entry in tips) row(entry.key, entry.value),
            const SizedBox(height: 8),
            const Text('Trinkgeld zählt nicht zum Umsatz.', style: TextStyle(fontSize: 12)),
          ])),
    ]);
  }
}

abstract final class ExtrasPageWeekday {
  static const _names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static String name(int weekday) => _names[weekday - 1];
}
