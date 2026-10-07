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
    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '2270');
    await tester.enterText(find.byKey(const Key('tip-amount')), '200');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(store.trips.single.cents, 2270);
    expect(store.trips.single.tipCents, 200);
    expect(store.trips.single.kilometers, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('edit-${store.trips.single.id}')));
    await tester.tap(find.byKey(ValueKey('edit-${store.trips.single.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt bearbeiten'), findsOneWidget);
    expect(find.text('2,00'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '30,00');
    await tester.enterText(find.byKey(const Key('tip-amount')), '300');
    await tester.ensureVisible(find.text('Fahrt speichern'));
    await tester.tap(find.text('Fahrt speichern'));
    await tester.pumpAndSettle();
    expect(store.trips.single.cents, 3000);
    expect(store.trips.single.tipCents, 300);
    expect(store.trips.single.history.single['tipCents'], 200);
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
    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fahrt erfassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '2270');
    await tester.tap(find.byKey(const Key('fare-type-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fare-type-wheel')), findsOneWidget);
    final scrollable = find.descendant(
        of: find.byKey(const Key('fare-type-wheel')),
        matching: find.byWidgetPredicate((widget) => widget is Scrollable));
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
  testWidgets('Entry starts in Fahrten and driver number persists in profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LogbookStore(prefs)..load();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    expect(find.text('Fahrt erfassen'), findsOneWidget);
    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt erfassen'), findsOneWidget);
    await tester.tap(find.text('Monat'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt erfassen'), findsNothing);
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt erfassen'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('change-driver-number')));
    await tester.tap(find.byKey(const Key('change-driver-number')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('driver-number-input')), '267');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(store.driverNumber, '267');
    expect((LogbookStore(prefs)..load()).driverNumber, '267');
    expect(find.text('Fahrer 267'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Changing the date preserves time and only the time button opens its picker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LogbookStore(await SharedPreferences.getInstance())..load();
    final trip = Trip(id: 'date-test', at: DateTime(2026, 10, 5, 14, 37),
      cents: 2270, source: 'Taxi', payment: PaymentMethod.cash);
    await tester.pumpWidget(LogbookApp(store: store,
      home: Scaffold(body: TripEditor(store: store, trip: trip))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('trip-date')));
    await tester.tap(find.byKey(const Key('trip-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('06.10.2026'), findsOneWidget);
    expect(find.text('14:37'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trip-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}

