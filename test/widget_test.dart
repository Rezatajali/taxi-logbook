import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

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

    await tester.tap(find.text('Fahrten'));
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
}
