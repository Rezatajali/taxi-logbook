import 'l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pauses.dart';
import 'pause_screen.dart';
import 'shifts.dart';
import 'store.dart';

class ShiftPanel extends StatelessWidget {
  const ShiftPanel({super.key, required this.store, required this.day});
  final LogbookStore store;
  final DateTime day;
  bool get enabled => store.ready && store.shiftsReady && !store.saving;

  Future<void> write(BuildContext context, Future<void> Function() action) async {
    try { await action(); } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is FormatException ? error.message : tr('Schicht konnte nicht gespeichert werden. Bitte erneut versuchen.'))));
      }
    }
  }

  Future<void> manual(BuildContext context, [ShiftRecord? shift]) async {
    final result = await showDialog<PauseRecord>(context: context,
      builder: (_) => ManualPauseDialog(day: day,
        title: shift == null ? tr('Schicht manuell eintragen') : tr('Schicht bearbeiten'),
        pause: shift == null ? null : PauseRecord(id: shift.id, start: shift.start, end: shift.end)));
    if (result != null && context.mounted) {
      final updated = ShiftRecord(id: result.id, start: result.start, end: result.end,
        origin: shift?.origin ?? ShiftOrigin.manual);
      await write(context, () => shift?.running == true
        ? store.finishShift(updated, result.end!) : store.saveShift(updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = store.shifts.where((s) => s.running).toList();
    final until = DateTime(day.year, day.month, day.day + 1);
    final from = DateTime(day.year, day.month, day.day);
    final entries = store.shifts.where((s) => s.start.isBefore(until) &&
      (s.end ?? now).isAfter(from)).toList()..sort((a, b) => b.start.compareTo(a.start));
    final totals = workTotalsForDay(store.shifts, store.pauses, day, now);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Schichtanfang und Schichtende'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (!store.shiftsReady) Text(tr('Schichten werden geladen …')),
      if (active.isEmpty) SizedBox(width: double.infinity, child: FilledButton.icon(
        key: const Key('start-shift'), onPressed: enabled ? () => write(context, () =>
          store.saveShift(ShiftRecord(id: DateTime.now().microsecondsSinceEpoch.toString(),
            start: DateTime.now().toUtc(), origin: ShiftOrigin.timer))) : null,
        icon: const Icon(Icons.play_circle_outline), label: Text(tr('Schicht anfangen')))),
      for (final shift in active) Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Schicht läuft · seit ${DateFormat('dd.MM. HH:mm').format(shift.start.toLocal())}'),
          Text(pauseTime(now.difference(shift.start)), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(key: ValueKey('finish-shift-${shift.id}'),
            onPressed: enabled && store.pausesReady ? () => write(context,
              () => store.finishShift(shift, DateTime.now().toUtc())) : null,
            icon: const Icon(Icons.stop_circle_outlined), label: Text(tr('Schicht beenden'))),
        ]))),
      OutlinedButton.icon(key: const Key('manual-shift'), onPressed: enabled ? () => manual(context) : null,
        icon: const Icon(Icons.edit_calendar_outlined), label: Text(tr('Schicht manuell eintragen'))),
      const SizedBox(height: 12),
      Text('Schichtzeit: ${pauseTime(totals.gross)}'),
      Text('Pausen in der Schicht: ${pauseTime(totals.breaks)}'),
      Text('Arbeitszeit ohne Pausen: ${pauseTime(totals.net)}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Text('Anrechnung: ${pauseTime(totals.credited)}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const Text('Deine Anrechnungsregel: Bei Schichten unter 6 Stunden kein Pausenabzug. '
        'Die tatsächliche Arbeitszeit wird separat angezeigt. Es werden keine pauschalen Pausen abgezogen.',
        style: TextStyle(fontSize: 12, color: Colors.white60)),
      const SizedBox(height: 12),
      if (entries.isEmpty) Text(tr('Für diesen Tag ist noch keine Schicht erfasst.')),
      for (final shift in entries) Card(child: ListTile(
        title: Text('${DateFormat('dd.MM. HH:mm').format(shift.start.toLocal())} → '
          '${shift.end == null ? 'läuft' : DateFormat('dd.MM. HH:mm').format(shift.end!.toLocal())}'),
        subtitle: Text(shift.origin == ShiftOrigin.timer ? tr('Manuell gestartet') : tr('Manuell eingetragen')),
        trailing: IconButton(tooltip: tr('Schicht bearbeiten'),
          onPressed: enabled ? () => manual(context, shift) : null, icon: const Icon(Icons.edit_outlined)),
      )),
      const SizedBox(height: 8),
      if (workWarning(totals) != null) Text(workWarning(totals)!,
        style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700)),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: Text(tr('Hinweise zu Arbeitszeiten')),
        children: const [Text('Allgemeine Regel für Arbeitnehmer: 8 Stunden täglich; bis 10 Stunden nur mit Ausgleich (§ 3 ArbZG). '
          'Über 6 Stunden Arbeitszeit mindestens 30 Minuten Pause, über 9 Stunden 45 Minuten (§ 4 ArbZG). '
          'Die 12-Stunden-Meldung ist deine zusätzliche Schichtwarnung, keine gesetzliche Freigabe. '
          'Sonderregelungen und weitere Ruhezeitpflichten sind hier nicht vollständig geprüft. '
          'Quelle: gesetze-im-internet.de/arbzg/', style: TextStyle(fontSize: 12))]),
      const Text('Zeitwarnungen erscheinen nur bei geöffneter App. GPS startet oder beendet noch keine Schicht.',
        style: TextStyle(fontSize: 12, color: Colors.white60)),
    ]);
  }
}
