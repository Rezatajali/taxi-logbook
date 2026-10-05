import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'store.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.localStore,
    required this.createStore, required this.homeBuilder});
  final DriverAuth auth;
  final LogbookStore localStore;
  final LogbookStore Function(DriverAccount) createStore;
  final Widget Function(LogbookStore, DriverAccount?, VoidCallback) homeBuilder;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<DriverAccount?> accounts = widget.auth.accounts();
  bool local = false;
  String? signOutError;

  Future<void> signOut(LogbookStore store) async {
    if (store.saving || store.pendingWrites) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bitte zuerst die ausstehenden Änderungen synchronisieren.')));
      return;
    }
    try {
      await widget.auth.signOut();
    } catch (error) {
      if (mounted) setState(() => signOutError = authError(error));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DriverAccount?>(
    stream: accounts,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final account = snapshot.data;
      if (account != null) {
        return AccountHome(key: ValueKey(account.uid), account: account,
          createStore: widget.createStore,
          builder: (store) => Column(children: [
            if (signOutError != null) MaterialBanner(
              content: Text(signOutError!),
              actions: [TextButton(onPressed: () => setState(() => signOutError = null),
                child: const Text('OK'))]),
            Expanded(child: widget.homeBuilder(store, account, () => signOut(store))),
          ]));
      }
      if (local) {
        return widget.homeBuilder(widget.localStore, null,
          () => setState(() => local = false));
      }
      return LoginScreen(auth: widget.auth,
        onLocal: () => setState(() => local = true));
    },
  );
}

class AccountHome extends StatefulWidget {
  const AccountHome({super.key, required this.account, required this.createStore,
    required this.builder});
  final DriverAccount account;
  final LogbookStore Function(DriverAccount) createStore;
  final Widget Function(LogbookStore) builder;
  @override
  State<AccountHome> createState() => _AccountHomeState();
}
class _AccountHomeState extends State<AccountHome> {
  late final LogbookStore store = widget.createStore(widget.account)..load();
  @override
  void dispose() { store.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.builder(store);
}

enum LoginMode { login, register, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.onLocal});
  final DriverAuth auth;
  final VoidCallback onLocal;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  LoginMode mode = LoginMode.login;
  bool busy = false;
  bool hidden = true;
  String? error;
  String? notice;
  @override
  void dispose() {
    email.dispose(); password.dispose(); confirmation.dispose(); super.dispose();
  }
  void changeMode(LoginMode value) {
    if (busy) return;
    setState(() { mode = value; error = null; notice = null; });
    password.clear(); confirmation.clear();
    form.currentState?.reset();
  }
  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; notice = null; });
    final address = email.text.trim();
    try {
      switch (mode) {
        case LoginMode.login:
          await widget.auth.login(address, password.text);
        case LoginMode.register:
          await widget.auth.register(address, password.text);
        case LoginMode.reset:
          await widget.auth.resetPassword(address);
          if (mounted) setState(() => notice = 'Falls ein Konto für diese E-Mail '
            'besteht, erhältst du einen Link zum Festlegen eines neuen Passworts. '
            'Bitte auch den Spam-Ordner prüfen.');
      }
    } catch (failure) {
      if (mounted) setState(() => error = authError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final reset = mode == LoginMode.reset;
    final register = mode == LoginMode.register;
    return Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: AutofillGroup(child: Form(key: form, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.local_taxi_rounded, size: 52),
            const SizedBox(height: 20),
            Text(reset ? 'Passwort zurücksetzen' : register ? 'Konto erstellen' : 'Taxi Logbuch',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(reset ? 'Wir senden dir einen Link per E-Mail.'
              : 'Deine Fahrten. Dein Konto. Auf deinen Geräten.', textAlign: TextAlign.center),
            const SizedBox(height: 28),
            TextFormField(key: const Key('auth-email'), controller: email,
              enabled: !busy, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email], autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'E-Mail-Adresse'),
              validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                .hasMatch((value ?? '').trim()) ? null : 'Bitte eine gültige E-Mail eingeben.'),
            if (!reset) ...[
              const SizedBox(height: 16),
              TextFormField(key: const Key('auth-password'), controller: password,
                enabled: !busy, obscureText: hidden, autocorrect: false,
                enableSuggestions: false,
                autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: 'Passwort', suffixIcon: IconButton(
                  tooltip: hidden ? 'Passwort anzeigen' : 'Passwort verbergen',
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                validator: (value) => (value ?? '').isEmpty ? 'Bitte Passwort eingeben.'
                  : register && value!.length < 6 ? 'Mindestens 6 Zeichen.' : null),
            ],
            if (register) ...[
              const SizedBox(height: 16),
              TextFormField(key: const Key('auth-confirmation'), controller: confirmation,
                enabled: !busy, obscureText: hidden, autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Passwort wiederholen'),
                validator: (value) => value != password.text ? 'Passwörter stimmen nicht überein.' : null),
            ],
            if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(notice!, key: const Key('reset-notice'))),
            const SizedBox(height: 24),
            FilledButton(key: const Key('auth-submit'), onPressed: busy ? null : submit,
              child: busy ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Text(reset ? 'Link per E-Mail senden' : register ? 'Konto erstellen' : 'Anmelden')),
            if (!reset) TextButton(onPressed: busy ? null : () => changeMode(LoginMode.reset),
              child: const Text('Passwort vergessen?')),
            TextButton(onPressed: busy ? null : () => changeMode(
              mode == LoginMode.login ? LoginMode.register : LoginMode.login),
              child: Text(mode == LoginMode.login ? 'Noch kein Konto? Registrieren' : 'Zur Anmeldung')),
            const Divider(height: 32),
            TextButton(onPressed: busy ? null : widget.onLocal,
              child: const Text('Lokale Vorschau / bisherige Einträge')),
            const Text('Lokale Einträge bleiben in diesem Browser und werden '
              'nicht automatisch einem Konto zugeordnet.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ],
        ))),
      ),
    ))));
  }
}
