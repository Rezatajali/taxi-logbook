import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Step-by-step guide to add the web app to the phone's home screen.
class InstallScreen extends StatelessWidget {
  const InstallScreen({super.key});

  static const appUrl = 'https://taxi-logbook-d1104.web.app';

  @override
  Widget build(BuildContext context) {
    final android = defaultTargetPlatform == TargetPlatform.android;
    return DefaultTabController(
      length: 2,
      initialIndex: android ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('App aufs Handy holen'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.phone_iphone), text: 'iPhone'),
            Tab(icon: Icon(Icons.phone_android), text: 'Android'),
          ]),
        ),
        body: const TabBarView(children: [
          _Steps(key: Key('install-ios'), steps: [
            _Step(Icons.public, 'Link in Safari öffnen',
                'Öffne $appUrl in Safari. In anderen Browsern fehlt die Funktion oft.'),
            _Step(Icons.ios_share, 'Auf „Teilen“ tippen',
                'Das Quadrat mit dem Pfeil nach oben – unten in der Leiste (bei neuen iPhones evtl. erst „…“ antippen).'),
            _Step(Icons.add_box_outlined, '„Zum Home-Bildschirm“ wählen',
                'In der Liste etwas nach unten scrollen und „Zum Home-Bildschirm“ antippen.'),
            _Step(Icons.check_circle_outline, 'Oben rechts „Hinzufügen“',
                'Fertig: Das Taxi-Logbuch-Symbol liegt jetzt auf deinem Home-Bildschirm und öffnet sich wie eine App.'),
          ]),
          _Steps(key: Key('install-android'), steps: [
            _Step(Icons.public, 'Link in Chrome öffnen', 'Öffne $appUrl in Google Chrome.'),
            _Step(Icons.more_vert, 'Drei-Punkte-Menü öffnen', 'Oben rechts auf die drei Punkte tippen.'),
            _Step(Icons.install_mobile, '„App installieren“ wählen',
                'Je nach Handy heißt es auch „Zum Startbildschirm hinzufügen“.'),
            _Step(Icons.check_circle_outline, '„Installieren“ bestätigen',
                'Fertig: Das Symbol liegt auf dem Startbildschirm und öffnet sich wie eine App.'),
          ]),
        ]),
      ),
    );
  }
}

class _Step {
  const _Step(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

class _Steps extends StatelessWidget {
  const _Steps({super.key, required this.steps});
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      for (final (index, step) in steps.indexed)
        Card(margin: const EdgeInsets.only(bottom: 14), child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 22, backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Text('${index + 1}', style: TextStyle(color: scheme.primary,
                fontWeight: FontWeight.w800, fontSize: 18))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(step.icon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(step.title, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17))),
              ]),
              const SizedBox(height: 6),
              Text(step.text),
            ])),
          ]),
        )),
      const SizedBox(height: 8),
      const Text('Die Daten bleiben in deinem Konto – egal ob du die App über das '
          'Symbol oder im Browser öffnest. Updates kommen automatisch.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
    ]);
  }
}
