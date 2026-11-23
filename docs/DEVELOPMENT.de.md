# Taxi Logbuch

Deutschsprachiger Flutter-Prototyp für die manuelle Erfassung von Taxifahrten.
Eine Codebasis für Android und Web; iPhone-Nutzer verwenden die veröffentlichte Webversion.

## Funktionen der ersten Version

Dunkles Dashboard mit grünen Diagrammen. In **Fahrten → Fahrt erfassen**
steht neben dem Betrag eine scrollbare Auswahl für Bar, Uber, Uber Bar, Karte, Rechnung,
Bolt und FREENOW. Über „Quelle / Zahlung anpassen“ sind Kombinationen wie Uber + Bar möglich.
Fahrten gruppiert einzelne Fahrten nach Datum. Unter Schichten werden Schichtanfang, Schichtende und Pausen erfasst.

- Fahrpreis in Euro, auf ganze Cent genau gespeichert; Ziffern werden als Cent eingegeben (2270 → 22,70 €).
- Fahrtquelle (Taxi, Uber, Bolt, FREENOW oder eigene Quelle) **getrennt** von Zahlungsart (Bar, Karte, Rechnung, Über Plattform).
- Datum/Uhrzeit, optionale Fahrtstrecke und Notiz.
- Fahrten bearbeiten (gelb) und nach Bestätigung als gelöscht markieren (rot, durchgestrichen). Alte Werte bleiben mit Zeitpunkt im Änderungsverlauf; gelöschte Fahrten zählen nicht zum Umsatz.
- Pausen mit Start-/Stop-Timer oder manuell mit Beginn und Ende. Laufende Timer bleiben beim Schließen erhalten; Tageswerte teilen Pausen über Mitternacht auf und zählen überlappende Zeiten einmal.
- Tagesfilter, Quellenfilter und Zahlungsfilter.
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
nicht für Android zweckentfremdet. GPS und Kilometerstände für vollständige Schichten folgen später. Arbeitszeiten werden manuell erfasst. Umsatz ist vor Provisionen, Steuern und
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
bash tool/deploy-hosting.sh
```

Eine Domain muss nicht gekauft werden: Firebase Hosting stellt `.web.app` bereit.
Die Webversion ist öffentlich unter https://taxi-logbuch-preview.rztajalli.chatgpt.site erreichbar.
Jeder Fahrer registriert sich und sieht die Daten seines eigenen Kontos. Die Web-App kann im Browser genutzt und zum Home-Bildschirm
hinzugefügt werden; für sie müssen Benutzer keine neue APK bei Änderungen laden.
Android-APKs sind direkt verteilbar, Updates müssen ohne eigenen Updater aber
manuell installiert werden. Release-Updates benötigen denselben Signaturschlüssel.

Das fertige Hosting-Paket enthält build/web, firebase.json, .firebaserc und
`tool/deploy-hosting.sh`. Mit Node.js LTS kann es ohne lokale Flutter-Installation
veröffentlicht werden. Die Anmeldung erfolgt im eigenen Google-Konto. Das Skript
veröffentlicht ausschließlich Hosting und ändert keine Firestore-Regeln.

## Pausen und Änderungsverlauf

Firestore speichert Pausen unter `users/{uid}/pauses/{id}` und Fahrten unter
`users/{uid}/trips/{id}`. Die bestehenden UID-Regeln gelten für beide Pfade.
Fahrtänderungen und Löschmarkierungen lesen den aktuellen Datensatz in einer
Transaktion, um den letzten Zustand vor der Änderung zu erhalten; sie benötigen
Internet. Der Verlauf ist für die App bestimmt und kein unveränderliches Archiv.
Früher endgültig gelöschte Einträge lassen sich damit nicht nachträglich wiederherstellen.
JSON-Exporte enthalten alle aktuellen Fahrten einschließlich Löschmarkierungen,
Änderungsverläufe und Pausen. Das lokale Format v1 wird weiter gelesen.

GPS ist noch nicht aktiv. `PauseOrigin.gps` und die strikte Schwelle von mehr als
15 Minuten Stillstand sind für die spätere Integration vorbereitet. Die Verbindung
zum GPS, zuverlässige Stillstandserkennung und Abgrenzung von Wartezeit folgen später.


## Schichten und Arbeitszeiten

`users/{uid}/shifts/{id}` speichert Beginn, Ende und Erfassungsart; die bisherigen
UID-Regeln gelten weiter. Anfang/Ende können manuell eingetragen oder durch
Tippen auf Start/Ende erfasst werden. Schichtende beendet zugleich offene Pausen
in einem atomaren Cloud-Batch. Überschneidungen werden anhand der geladenen
Schichten abgelehnt; zwei gleichzeitig offline arbeitende Geräte können dennoch
kollidieren. Zeitintervalle werden für tatsächliche Tages-/Monatswerte vereinigt.

Der Monatsbericht zählt Tage mit erfassten Schichtzeiten auch ohne Fahrten.
Nachtzeiten werden an lokaler Mitternacht aufgeteilt. Tatsächliche Arbeitszeit
zieht ausschließlich erfasste Pausen innerhalb der Schichten ab. Die gewünschte
Anrechnung für Schichten unter sechs Stunden wird separat ohne Pausenabzug
angezeigt; dies ist keine gesetzliche Definition der Arbeitszeit. Es gibt keinen
pauschalen Abzug von Pflichtpausen.

Zeitwarnungen sind bei geöffneter App sichtbar: über 8 Stunden Arbeitszeit,
ab 10 Stunden Arbeitszeit und ab 12 Stunden Schichtdauer. Sie sind kein vollständiger
Compliance-Check und keine Hintergrund-/Push-Alarme. Allgemeine Hinweise beziehen
sich auf §§ 2–4 ArbZG (https://www.gesetze-im-internet.de/arbzg/); Sonderregelungen,
Ausgleichszeiträume und Ruhezeiten werden nicht vollständig geprüft. GPS ist noch
nicht verbunden und startet/beendet keine Schicht automatisch.

## Startseite

Die App öffnet direkt Fahrten. Es gibt vier Ziele: Fahrten, Schichten, Monat und Profil. Ein separates Home entfällt. Die kompakte Tagesübersicht in Fahrten zeigt Tagesumsatz und Bar-Anteil für das ausgewählte Datum, unabhängig von Listenfiltern. Ausführliche Monatsberichte bleiben in Monat.
