# Taxi Logbuch

Deutschsprachiger Flutter-Prototyp für die manuelle Erfassung von Taxifahrten.
Eine Codebasis für Android und Web; iPhone-Nutzer verwenden später die gehostete Webversion.

## Funktionen der ersten Version

- Fahrpreis in Euro, auf ganze Cent genau gespeichert; Eingabe mit Komma oder Punkt.
- Fahrtquelle (Taxi, Uber, Bolt, FREENOW oder eigene Quelle) **getrennt** von Zahlungsart (Bar, Karte, Über Plattform).
- Datum/Uhrzeit, optionale Fahrtstrecke und Notiz.
- Fahrten bearbeiten und nach Bestätigung löschen; Tagesfilter, Quellenfilter und Zahlungsfilter.
- Tagesumsatz, Barumsatz, Monatsumsatz, Durchschnitt je Tag mit Fahrten und anklickbares Tagesdiagramm.
- €/km nur aus Fahrten mit eingetragener Strecke. Unbekannte Strecken und Leerfahrten werden nicht berücksichtigt.
- Lokale Speicherung und JSON-Export in die Zwischenablage.

## Status

**Noch kein Mehrbenutzerbetrieb:** Firebase Authentication, Cloud Firestore,
serverseitige Zugriffsregeln und geräteübergreifende Synchronisierung sind noch nicht verbunden.
Es werden keine Passwörter abgefragt. Alle lokalen Einträge gehören zum selben lokalen Logbuch.
GPS sowie Kilometerstände und Arbeitszeiten für komplette Schichten folgen später.
Die angezeigten Beträge sind Umsatz vor Provisionen, Steuern und Fahrzeugkosten, kein Nettogewinn.

Der lokale Speicher ist für das Testen vorgesehen, nicht als einzige dauerhafte Sicherung
betrieblicher Daten. Das Löschen der App oder der Browserdaten kann Einträge entfernen.
Ein JSON-Export kann als Kopie gesichert werden; eine Importfunktion folgt später.

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

## Nächster Schritt: Firebase im eigenen Konto

1. Firebase-Projekt anlegen und Hosting aktivieren. Eine eigene Domain ist nicht nötig.
2. Email/Password Authentication aktivieren; Firestore mit restriktiven Regeln einrichten.
3. FlutterFire konfigurieren und einen Cloud-Store neben dem lokalen Prototyp implementieren.
4. Daten unter `users/{uid}/trips/{tripId}` speichern. Nur der angemeldete Besitzer darf zugreifen.
5. Zugriffe mit zwei Benutzerkonten und direkten fremden Dokumentanfragen im Emulator testen.
6. Mit dem Firebase CLI `firebase use --add`, dann `firebase deploy --only hosting` ausführen.

`firebase.json` bereitet ausschließlich Hosting vor; es richtet weder Anmeldung noch
Firestore ein. Noch keine Hosting-Bereitstellung und kein Firebase-Projekt sind erfolgt.
Die Firebase-Zugangsdaten bleiben beim Kontoinhaber.
