import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';
import 'package:taxi_logbook/logbook.dart';

void main() {
  testWidgets('A driver saves and edits a fare on a narrow phone screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '22,70');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(store.trips.single.cents, 2270);
    expect(store.trips.single.kilometers, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Schichten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taxi').last);
    await tester.pumpAndSettle();
    expect(find.text('Fahrt bearbeiten'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '30,00');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(store.trips.single.cents, 3000);
    expect(store.trips, hasLength(1));
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Monatsumsatz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The wheel beside the amount saves an invoice choice', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '22,70');
    await tester.tap(find.byKey(const Key('fare-type-button')));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byKey(const Key('fare-type-wheel')), matching: find.byType(Scrollable));
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(48.0 * 3); // Rechnung
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-fare-type')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(store.trips.single.payment, PaymentMethod.invoice);
    expect(store.trips.single.source, 'Taxi');
    expect(store.trips.single.cents, 2270);
    expect(tester.takeException(), isNull);
  });
}
