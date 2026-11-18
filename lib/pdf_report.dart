import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'logbook.dart';
import 'shifts.dart';

/// One row of the monthly PDF: a working day with its shifts and fares.
class ReportDay {
  ReportDay(this.day, this.shifts, this.summary);
  final DateTime day;
  final List<ShiftRecord> shifts;
  final TripSummary summary;
}

// The built-in PDF fonts only cover Latin-1, so amounts use "EUR" instead of €.
final _amount = NumberFormat('#,##0.00', 'de_DE');
String pdfMoney(int cents) => '${_amount.format(cents / 100)} EUR';

/// Builds the rows of the monthly report. Fares after midnight belong to the
/// day their shift started (see [workDayOf]).
List<ReportDay> reportDays(Iterable<Trip> trips, Iterable<ShiftRecord> shifts, DateTime month) {
  final monthTrips = tripsInMonth(trips, month, shifts);
  final result = <ReportDay>[];
  for (var d = 1; d <= DateTime(month.year, month.month + 1, 0).day; d++) {
    final day = DateTime(month.year, month.month, d);
    final dayShifts = shifts.where((s) => sameDay(s.start.toLocal(), day)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final summary = TripSummary(tripsOnDay(monthTrips, day, shifts), shifts: shifts);
    if (dayShifts.isNotEmpty || summary.trips.isNotEmpty) {
      result.add(ReportDay(day, dayShifts, summary));
    }
  }
  return result;
}

/// Monthly report with totals and, per day, shift start/end (no durations).
Future<Uint8List> buildMonthReport({required Iterable<Trip> trips,
    required Iterable<ShiftRecord> shifts, required DateTime month,
    required String driverLabel, DateTime? createdAt}) {
  final summary = TripSummary(tripsInMonth(trips, month, shifts), shifts: shifts);
  final days = reportDays(trips, shifts, month);
  final time = DateFormat('HH:mm');
  final date = DateFormat('dd.MM.yyyy');
  String shiftText(Iterable<ShiftRecord> list, bool start) => list.isEmpty ? '-'
      : list.map((s) => s.end == null && !start ? 'läuft'
          : (start ? time.format(s.start.toLocal()) : _endText(s, time))).join('\n');

  final doc = pw.Document(title: 'Taxi Logbuch ${DateFormat('MM/yyyy').format(month)}');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (context) => [
      pw.Text('Taxi Logbuch - Monatsbericht',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text('${DateFormat('MMMM yyyy', 'de_DE').format(month)} · $driverLabel'),
      pw.Text('Erstellt am ${date.format(createdAt ?? DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Übersicht', 'Betrag'],
        data: [
          ['Umsatz gesamt (${summary.trips.length} Fahrten)', pdfMoney(summary.totalCents)],
          for (final entry in summary.paymentBreakdown.entries)
            if (entry.value != 0) [entry.key, pdfMoney(entry.value)],
          for (final entry in summary.bySource.entries)
            ['Quelle: ${entry.key}', pdfMoney(entry.value)],
        ],
        cellAlignments: {1: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 20),
      pw.Text('Tage', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      if (days.isEmpty) pw.Text('Keine Fahrten oder Schichten in diesem Monat.')
      else pw.TableHelper.fromTextArray(
        headers: ['Datum', 'Schichtbeginn', 'Schichtende', 'Fahrten', 'Umsatz', 'Bar', 'Uber Bar'],
        data: [
          for (final d in days) [
            date.format(d.day),
            shiftText(d.shifts, true),
            shiftText(d.shifts, false),
            '${d.summary.trips.length}',
            pdfMoney(d.summary.totalCents),
            pdfMoney(d.summary.cashCents),
            pdfMoney(d.summary.uberCashCents),
          ],
        ],
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 16),
      pw.Text('Fahrten nach Mitternacht zählen zum Tag des Schichtbeginns. '
          'Umsatz vor Provisionen, Steuern und Fahrzeugkosten. '
          'Kein Ersatz für Fiskaltaxameter oder amtliche Aufzeichnungen.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    ],
  ));
  return doc.save();
}

String _endText(ShiftRecord shift, DateFormat time) {
  final start = shift.start.toLocal();
  final end = shift.end!.toLocal();
  // Mark shifts that end on a later calendar day, e.g. "02:30 (+1)".
  final days = DateTime(end.year, end.month, end.day)
      .difference(DateTime(start.year, start.month, start.day)).inDays;
  return days > 0 ? '${time.format(end)} (+$days)' : time.format(end);
}
