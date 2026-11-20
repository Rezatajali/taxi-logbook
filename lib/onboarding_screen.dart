import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';

/// Three short pages shown once per device after the first sign-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  static const doneKey = 'onboarding_done';

  static bool shouldShow(SharedPreferences preferences) => !(preferences.getBool(doneKey) ?? false);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pages = PageController();
  int page = 0;

  List<(IconData, String, String)> get steps => [
    (Icons.local_taxi_rounded, tr('Fahrt in Sekunden erfassen'),
      tr('Unten auf „Fahrt erfassen“ tippen, Betrag eingeben (2270 → 22,70 €), Art wählen – fertig.')),
    (Icons.pause_circle_outline, tr('Schichten und Pausen'),
      tr('Unter „Schichten“ startest du Schicht und Pausen. Fahrten nach Mitternacht zählen zum Tag des Schichtbeginns.')),
    (Icons.auto_awesome_outlined, tr('Monat und Extras'),
      tr('Im Monat siehst du Umsatz und Wochenvergleich, unter Extras Kassensturz, Kosten, Trinkgeld und Statistik.')),
  ];

  @override
  void dispose() { pages.dispose(); super.dispose(); }

  Future<void> finish() async {
    (await SharedPreferences.getInstance()).setBool(OnboardingScreen.doneKey, true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = page == steps.length - 1;
    return Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
      Align(alignment: AlignmentDirectional.centerEnd,
        child: TextButton(onPressed: finish, child: Text(tr('Überspringen')))),
      Expanded(child: PageView(
        controller: pages,
        onPageChanged: (value) => setState(() => page = value),
        children: [
          for (final (icon, title, text) in steps) Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 64, color: scheme.primary)),
            const SizedBox(height: 32),
            Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
          ]),
        ],
      )),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < steps.length; i++) AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4), width: i == page ? 22 : 8, height: 8,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4),
            color: i == page ? scheme.primary : scheme.primary.withValues(alpha: 0.3))),
      ]),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: FilledButton(
        key: const Key('onboarding-next'),
        onPressed: last ? finish : () => pages.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        child: Text(last ? tr('Los geht’s') : tr('Weiter')))),
    ]))));
  }
}
