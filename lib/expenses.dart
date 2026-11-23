import 'package:flutter/material.dart';
import 'l10n.dart';

enum ExpenseCategory {
  fuel('Tanken', Icons.local_gas_station_outlined),
  wash('Waschen', Icons.local_car_wash_outlined),
  parking('Parken', Icons.local_parking_outlined),
  repair('Werkstatt', Icons.build_outlined),
  other('Sonstiges', Icons.receipt_outlined);

  const ExpenseCategory(this.german, this.icon);
  final String german;
  String get label => tr(german);
  final IconData icon;
}

/// A cost such as fuel or a car wash. Kept separate from fares and revenue.
class Expense {
  Expense({required this.id, required this.at, required this.cents,
      required this.category, this.note = ''}) {
    if (cents <= 0 || cents > 99999999 || note.length > 250) {
      throw const FormatException('Ungültige Kosten.');
    }
  }
  final String id;
  final DateTime at;
  final int cents;
  final ExpenseCategory category;
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id, 'at': at.toIso8601String(), 'cents': cents,
    'category': category.name, 'note': note,
  };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    at: DateTime.parse(json['at'] as String),
    cents: json['cents'] as int,
    category: ExpenseCategory.values.asNameMap()[json['category']] ?? ExpenseCategory.other,
    note: json['note'] as String? ?? '',
  );
}

List<Expense> expensesInMonth(Iterable<Expense> expenses, DateTime month) => expenses
    .where((e) => e.at.year == month.year && e.at.month == month.month).toList()
  ..sort((a, b) => b.at.compareTo(a.at));

Map<ExpenseCategory, int> expensesByCategory(Iterable<Expense> expenses) {
  final result = <ExpenseCategory, int>{};
  for (final e in expenses) {
    result.update(e.category, (v) => v + e.cents, ifAbsent: () => e.cents);
  }
  return result;
}
