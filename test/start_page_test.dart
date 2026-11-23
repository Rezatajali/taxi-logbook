import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

void main() {
  testWidgets('Fahrten opens first and daily totals follow the selected date', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    final now = DateTime.now();
    await store.saveTrip(Trip(id: 'today', at: now, cents: 2270,
      source: 'Taxi', payment: PaymentMethod.cash));
    await store.saveTrip(Trip(id: 'tomorrow', at: DateTime(now.year, now.month, now.day + 1),
      cents: 3500, source: 'Uber', payment: PaymentMethod.platform));
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    expect(find.text('Deine Fahrten'), findsOneWidget);
    expect(find.text('Fahrt erfassen'), findsOneWidget);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(5));
    expect(find.text('Tagesumsatz'), findsOneWidget);
    expect(find.text('Davon bar'), findsOneWidget);
    expect(find.text('Trinkgeld'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Nächster Tag'));
    await tester.tap(find.byTooltip('Nächster Tag'));
    await tester.pumpAndSettle();
    expect(find.text(money(0)), findsWidgets);
    expect(find.text(money(2270)), findsNothing);
    expect(find.text('Quelle filtern'), findsNothing);
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Quelle filtern'), findsOneWidget);
    await tester.ensureVisible(find.text('Karte'));
    await tester.tap(find.text('Karte'));
    await tester.pumpAndSettle();
    expect(find.text('Keine passenden Fahrten.'), findsOneWidget);
    expect(find.text(money(3500)), findsWidgets);
    await tester.ensureVisible(find.text('Filter zurücksetzen'));
    await tester.tap(find.text('Filter zurücksetzen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Filter'));
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schichten'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt erfassen'), findsNothing);
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Monatsumsatz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
