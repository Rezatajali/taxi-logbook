# Firebase-Verbindung vorbereiten

Projekt: `taxi-logbook-d1104`. Die öffentlichen Web-App-Einstellungen stehen in
`firebase-web.json`. Dies sind keine Admin-Zugangsdaten und keine Sicherheitsregeln.
Die Datei ist noch nicht in die laufende Flutter-App eingebunden.

Nächste Schritte im Firebase-Konto:

1. Authentication → Sign-in method → Email/Password aktivieren.
2. Cloud Firestore in einer passenden EU-Region im Produktionsmodus anlegen.
3. Regeln für `users/{uid}/trips/{tripId}` veröffentlichen, die ausschließlich den
   angemeldeten Besitzer zulassen; keine offenen Testregeln verwenden.
4. Firebase Flutter SDK, Anmeldung und Cloud-Store implementieren und mit zwei
   Konten auf Datenisolation prüfen. Lokale Alt-Daten nur auf ausdrücklichen
   Benutzerwunsch übernehmen, nicht automatisch dem ersten Konto zuordnen.

Android erhält später eine eigene Firebase-App-Registrierung. Die Web-App-ID
wird nicht als Android-App-ID verwendet. Der aktuelle Preview bleibt lokal.
