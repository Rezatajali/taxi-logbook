import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_logbook/auth_screen.dart';
import 'package:taxi_logbook/auth_service.dart';

class FakeAuth implements DriverAuth {
  String? resetEmail;
  int registrations = 0;
  Completer<void>? resetWait;
  @override
  Stream<DriverAccount?> accounts() => Stream.value(null);
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> register(String email, String password) async { registrations++; }
  Object? resetFailure;
  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
    if (resetFailure != null) throw resetFailure!;
    await resetWait?.future;
  }
  @override
  Future<void> signOut() async {}
}
void main() {
  testWidgets('Password reset uses the trimmed email, never asks for a password, and prevents duplicate requests', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth()..resetWait = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth, onLocal: () {})));
    await tester.ensureVisible(find.text('Passwort vergessen?'));
    await tester.tap(find.text('Passwort vergessen?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-password')), findsNothing);
    await tester.enterText(find.byKey(const Key('auth-email')), ' driver@example.com ');
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    expect(auth.resetEmail, 'driver@example.com');
    expect(tester.widget<FilledButton>(find.byKey(const Key('auth-submit'))).onPressed, isNull);
    auth.resetWait!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reset-notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Registration rejects mismatched password confirmation', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth, onLocal: () {})));
    await tester.ensureVisible(find.text('Noch kein Konto? Registrieren'));
    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-email')), 'driver@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'secret123');
    await tester.enterText(find.byKey(const Key('auth-confirmation')), 'different');
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.registrations, 0);
    expect(find.text('Passwörter stimmen nicht überein.'), findsOneWidget);
  });
  testWidgets('Registration requires at least 8 password characters', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth, onLocal: () {})));
    await tester.ensureVisible(find.text('Noch kein Konto? Registrieren'));
    await tester.tap(find.text('Noch kein Konto? Registrieren'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-email')), 'driver@example.com');
    await tester.enterText(find.byKey(const Key('auth-password')), 'short12');
    await tester.enterText(find.byKey(const Key('auth-confirmation')), 'short12');
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(auth.registrations, 0);
    expect(find.text('Mindestens 8 Zeichen.'), findsOneWidget);
  });
  testWidgets('Reset names an unknown email when Firebase reports it', (tester) async {
    final auth = FakeAuth()..resetFailure = FirebaseAuthException(code: 'user-not-found');
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth, onLocal: () {})));
    await tester.ensureVisible(find.text('Passwort vergessen?'));
    await tester.tap(find.text('Passwort vergessen?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-email')), 'wrong@example.com');
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('kein Konto'), findsOneWidget);
    expect(find.byKey(const Key('reset-notice')), findsNothing);
  });
  testWidgets('Install guide opens from the login screen with iPhone and Android steps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: FakeAuth(), onLocal: () {})));
    await tester.ensureVisible(find.byKey(const Key('install-guide')));
    await tester.tap(find.byKey(const Key('install-guide')));
    await tester.pumpAndSettle();
    // Tests run as Android, so the Android tab opens first.
    expect(find.text('„App installieren“ wählen'), findsOneWidget);
    await tester.tap(find.text('iPhone'));
    await tester.pumpAndSettle();
    expect(find.text('„Zum Home-Bildschirm“ wählen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
