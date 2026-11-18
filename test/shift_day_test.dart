import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/pdf_report.dart';
import 'package:taxi_logbook/shifts.dart';

Trip fare(String id, DateTime at, int cents,
        {String source = 'Taxi', PaymentMethod payment = PaymentMethod.cash}) =>
    Trip(id: id, at: at, cents: cents, source: source, payment: payment);

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  // Evening shift 17:00 -> 02:30 next day.
  final night = ShiftRecord(id: 'n', start: DateTime(2026, 10, 5, 17),
      end: DateTime(2026, 10, 6, 2, 30));

  test('Fares after midnight count for the day the shift started', () {
    expect(workDayOf(DateTime(2026, 10, 6, 1), [night]), DateTime(2026, 10, 5));
    expect(workDayOf(DateTime(2026, 10, 6, 2, 30), [night]), DateTime(2026, 10, 5));
    // Outside any shift: the calendar day.
    expect(workDayOf(DateTime(2026, 10, 6, 9), [night]), DateTime(2026, 10, 6));
    expect(workDayOf(DateTime(2026, 10, 6, 1), const []), DateTime(2026, 10, 6));

    final trips = [
      fare('a', DateTime(2026, 10, 5, 18), 2000),
      fare('b', DateTime(2026, 10, 6, 1), 3000),
      fare('c', DateTime(2026, 10, 6, 10), 500),
    ];
    expect(tripsOnDay(trips, DateTime(2026, 10, 5), [night]).map((t) => t.id), ['a', 'b']);
    expect(tripsOnDay(trips, DateTime(2026, 10, 6), [night]).map((t) => t.id), ['c']);
    final summary = TripSummary(trips, shifts: [night]);
    expect(summary.dailyCents(DateTime(2026, 10)).sublist(4, 6), [5000, 500]);
    expect(summary.workingDays, 2);
  });

  test('A night shift at the end of the month stays in that month', () {
    final shift = ShiftRecord(id: 's', start: DateTime(2026, 10, 31, 20),
        end: DateTime(2026, 11, 1, 3));
    final trips = [fare('late', DateTime(2026, 11, 1, 1), 4200)];
    expect(tripsInMonth(trips, DateTime(2026, 10), [shift]), hasLength(1));
    expect(tripsInMonth(trips, DateTime(2026, 11), [shift]), isEmpty);
  });

  test('A forgotten running shift does not capture later days', () {
    final running = ShiftRecord(id: 'r', start: DateTime(2026, 10, 5, 17));
    expect(workDayOf(DateTime(2026, 10, 6, 3), [running]), DateTime(2026, 10, 5));
    expect(workDayOf(DateTime(2026, 10, 8, 3), [running]), DateTime(2026, 10, 8));
  });

  test('Monthly PDF lists shift start and end per day without durations', () async {
    final trips = [
      fare('a', DateTime(2026, 10, 5, 18), 2000),
      fare('b', DateTime(2026, 10, 6, 1), 3000, source: 'Uber'),
    ];
    final days = reportDays(trips, [night], DateTime(2026, 10));
    expect(days, hasLength(1));
    expect(days.single.summary.totalCents, 5000);
    expect(days.single.summary.uberCashCents, 3000);
    final bytes = await buildMonthReport(trips: trips, shifts: [night],
        month: DateTime(2026, 10), driverLabel: 'Fahrer 267',
        createdAt: DateTime(2026, 11, 1));
    expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
    expect(pdfMoney(123456), '1.234,56 EUR');
  });
}
