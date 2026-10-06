import 'package:flutter/material.dart';

class _GuideStep {
  const _GuideStep(this.title, this.text, this.icon);
  final String title;
  final String text;
  final IconData icon;
}

const _steps = [
  _GuideStep('Anmelden oder registrieren',
    'Beim ersten Mal „Registrieren“ wählen. E-Mail, Passwort und Passwort-Wiederholung eingeben. Danach mit E-Mail und Passwort anmelden.\n\nPasswort vergessen? Einen neuen Link anfordern und den neuesten Link in deinem E-Mail-Postfach öffnen.', Icons.login),
  _GuideStep('Home: Dein Tag auf einen Blick',
    'Hier siehst du den heutigen Umsatz, die Bar-Einnahmen und deine Fahrten.\n\nZum Erfassen einer neuen Fahrt unten auf „Schichten“ tippen.', Icons.space_dashboard_outlined),
  _GuideStep('Schichten: Den Tag auswählen',
    'Mit den Pfeilen den Tag wechseln oder auf das große Datum tippen.\n\n„Fahrt erfassen“ gibt es nur auf dieser Seite. Eine neue Fahrt wird dem ausgewählten Tag zugeordnet.', Icons.calendar_month_outlined),
  _GuideStep('Eine Fahrt erfassen',
    'Nur Ziffern tippen: 2270 wird zu 22,70 €. Für 22 Euro 2200 eingeben.\n\nNeben dem Betrag die Art wählen: Bar, Uber, Karte, Rechnung, Bolt oder FREENOW. Datum und Uhrzeit lassen sich getrennt ändern. Zum Schluss „Fahrt speichern“ tippen.', Icons.add_circle_outline),
  _GuideStep('Fahrten bearbeiten oder löschen',
    'Jede Fahrt bleibt ein eigener Eintrag. Mit „Bearbeiten“ den Betrag oder die Angaben ändern und erneut speichern.\n\nBearbeitete Fahrten werden gelb markiert. Gelöschte Fahrten bleiben rot und durchgestrichen sichtbar, zählen aber nicht mehr zum Umsatz. Unter „Änderungsverlauf“ findest du die vorherigen Werte.', Icons.edit_outlined),
  _GuideStep('Monat: Umsatz und Diagramm',
    'Mit den Pfeilen den Monat auswählen. Hier findest du den Gesamtumsatz, Bar-Einnahmen und den Durchschnitt pro Tag mit Fahrten.\n\nIm Diagramm auf einen Tag tippen, um seinen Umsatz zu sehen. €/km berücksichtigt nur Fahrten mit eingetragener Strecke.', Icons.bar_chart),
  _GuideStep('Profil: Deine Fahrernummer',
    'Unter „Nummer ändern“ deine eigene Nummer eintragen, zum Beispiel 267. Danach steht „Fahrer 267“ oben und bei deinen Fahrten.\n\nAngemeldete Fahrer speichern ihre Daten im eigenen Cloud-Konto. Die lokale Vorschau ist davon getrennt. Im Profil findest du auch Export und Abmelden.', Icons.badge_outlined),
  _GuideStep('Pausen: Timer oder manuell',
    'Unten auf „Pausen“ tippen. „Pause starten“ beginnt den Timer; „Pause beenden“ speichert das Ende. Der Timer bleibt auch beim Schließen der App erhalten.\n\nMit „Pause manuell eintragen“ Beginn und Ende nachtragen. Über das Datum frühere Tage ansehen. GPS-Erkennung ist noch nicht aktiv.', Icons.pause_circle_outline),
  _GuideStep('Ein Symbol auf dem Handy',
    'iPhone: Den Link in Safari öffnen → Teilen → Zum Home-Bildschirm.\n\nAndroid: Den Link in Chrome öffnen → Dreipunkt-Menü → Installieren oder Zum Startbildschirm hinzufügen.\n\nDanach über das Symbol starten. Für diese Web-Version brauchst du keine APK und keinen App Store.', Icons.add_to_home_screen),
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final pages = PageController();
  int page = 0;
  static const green = Color(0xFF00C99A);
  static const gold = Color(0xFFF3C45D);

  @override
  void dispose() { pages.dispose(); super.dispose(); }

  Widget previewLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [Expanded(child: Text(label)), const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))]),
  );

  Widget previewButton(String label, {IconData icon = Icons.touch_app_outlined}) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(color: green.withValues(alpha: 0.13),
      border: Border.all(color: green), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Icon(icon, color: green, size: 22), const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)))]),
  );

  Widget datePreview() => const Row(children: [
    Icon(Icons.chevron_left, color: gold),
    Expanded(child: Text('06.10.2026', textAlign: TextAlign.center,
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
    Icon(Icons.chevron_right, color: gold),
  ]);

  Widget illustration(int index) {
    final children = switch (index) {
      0 => <Widget>[
        previewLine('E-Mail', 'name@beispiel.de'),
        previewLine('Passwort', '••••••••'),
        previewButton('Anmelden', icon: Icons.login),
        const Text('Noch kein Konto? Registrieren', style: TextStyle(color: gold)),
        const SizedBox(height: 10), const Text('Passwort vergessen?'),
      ],
      1 => <Widget>[
        const Text('Umsatz heute', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        const Text('120,00 €', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: gold)),
        previewLine('Bar', '70,00 €'), previewLine('Fahrten', '5'),
        previewButton('Unten: Schichten', icon: Icons.local_taxi_outlined),
      ],
      2 => <Widget>[
        datePreview(), const SizedBox(height: 16),
        previewLine('Fahrer 267 · Bar', '22,70 €'),
        previewButton('Fahrt erfassen', icon: Icons.add),
      ],
      3 => <Widget>[
        const Text('Ziffern eingeben', style: TextStyle(color: gold)),
        const SizedBox(height: 8),
        const Text('2270 → 22,70 €', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        previewButton('Art: Bar  ↕', icon: Icons.payments_outlined),
        datePreview(), previewLine('Uhrzeit separat ändern', '14:37'),
        previewButton('Fahrt speichern', icon: Icons.check),
      ],
      4 => <Widget>[
        previewLine('Fahrer 267', '22,70 €'),
        const Text('14:37 · Taxi · Bar'),
        previewButton('Bearbeiten', icon: Icons.edit_outlined),
        previewButton('Löschen → bestätigen', icon: Icons.delete_outline),
        const SizedBox(height: 8), const Text('Weitere Angaben (optional)  ⌄'),
      ],
      5 => <Widget>[
        const Text('‹   Oktober 2026   ›', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        previewLine('Monatsumsatz', '1.200,00 €'),
        previewLine('Ø Tag mit Fahrten', '120,00 €'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 4; i++) Expanded(child: Column(children: [
            Container(width: 28, height: [40.0, 70.0, 55.0, 90.0][i],
              decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(5))),
            const SizedBox(height: 6), Text('${i + 1}'),
          ])),
        ]),
      ],
      6 => <Widget>[
        const Icon(Icons.badge_outlined, size: 44, color: green),
        const SizedBox(height: 10),
        const Text('Fahrer 267', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        previewButton('Nummer ändern', icon: Icons.edit_outlined),
        previewLine('Speicherung', 'Cloud'),
        previewButton('Abmelden', icon: Icons.logout),
      ],
      7 => <Widget>[
        previewLine('Pause läuft', '00:20:00'),
        previewButton('Pause starten', icon: Icons.pause_circle_outline),
        previewButton('Pause beenden', icon: Icons.stop_circle_outlined),
        previewButton('Pause manuell eintragen', icon: Icons.edit_calendar_outlined),
      ],
      _ => <Widget>[
        previewButton('Safari → Teilen ↑', icon: Icons.ios_share),
        previewButton('Zum Home-Bildschirm', icon: Icons.add_box_outlined),
        const Divider(height: 28),
        previewButton('Chrome → Menü ⋮', icon: Icons.more_vert),
        previewButton('Installieren / Startbildschirm', icon: Icons.install_mobile),
      ],
    };
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF232238),
        borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...children, const SizedBox(height: 16),
        const Text('Abbildung zur Erklärung · Beispieldaten',
          style: TextStyle(fontSize: 12, color: Colors.white60)),
      ]),
    );
  }

  void go(int index) => pages.animateToPage(index,
    duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('So funktioniert dein Logbuch')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Row(children: [
          const Icon(Icons.menu_book_outlined, color: gold), const SizedBox(width: 10),
          Text('Schritt ${page + 1} von ${_steps.length}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ])),
        Expanded(child: PageView.builder(controller: pages, itemCount: _steps.length,
          onPageChanged: (value) => setState(() => page = value),
          itemBuilder: (context, index) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(_steps[index].icon, color: gold), const SizedBox(width: 10),
                Expanded(child: Text(_steps[index].title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)))]),
              const SizedBox(height: 18), illustration(index), const SizedBox(height: 20),
              Text(_steps[index].text, style: const TextStyle(fontSize: 18, height: 1.5)),
            ]),
          ),
        )),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: page == 0 ? null : () => go(page - 1),
            child: const Text('Zurück'))), const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: page == _steps.length - 1
            ? () => Navigator.pop(context) : () => go(page + 1),
            child: Text(page == _steps.length - 1 ? 'Fertig' : 'Weiter'))),
        ])),
      ]),
    ))),
  );
}
