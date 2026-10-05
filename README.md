# Taxi Logbuch

Deutschsprachiger Flutter-Prototyp für die manuelle Erfassung von Taxifahrten.
Eine Codebasis für Android und Web; iPhone-Nutzer verwenden später die gehostete Webversion.

## Funktionen der ersten Version

Dunkles Dashboard mit grünen Diagrammen. In **Schichten → Fahrt erfassen**
steht neben dem Betrag eine scrollbare Auswahl für Bar, Uber, Karte, Rechnung,
Bolt und FREENOW. Über „Quelle / Zahlung anpassen“ sind Kombinationen wie Uber + Bar möglich.
Tagesschichten gruppieren die Fahrten nach Datum; Start-/Endzeiten folgen später.

- Fahrpreis in Euro, auf ganze Cent genau gespeichert; Eingabe mit Komma oder Punkt.
- Fahrtquelle (Taxi, Uber, Bolt, FREENOW oder eigene Quelle) **getrennt** von Zahlungsart (Bar, Karte, Rechnung, Über Plattform).
- Datum/Uhrzeit, optionale Fahrtstrecke und Notiz.
- Fahrten bearbeiten und nach Bestätigung löschen; Tagesfilter, Quellenfilter und Zahlungsfilter.
- Tagesumsatz, Barumsatz, Monatsumsatz, Durchschnitt je Tag mit Fahrten und anklickbares Tagesdiagramm.
- €/km nur aus Fahrten mit eingetragener Strecke. Unbekannte Strecken und Leerfahrten werden nicht berücksichtigt.
- Lokale Speicherung und JSON-Export in die Zwischenablage.

## Status

Die Webversion hat E-Mail/Passwort-Anmeldung, Registrierung mit Passwortbestätigung,
„Passwort vergessen?“ und Cloud Firestore für einzelne Fahrten je Fahrer.
Die vom Benutzer eingerichteten Zugriffsregeln werden im echten Firebase-Projekt
mit zwei temporären Konten im CI geprüft. Die Zustellung einer Reset-Mail muss
mit einer eigenen erreichbaren E-Mail-Adresse abschließend geprüft werden.

Deutliche Bearbeiten-/Löschen-Schaltflächen stehen direkt an jeder Fahrt.
Der Speichern-Knopf im Fahrtformular steht vor den optionalen Feldern.
Lokale Alt-Daten sind über „Lokale Vorschau / bisherige Einträge“ weiter erreichbar;
sie werden nicht automatisch einem neuen Konto zugeordnet.

**Android-Test-APK bleibt lokal**, bis eine Android-App im Firebase-Projekt
registriert und deren eigene Konfiguration ergänzt ist. Die Web-App-ID wird
nicht für Android zweckentfremdet. GPS, Kilometerstände und Arbeitszeiten für
vollständige Schichten folgen später. Umsatz ist vor Provisionen, Steuern und
Fahrzeugkosten, kein Nettogewinn.

## Lokal starten

Flutter **3.35.7** und die passende Android-/Browser-Entwicklungsumgebung installieren.

```bash
bash tool/bootstrap.sh
flutter run -d chrome
```

Das Bootstrap-Skript erzeugt nur fehlende Android-/Web-Plattformverzeichnisse mit
dem installierten Flutter SDK und lässt die Anwendungsdateien unverändert.

```bash
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

## GitHub Actions

Der Workflow prüft Quellcode und Tests und baut danach Web sowie eine Android-Test-APK.
In GitHub unter **Actions → Flutter prüfen und bauen → letzter erfolgreicher Lauf → Artifacts**
stehen die ZIP-Dateien zum Download bereit. Das Web-Artefakt ist noch keine veröffentlichte URL.

Die Debug-APK ist zum Testen vorgesehen. Für eine dauerhaft verteilte Android-Version
brauchen wir einen gesicherten, stabilen Signaturschlüssel und einen Release-Build.
Die temporären CI-Debug-Schlüssel können zwischen Läufen variieren; Updates über eine
bereits installierte Testversion sind dann nicht möglich. Vor einer Deinstallation Daten exportieren.
Keine Schlüssel oder Passwörter im Repository speichern.

## Firebase und Veröffentlichung

Das Projekt `taxi-logbook-d1104` und die Web-App sind eingerichtet. Details und
noch erforderliche Android-Schritte stehen in `config/README.md`.
`firebase.json` enthält Hosting sowie die Regeln aus `firestore.rules`.
Zum öffentlichen Web-Hosting im eigenen Konto:

```bash
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting
```

Eine Domain muss nicht gekauft werden: Firebase Hosting stellt `.web.app` bereit.
Die persönliche Sites-Vorschau bleibt privat und ist noch kein allgemeiner Link
für andere Fahrer. Die Web-App kann im Browser genutzt und zum Home-Bildschirm
hinzugefügt werden; für sie müssen Benutzer keine neue APK bei Änderungen laden.
Android-APKs sind direkt verteilbar, Updates müssen ohne eigenen Updater aber
manuell installiert werden. Release-Updates benötigen denselben Signaturschlüssel.
