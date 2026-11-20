import 'l10n.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'help_screen.dart';
import 'install_screen.dart';
import 'legal_screen.dart';
import 'store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.localStore,
    required this.createStore, required this.homeBuilder});
  final DriverAuth auth;
  final LogbookStore localStore;
  final LogbookStore Function(DriverAccount) createStore;
  /// The last argument deletes the signed-in account (null for the local preview).
  final Widget Function(LogbookStore, DriverAccount?, VoidCallback,
      Future<void> Function(String password)?) homeBuilder;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<DriverAccount?> accounts = widget.auth.accounts();
  bool local = false;
  String? signOutError;

  Future<void> signOut(LogbookStore store) async {
    if (store.saving || store.pendingWrites) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Bitte zuerst die ausstehenden Änderungen synchronisieren.'))));
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
            Expanded(child: widget.homeBuilder(store, account, () => signOut(store),
              (password) => widget.auth.deleteAccount(password, store.deleteAllData))),
          ]));
      }
      if (local) {
        return widget.homeBuilder(widget.localStore, null,
          () => setState(() => local = false), null);
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
    final address = email.text;
    password.clear(); confirmation.clear();
    form.currentState?.reset();
    email.text = address;
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
          if (mounted) {
            setState(() => notice = 'Anfrage für $address gesendet. Falls ein Konto '
            'mit genau dieser E-Mail besteht, kommt in wenigen Minuten ein Link von '
            'noreply@taxi-logbook-d1104.firebaseapp.com. Bitte auch Spam/Werbung prüfen. '
            'Kommt nichts an, wurde das Konto vermutlich mit einer anderen E-Mail erstellt.');
          }
      }
    } catch (failure) {
      if (mounted) setState(() => error = authError(failure, reset: mode == LoginMode.reset));
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
            Align(alignment: AlignmentDirectional.centerEnd, child: PopupMenuButton<AppLanguage>(
              key: const Key('login-language'),
              tooltip: tr('Sprache'),
              initialValue: language.value,
              onSelected: (value) async =>
                  saveLanguage(await SharedPreferences.getInstance(), value),
              itemBuilder: (_) => [
                for (final l in AppLanguage.values) PopupMenuItem(value: l, child: Text(l.label)),
              ],
              child: Padding(padding: const EdgeInsets.all(8), child: Row(mainAxisSize: MainAxisSize.min,
                children: [const Icon(Icons.language), const SizedBox(width: 6), Text(language.value.label)])),
            )),
            Center(child: ClipRRect(borderRadius: BorderRadius.circular(24),
              child: Image.asset('branding/logo.png', width: 96, height: 96,
                semanticLabel: 'Taxi Logbuch'))),
            const SizedBox(height: 20),
            Text(reset ? tr('Passwort zurücksetzen') : register ? tr('Konto erstellen') : 'Taxi Logbuch',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            const SizedBox(height: 12),
            Text(reset ? tr('Wir senden dir einen Link per E-Mail.')
              : tr('Fahrten erfassen. Schichten planen.\nDeinen Umsatz im Blick behalten.'), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            TextFormField(key: const Key('auth-email'), controller: email,
              enabled: !busy, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email], autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(labelText: tr('E-Mail-Adresse')),
              validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                .hasMatch((value ?? '').trim()) ? null : tr('Bitte eine gültige E-Mail eingeben.')),
            if (!reset) ...[
              const SizedBox(height: 16),
              TextFormField(key: const Key('auth-password'), controller: password,
                enabled: !busy, obscureText: hidden, autocorrect: false,
                enableSuggestions: false,
                autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(labelText: tr('Passwort'), suffixIcon: IconButton(
                  tooltip: hidden ? tr('Passwort anzeigen') : tr('Passwort verbergen'),
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
                validator: (value) => (value ?? '').isEmpty ? tr('Bitte Passwort eingeben.')
                  : register && value!.length < 8 ? tr('Mindestens 8 Zeichen.') : null),
            ],
            if (register) ...[
              const SizedBox(height: 16),
              TextFormField(key: const Key('auth-confirmation'), controller: confirmation,
                enabled: !busy, obscureText: hidden, autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: tr('Passwort wiederholen')),
                validator: (value) => value != password.text ? tr('Passwörter stimmen nicht überein.') : null),
              const SizedBox(height: 8),
              // Registration requires accepting the privacy policy.
              FormField<bool>(
                key: const Key('privacy-consent'),
                initialValue: false,
                validator: (value) => value == true ? null : tr('Bitte der Datenschutzerklärung zustimmen.'),
                builder: (field) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: field.value ?? false,
                    onChanged: busy ? null : (value) => field.didChange(value),
                    title: Text(tr('Ich habe die Datenschutzerklärung gelesen und stimme zu.')),
                    subtitle: Align(alignment: AlignmentDirectional.centerStart, child: TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => const LegalScreen(privacy: true))),
                      child: Text(tr('Datenschutzerklärung lesen')))),
                  ),
                  if (field.hasError) Text(field.errorText!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ]),
              ),
            ],
            if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(notice!, key: const Key('reset-notice'))),
            const SizedBox(height: 24),
            FilledButton(key: const Key('auth-submit'), onPressed: busy ? null : submit,
              child: busy ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Text(reset ? tr('Link per E-Mail senden') : register ? tr('Konto erstellen') : tr('Anmelden'))),
            if (!reset) TextButton(onPressed: busy ? null : () => changeMode(LoginMode.reset),
              child: Text(tr('Passwort vergessen?'))),
            TextButton(onPressed: busy ? null : () => changeMode(
              mode == LoginMode.login ? LoginMode.register : LoginMode.login),
              child: Text(mode == LoginMode.login ? tr('Noch kein Konto? Registrieren') : tr('Zur Anmeldung'))),
            OutlinedButton.icon(key: const Key('install-guide'),
              onPressed: busy ? null : () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const InstallScreen())),
              icon: const Icon(Icons.add_to_home_screen), label: Text(tr('App aufs Handy holen'))),
            TextButton.icon(onPressed: busy ? null : () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
              icon: const Icon(Icons.help_outline), label: Text(tr('Hilfe · Anleitung'))),
            const Divider(height: 32),
            TextButton(onPressed: busy ? null : widget.onLocal,
              child: Text(tr('Lokale Vorschau / bisherige Einträge'))),
            const Text('Lokale Einträge bleiben in diesem Browser und werden '
              'nicht automatisch einem Konto zugeordnet.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(key: const Key('legal-link'), onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const LegalScreen())),
              child: Text(tr('Impressum · Datenschutz'))),
          ],
        ))),
      ),
    ))));
  }
}
