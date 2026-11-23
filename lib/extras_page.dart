import 'l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'logbook.dart';
import 'currency_input.dart';
import 'expenses.dart';
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
        IconButton(tooltip: tr('Vorheriger Tag'), icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => cashDay = DateTime(cashDay.year, cashDay.month, cashDay.day - 1))),
        Expanded(child: Text(DateFormat('EEEE, dd.MM.', dateLocale).format(cashDay),
          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(tooltip: tr('Nächster Tag'), icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => cashDay = DateTime(cashDay.year, cashDay.month, cashDay.day + 1))),
      ]),
      row(tr('Bar-Fahrten inkl. Uber Bar und Trinkgeld'), day.expectedCashCents),
      const SizedBox(height: 8),
      field(const Key('start-cash'), startCash, tr('Wechselgeld zu Schichtbeginn (optional)')),
      const SizedBox(height: 8),
      row(tr('Soll in der Kasse'), expected, bold: true),
      const SizedBox(height: 8),
      field(const Key('counted-cash'), countedCash, tr('Gezählt')),
      if (difference != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          key: const Key('cash-difference'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
            color: (difference == 0 ? scheme.primary : difference > 0 ? Colors.amber : scheme.error)
                .withValues(alpha: 0.15)),
          child: Text(difference == 0 ? tr('Passt genau ✓')
              : difference > 0 ? '${_money(difference)} zu viel in der Kasse'
              : '${_money(-difference)} fehlen in der Kasse',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        )),
    ]);
  }

  Future<void> addExpense() async {
    final expense = await showModalBottomSheet<Expense>(context: context, isScrollControlled: true,
      useSafeArea: true, builder: (_) => ExpenseForm(month: month));
    if (expense == null || !mounted) return;
    try {
      await widget.store.saveExpense(expense);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Kosten konnten nicht gespeichert werden.'))));
      }
    }
  }

  Future<void> deleteExpense(Expense expense) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Kosten löschen?')),
      content: Text('${expense.category.label} · ${_money(expense.cents)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen'))),
      ],
    ));
    if (ok == true) await widget.store.deleteExpense(expense.id);
  }

  Widget costs(TripSummary summary) {
    final list = expensesInMonth(widget.store.expenses, month);
    final total = list.fold(0, (sum, e) => sum + e.cents);
    final byCategory = expensesByCategory(list).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final canWrite = widget.store.ready && !widget.store.saving;
    return Column(key: const Key('costs'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      row(tr('Umsatz'), summary.totalCents),
      row(tr('Kosten'), -total),
      const Divider(),
      row(tr('Nach Kosten'), summary.totalCents - total, bold: true),
      if (byCategory.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final entry in byCategory) row(entry.key.label, entry.value),
        const SizedBox(height: 8),
        for (final e in list) ListTile(
          key: ValueKey('expense-${e.id}'),
          contentPadding: EdgeInsets.zero, dense: true,
          leading: Icon(e.category.icon),
          title: Text('${e.category.label} · ${_money(e.cents)}'),
          subtitle: Text([DateFormat('dd.MM.').format(e.at), if (e.note.isNotEmpty) e.note].join(' · ')),
          trailing: IconButton(tooltip: tr('Löschen'), icon: const Icon(Icons.delete_outline),
            onPressed: canWrite ? () => deleteExpense(e) : null),
        ),
      ],
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        key: const Key('add-expense'),
        onPressed: canWrite ? addExpense : null,
        icon: const Icon(Icons.add), label: Text(tr('Kosten erfassen')))),
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
    if (summary.trips.isEmpty) return Text(tr('Noch keine Fahrten in diesem Monat.'));
    final best = summary.bestDays.take(3).toList();
    final weekdays = summary.averageByWeekday;
    final maxWeekday = weekdays.values.fold(0, (a, b) => a > b ? a : b);
    final hours = summary.revenueByHour;
    // Group hours into 3-hour blocks so the list stays short on a phone.
    final blocks = [for (var h = 0; h < 24; h += 3) (h, hours.sublist(h, h + 3).fold(0, (a, b) => a + b))];
    final maxBlock = blocks.fold(0, (a, b) => a > b.$2 ? a : b.$2);
    final heading = const TextStyle(fontWeight: FontWeight.w800);
    return Column(key: const Key('statistics'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Beste Tage'), style: heading),
      for (final (index, entry) in best.indexed)
        row('${['🥇', '🥈', '🥉'][index]} ${DateFormat('EEE dd.MM.', dateLocale).format(entry.$1)}', entry.$2),
      const SizedBox(height: 12),
      Text(tr('Ø pro Wochentag'), style: heading),
      for (var d = 1; d <= 7; d++)
        if (weekdays.containsKey(d)) bar(ExtrasPageWeekday.name(d), weekdays[d]!, maxWeekday),
      const SizedBox(height: 12),
      Text(tr('Umsatz nach Uhrzeit'), style: heading),
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
      Padding(padding: EdgeInsets.only(bottom: 12),
        child: Text(tr('Extras'), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
      section(tr('Kassensturz'), Icons.point_of_sale_outlined, cashCount()),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: tr('Vorheriger Monat'), icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text(DateFormat('MMMM yyyy', dateLocale).format(month),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        IconButton(tooltip: tr('Nächster Monat'), icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 8),
      section(tr('Kosten'), Icons.local_gas_station_outlined, costs(summary)),
      section(tr('Statistik'), Icons.insights_outlined, statistics(summary)),
      section(tr('Trinkgeld'), Icons.volunteer_activism_outlined, tips.isEmpty
        ? const Text('Noch kein Trinkgeld in diesem Monat. Trage es beim Erfassen '
            'einer Fahrt im Feld „Trinkgeld (optional)“ ein.')
        : Column(key: const Key('tips-by-source'), children: [
            row('Gesamt ($tipTrips Fahrten)', summary.tipCents, bold: true),
            const Divider(),
            for (final entry in tips) row(entry.key, entry.value),
            const SizedBox(height: 8),
            Text(tr('Trinkgeld zählt nicht zum Umsatz.'), style: TextStyle(fontSize: 12)),
          ])),
    ]);
  }
}

abstract final class ExtrasPageWeekday {
  static const _names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static String name(int weekday) => tr(_names[weekday - 1]);
}

/// Bottom sheet to record one cost (fuel, car wash, parking …).
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, required this.month});
  final DateTime month;
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  final note = TextEditingController();
  ExpenseCategory category = ExpenseCategory.fuel;
  late DateTime at;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to today in the current month, otherwise the 1st of the shown month.
    at = now.year == widget.month.year && now.month == widget.month.month
        ? DateTime(now.year, now.month, now.day) : widget.month;
  }

  @override
  void dispose() { amount.dispose(); note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Form(key: form, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(tr('Kosten erfassen'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          IconButton(tooltip: tr('Schließen'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in ExpenseCategory.values)
            ChoiceChip(avatar: Icon(c.icon, size: 18), label: Text(c.label), selected: category == c,
              onSelected: (_) => setState(() => category = c)),
        ]),
        const SizedBox(height: 16),
        TextFormField(key: const Key('expense-amount'), controller: amount, autofocus: true,
          keyboardType: TextInputType.number, inputFormatters: const [CentsInputFormatter()],
          decoration: InputDecoration(labelText: tr('Betrag'), suffixText: '€', helperText: '4500 → 45,00 €'),
          validator: (v) => parseCents(v ?? '') == null ? tr('Betrag größer als 0 eingeben.') : null),
        const SizedBox(height: 12),
        OutlinedButton.icon(icon: const Icon(Icons.calendar_today_outlined),
          label: Text(DateFormat('dd.MM.yyyy').format(at)),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: at,
              firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null) setState(() => at = picked);
          }),
        const SizedBox(height: 12),
        TextFormField(controller: note, maxLength: 250,
          decoration: InputDecoration(labelText: tr('Notiz (optional)'))),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          key: const Key('save-expense'),
          icon: const Icon(Icons.check), label: Text(tr('Kosten speichern')),
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(context, Expense(id: DateTime.now().microsecondsSinceEpoch.toString(),
              at: at, cents: parseCents(amount.text)!, category: category, note: note.text.trim()));
          })),
      ]))),
  );
}
