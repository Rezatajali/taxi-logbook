import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pauses.dart';
import 'store.dart';

String pauseTime(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
    '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
    '${(seconds % 60).toString().padLeft(2, '0')}';
}

class PausesPanel extends StatefulWidget {
  const PausesPanel({super.key, required this.store});
  final LogbookStore store;
  @override
  State<PausesPanel> createState() => _PausesPanelState();
}

class _PausesPanelState extends State<PausesPanel> {
  DateTime day = DateUtils.dateOnly(DateTime.now());
  late final Timer timer;
  bool get enabled => widget.store.ready && widget.store.pausesReady && !widget.store.saving;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.store.pauses.any((p) => p.running)) setState(() {});
    });
  }
  @override
  void dispose() { timer.cancel(); super.dispose(); }

  Future<void> save(PauseRecord pause) async {
    try {
      await widget.store.savePause(pause);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pause konnte nicht gespeichert werden. Bitte erneut versuchen.')));
      }
    }
  }

  Future<void> manual([PauseRecord? pause]) async {
    final result = await showDialog<PauseRecord>(context: context,
      builder: (_) => ManualPauseDialog(day: day, pause: pause));
    if (result != null && mounted) await save(result);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final running = widget.store.pauses.where((p) => p.running).toList();
    final from = DateTime(day.year, day.month, day.day);
    final until = DateTime(day.year, day.month, day.day + 1);
    final entries = widget.store.pauses.where((p) => p.start.isBefore(until) &&
      (p.end ?? now).isAfter(from)).toList()..sort((a, b) => b.start.compareTo(a.start));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Deine Pausen', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (!widget.store.pausesReady) const Text('Pausen werden geladen …'),
      if (running.isEmpty) SizedBox(width: double.infinity, child: FilledButton.icon(
        key: const Key('start-pause'), onPressed: enabled ? () => save(PauseRecord(
          id: now.microsecondsSinceEpoch.toString(), start: DateTime.now().toUtc(), origin: PauseOrigin.timer)) : null,
        icon: const Icon(Icons.pause_circle_outline), label: const Text('Pause starten'))),
      for (final pause in running) Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pause läuft', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Seit ${DateFormat('dd.MM. HH:mm').format(pause.start.toLocal())}'),
          Text(pauseTime(now.difference(pause.start)),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FilledButton.icon(key: ValueKey('stop-pause-${pause.id}'),
            onPressed: enabled ? () => save(pause.finish(DateTime.now().toUtc())) : null,
            icon: const Icon(Icons.stop_circle_outlined), label: const Text('Pause beenden')),
        ]))),
      const SizedBox(height: 12),
      OutlinedButton.icon(key: const Key('manual-pause'), onPressed: enabled ? () => manual() : null,
        icon: const Icon(Icons.edit_calendar_outlined), label: const Text('Pause manuell eintragen')),
      const SizedBox(height: 24),
      Row(children: [
        IconButton(tooltip: 'Vorheriger Tag', icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day - 1))),
        Expanded(child: TextButton(onPressed: () async {
          final picked = await showDatePicker(context: context, initialDate: day,
            firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (picked != null && mounted) setState(() => day = picked);
        }, child: Text(DateFormat('dd.MM.yyyy').format(day),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)))),
        IconButton(tooltip: 'Nächster Tag', icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => day = DateTime(day.year, day.month, day.day + 1))),
      ]),
      Text('Pausenzeit: ${pauseTime(pauseDurationForDay(widget.store.pauses, day, now))}',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (entries.isEmpty) const Text('Für diesen Tag sind noch keine Pausen eingetragen.'),
      for (final pause in entries) Card(child: ListTile(
        leading: const Icon(Icons.pause_circle_outline),
        title: Text('${DateFormat('dd.MM. HH:mm').format(pause.start.toLocal())} → '
          '${pause.end == null ? 'läuft' : DateFormat('dd.MM. HH:mm').format(pause.end!.toLocal())}'),
        subtitle: Text('${pause.origin == PauseOrigin.timer ? 'Timer' : pause.origin == PauseOrigin.gps ? 'GPS' : 'Manuell'} · '
          '${pauseTime((pause.end ?? now).difference(pause.start))}'),
        trailing: pause.running ? null : IconButton(tooltip: 'Pause bearbeiten',
          onPressed: enabled ? () => manual(pause) : null, icon: const Icon(Icons.edit_outlined)),
      )),
      const SizedBox(height: 20),
      const Text('Der Timer läuft auch nach dem Schließen der App weiter. '
        'Pausen über Mitternacht werden auf die jeweiligen Tage verteilt.'),
      const SizedBox(height: 12),
      const Text('GPS folgt später: Ein erkannter Stillstand von mehr als 15 Minuten '
        'soll als Pause erfasst werden. Wartezeit ist nicht immer eine Pause; '
        'die Erkennung ist derzeit noch nicht aktiv.', style: TextStyle(color: Colors.white60)),
    ]);
  }
}

class ManualPauseDialog extends StatefulWidget {
  const ManualPauseDialog({super.key, required this.day, this.pause});
  final DateTime day;
  final PauseRecord? pause;
  @override
  State<ManualPauseDialog> createState() => _ManualPauseDialogState();
}

class _ManualPauseDialogState extends State<ManualPauseDialog> {
  late DateTime start, end;
  String? error;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    end = widget.pause?.end?.toLocal() ?? DateTime(widget.day.year, widget.day.month,
      widget.day.day, now.hour, now.minute);
    start = widget.pause?.start.toLocal() ?? end.subtract(const Duration(minutes: 30));
  }
  Future<void> pick(bool begin, bool date) async {
    final value = begin ? start : end;
    DateTime? next;
    if (date) {
      final picked = await showDatePicker(context: context, initialDate: value,
        firstDate: DateTime(2020), lastDate: DateTime(2100));
      if (picked != null) next = DateTime(picked.year, picked.month, picked.day, value.hour, value.minute);
    } else {
      final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
      if (picked != null) next = DateTime(value.year, value.month, value.day, picked.hour, picked.minute);
    }
    final selected = next;
    if (selected != null && mounted) setState(() { if (begin) { start = selected; } else { end = selected; } error = null; });
  }
  Widget controls(String label, bool begin, DateTime value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: () => pick(begin, true), icon: const Icon(Icons.calendar_today),
          label: Text(DateFormat('dd.MM.yyyy').format(value))),
        TextButton.icon(onPressed: () => pick(begin, false), icon: const Icon(Icons.schedule),
          label: Text(DateFormat('HH:mm').format(value))),
      ]),
    ]);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.pause == null ? 'Pause manuell eintragen' : 'Pause bearbeiten'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        controls('Beginn', true, start), const SizedBox(height: 12), controls('Ende', false, end),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(key: const Key('save-manual-pause'), onPressed: () {
        if (!end.isAfter(start)) { setState(() => error = 'Das Ende muss nach dem Beginn liegen.'); return; }
        Navigator.pop(context, PauseRecord(id: widget.pause?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          start: start.toUtc(), end: end.toUtc(), origin: widget.pause?.origin ?? PauseOrigin.manual));
      }, child: const Text('Speichern'))],
  );
}
