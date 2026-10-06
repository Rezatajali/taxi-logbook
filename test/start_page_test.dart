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
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(4));
    expect(find.text('Tagesumsatz'), findsOneWidget);
    expect(find.text('Davon bar'), findsOneWidget);
    await tester.tap(find.byTooltip('Nächster Tag'));
    await tester.pumpAndSettle();
    expect(find.text(money(0)), findsOneWidget);
    expect(find.text(money(2270)), findsNothing);
    await tester.tap(find.text('Schichten'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt erfassen'), findsNothing);
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Monatsumsatz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
