import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n_strings.dart';

/// App languages. German is the source language; Persian and Arabic are RTL.
enum AppLanguage {
  de('Deutsch', Locale('de', 'DE'), 'de_DE'),
  en('English', Locale('en'), 'en'),
  fa('فارسی', Locale('fa'), 'fa'),
  tr('Türkçe', Locale('tr'), 'tr'),
  ar('العربية', Locale('ar'), 'ar');

  const AppLanguage(this.label, this.locale, this.intlLocale);
  final String label;
  final Locale locale;
  final String intlLocale;
}

final language = ValueNotifier<AppLanguage>(AppLanguage.de);
const _languageKey = 'language';

void loadLanguage(SharedPreferences preferences) {
  language.value = AppLanguage.values.asNameMap()[preferences.getString(_languageKey)] ?? AppLanguage.de;
}

Future<void> saveLanguage(SharedPreferences preferences, AppLanguage value) async {
  language.value = value;
  await preferences.setString(_languageKey, value.name);
}

/// Locale for month and weekday names in the chosen language.
String get dateLocale => language.value.intlLocale;

/// Translates German source text into the current language (German fallback).
String tr(String german) {
  final lang = language.value;
  if (lang == AppLanguage.de) return german;
  return translations[german]?[lang.index - 1] ?? german;
}
