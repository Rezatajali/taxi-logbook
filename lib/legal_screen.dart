import 'package:flutter/material.dart';
import 'l10n.dart';

/// Operator details for Impressum and privacy policy (§ 5 DDG, Art. 13 DSGVO).
/// Must be filled in with the operator's real name, postal address and email.
abstract final class LegalConfig {
  static const operatorName = '';
  static const operatorAddress = ''; // Straße Nr., PLZ Ort
  static const operatorEmail = '';
  static bool get complete =>
      operatorName.isNotEmpty && operatorAddress.isNotEmpty && operatorEmail.isNotEmpty;
}

String get _operator => LegalConfig.complete
    ? '${LegalConfig.operatorName}\n${LegalConfig.operatorAddress}\nE-Mail: ${LegalConfig.operatorEmail}'
    : '(Angaben zum Betreiber werden ergänzt.)';

const _privacy = <(String, String)>[
  ('Worum geht es?', 'Taxi Logbuch ist ein persönliches Fahrten- und Umsatzbuch. Diese Erklärung '
      'beschreibt, welche personenbezogenen Daten dabei verarbeitet werden.'),
  ('Welche Daten?', 'Für dein Konto: E-Mail-Adresse und Passwort (das Passwort speichert Firebase '
      'nur verschlüsselt). Deine Einträge: Fahrten (Betrag, Zeit, Quelle, Zahlungsart, optional '
      'Trinkgeld, Strecke, Notiz), Schichten, Pausen, Kosten, Fahrtquellen und Fahrernummer.\n\n'
      'Beim Aufruf der Website verarbeitet der Hosting-Anbieter technisch notwendige Daten wie '
      'IP-Adresse, Zeitpunkt und Browser (Server-Protokolle).'),
  ('Wozu und auf welcher Grundlage?', 'Ausschließlich, um dir das Logbuch bereitzustellen und deine '
      'Einträge auf deinen Geräten zu synchronisieren (Art. 6 Abs. 1 lit. b DSGVO). Die '
      'Server-Protokolle dienen dem sicheren Betrieb (Art. 6 Abs. 1 lit. f DSGVO). Es gibt keine '
      'Werbung, kein Tracking und keine Weitergabe zu Werbezwecken.'),
  ('Dienstleister', 'Die App nutzt Google Firebase (Firebase Authentication, Cloud Firestore, Firebase '
      'Hosting) der Google Ireland Limited, Gordon House, Barrow Street, Dublin 4, Irland, als '
      'Auftragsverarbeiter. Dabei kann eine Übermittlung in die USA nicht ausgeschlossen werden; '
      'Google ist nach dem EU-US Data Privacy Framework zertifiziert.\n\n'
      'Für die Darstellung werden Schriftarten von Google-Servern (fonts.gstatic.com) geladen; '
      'dabei wird deine IP-Adresse an Google übertragen.'),
  ('Speicherung im Browser', 'Im Browser werden nur technisch notwendige Daten gespeichert, z. B. '
      'Anmeldestatus, Sprache, Darstellung und die lokale Vorschau. Es werden keine Tracking-Cookies '
      'verwendet.'),
  ('Wie lange?', 'Deine Daten bleiben gespeichert, bis du sie löschst. Unter Profil → „Konto löschen“ '
      'kannst du dein Konto und alle Einträge jederzeit selbst endgültig löschen.'),
  ('Deine Rechte', 'Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der '
      'Verarbeitung, Datenübertragbarkeit (Profil → „Daten exportieren“) und Widerspruch. Du kannst '
      'dich außerdem bei einer Datenschutz-Aufsichtsbehörde beschweren, z. B. bei der Berliner '
      'Beauftragten für Datenschutz und Informationsfreiheit.'),
];

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.privacy = false});
  final bool privacy;

  Widget block(String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      SelectableText(text),
    ]),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: privacy ? 1 : 0,
    child: Scaffold(
      appBar: AppBar(title: Text(tr('Rechtliches')), bottom: const TabBar(tabs: [
        Tab(text: 'Impressum'), Tab(text: 'Datenschutz'),
      ])),
      body: TabBarView(children: [
        ListView(padding: const EdgeInsets.all(20), children: [
          block('Angaben gemäß § 5 DDG', _operator),
          block('Verantwortlich für den Inhalt', LegalConfig.complete ? LegalConfig.operatorName : _operator),
          block('Hinweis', 'Taxi Logbuch ersetzt kein Fiskaltaxameter und keine amtlichen '
              'Aufzeichnungen. Alle Angaben ohne Gewähr.'),
        ]),
        ListView(key: const Key('privacy-policy'), padding: const EdgeInsets.all(20), children: [
          block('Verantwortlicher', _operator),
          for (final (title, text) in _privacy) block(title, text),
          const Text('Stand: November 2026', style: TextStyle(fontSize: 12)),
        ]),
      ]),
    ),
  );
}
