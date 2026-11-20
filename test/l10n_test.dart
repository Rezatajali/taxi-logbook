import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_logbook/l10n.dart';
import 'package:taxi_logbook/logbook.dart';
import 'package:taxi_logbook/l10n_strings.dart';
import 'package:taxi_logbook/main.dart';
import 'package:taxi_logbook/store.dart';

void main() {
  tearDown(() => language.value = AppLanguage.de);

  test('Every translation has English, Persian, Turkish and Arabic text', () {
    for (final entry in translations.entries) {
      expect(entry.value, hasLength(4), reason: entry.key);
      expect(entry.value.every((t) => t.trim().isNotEmpty), isTrue, reason: entry.key);
    }
    language.value = AppLanguage.fa;
    expect(tr('Fahrten'), 'کرایه‌ها');
    expect(tr('Unbekannter Text'), 'Unbekannter Text');
  });

  testWidgets('Switching to Persian translates the app and uses right-to-left', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LogbookStore(prefs)..load();
    await tester.pumpWidget(LogbookApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-fa')));
    await tester.pumpAndSettle();
    expect(find.text('کرایه‌ها'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('کرایه‌ها'))), TextDirection.rtl);
    expect(prefs.getString('language'), 'fa');
    expect(tester.takeException(), isNull);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('All tabs render on a phone in ${lang.label}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = LogbookStore(await SharedPreferences.getInstance())..load();
      await store.saveTrip(Trip(id: 'a', at: DateTime.now(), cents: 2270, tipCents: 100,
          source: 'Uber', payment: PaymentMethod.cash));
      language.value = lang;
      await tester.pumpWidget(LogbookApp(store: store));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      for (var i = 0; i < bar.destinations.length; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tab $i');
      }
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'fare form');
    });
  }
}
