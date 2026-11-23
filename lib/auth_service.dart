import 'l10n.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverAccount {
  const DriverAccount(this.uid, this.email);
  final String uid;
  final String email;
}

abstract class DriverAuth {
  Stream<DriverAccount?> accounts();
  Future<void> login(String email, String password);
  Future<void> register(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
  /// Confirms the password, deletes the driver's data, then the account itself.
  Future<void> deleteAccount(String password, Future<void> Function() deleteData);
}

class FirebaseDriverAuth implements DriverAuth {
  FirebaseDriverAuth(this.auth);
  final FirebaseAuth auth;
  @override
  Stream<DriverAccount?> accounts() => auth.authStateChanges().map((user) =>
      user == null ? null : DriverAccount(user.uid, user.email ?? ''));
  @override
  Future<void> login(String email, String password) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }
  @override
  Future<void> register(String email, String password) async {
    await auth.createUserWithEmailAndPassword(email: email, password: password);
  }
  @override
  Future<void> resetPassword(String email) => auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<void> deleteAccount(String password, Future<void> Function() deleteData) async {
    final user = auth.currentUser;
    if (user == null || user.email == null) throw StateError('Nicht angemeldet.');
    // Firebase requires a recent sign-in before an account can be deleted.
    await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password));
    await deleteData();
    await user.delete();
  }
}

String authError(Object error, {bool reset = false}) {
  if (error is FirebaseAuthException) {
    // Only reported when Firebase email enumeration protection is turned off.
    if (reset && error.code == 'user-not-found') {
      return 'Zu dieser E-Mail gibt es kein Konto. Bitte die E-Mail-Adresse prüfen '
          'oder ein neues Konto erstellen.';
    }
    return switch (error.code) {
      'invalid-email' => tr('Bitte eine gültige E-Mail-Adresse eingeben.'),
      'email-already-in-use' => tr('Diese E-Mail ist bereits registriert. Bitte anmelden.'),
      'weak-password' => tr('Bitte ein stärkeres Passwort wählen (mindestens 8 Zeichen).'),
      'invalid-credential' || 'wrong-password' || 'user-not-found' =>
        tr('E-Mail oder Passwort stimmt nicht.'),
      'too-many-requests' => tr('Zu viele Versuche. Bitte später erneut versuchen.'),
      'network-request-failed' => tr('Keine Verbindung. Bitte Internetverbindung prüfen.'),
      'operation-not-allowed' => 'E-Mail/Passwort ist in Firebase noch nicht aktiviert.',
      'user-disabled' => tr('Dieses Konto ist deaktiviert.'),
      _ => tr('Aktion nicht möglich. Bitte erneut versuchen.'),
    };
  }
  return tr('Aktion nicht möglich. Bitte erneut versuchen.');
}
