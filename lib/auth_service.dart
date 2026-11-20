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
}

String authError(Object error, {bool reset = false}) {
  if (error is FirebaseAuthException) {
    // Only reported when Firebase email enumeration protection is turned off.
    if (reset && error.code == 'user-not-found') {
      return 'Zu dieser E-Mail gibt es kein Konto. Bitte die E-Mail-Adresse prüfen '
          'oder ein neues Konto erstellen.';
    }
    return switch (error.code) {
      'invalid-email' => 'Bitte eine gültige E-Mail-Adresse eingeben.',
      'email-already-in-use' => 'Diese E-Mail ist bereits registriert. Bitte anmelden.',
      'weak-password' => 'Bitte ein stärkeres Passwort wählen (mindestens 8 Zeichen).',
      'invalid-credential' || 'wrong-password' || 'user-not-found' =>
        'E-Mail oder Passwort stimmt nicht.',
      'too-many-requests' => 'Zu viele Versuche. Bitte später erneut versuchen.',
      'network-request-failed' => 'Keine Verbindung. Bitte Internetverbindung prüfen.',
      'operation-not-allowed' => 'E-Mail/Passwort ist in Firebase noch nicht aktiviert.',
      'user-disabled' => 'Dieses Konto ist deaktiviert.',
      _ => 'Aktion nicht möglich. Bitte erneut versuchen.',
    };
  }
  return 'Aktion nicht möglich. Bitte erneut versuchen.';
}
