# Firebase Web

Projekt: `taxi-logbook-d1104`. Die öffentlichen Client-Einstellungen stehen in
`firebase-web.json` und in `lib/firebase_web_options.dart`. Admin-Schlüssel und
Passwörter werden nicht im Repository gespeichert.

Die Webversion verwendet Firebase Authentication (E-Mail/Passwort, Registrierung,
Passwort-Reset-Mail) und Cloud Firestore. Firebase übernimmt die gehostete
Passwort-Reset-Seite; die Anwendung speichert keine Passwörter in Firestore.

Fahrten: `users/{uid}/trips/{tripId}`. Eigene Quellen:
`users/{uid}/settings/logbook`. Die Backend-Instanz ist an einen UID gebunden.
Beim Kontowechsel werden Store und Listener entsorgt. Die Regeln entsprechen
`firestore.rules` und müssen im Firebase-Projekt veröffentlicht sein.

Lokale Alt-Daten bleiben unangetastet und über „Lokale Vorschau“ erreichbar.
Sie werden nicht automatisch dem ersten angemeldeten Konto zugeordnet.
Die Webversion lädt beim Start die jeweilige Konto-Historie. Offline-Writes
sind als ausstehend markiert; Abmelden ist bis zur Synchronisierung gesperrt.
Ein JSON-Export umfasst nur die Daten des gerade geöffneten Logbuchs.

Android benötigt noch eine eigene App-Registrierung mit Paketnamen
`de.tajalli.taxi_logbook` und deren Firebase-Konfiguration. Die Android-Test-APK
bleibt deshalb vorerst lokal. Für Verteilung und Updates braucht ein Release
zudem einen dauerhaft gesicherten Signaturschlüssel.

`node tool/verify-firebase.mjs` prüft das reale Projekt mit zwei temporären
Konten: Registrierung, Anmeldung, eigene CRUD-Operationen sowie Verweigerung
fremder und anonymer Zugriffe. Alle Testdokumente/Konten werden in `finally`
entfernt. Es werden keine E-Mails versandt und keine bestehenden Daten angefasst.
Der GitHub-Workflow führt diese Prüfung nach den Flutter-Tests aus.
