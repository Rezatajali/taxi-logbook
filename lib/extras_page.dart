import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'logbook.dart';
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
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: 'Vorheriger Monat', icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text(DateFormat('MMMM yyyy', 'de_DE').format(month),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        IconButton(tooltip: 'Nächster Monat', icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 8),
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
