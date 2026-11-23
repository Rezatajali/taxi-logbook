import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_logbook/help_screen.dart';

void main() {
  testWidgets('The German visual guide can be read and navigated on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(useMaterial3: true),
      home: const HelpScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 1 von 9'), findsOneWidget);
    expect(find.text('Anmelden oder registrieren'), findsOneWidget);
    for (var i = 1; i < 9; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Schritt ${i + 1} von 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Ein Symbol auf dem Handy'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 8 von 9'), findsOneWidget);
  });
}
