import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class LocalizationService extends ChangeNotifier {
  Locale _locale = const Locale('en');
  Map<String, dynamic> _localizedStrings = {};

  Locale get locale => _locale;

  LocalizationService() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final jsonString = await rootBundle.loadString('localization/en.json');
    _localizedStrings = json.decode(jsonString) as Map<String, dynamic>;
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    _locale = Locale(languageCode);
    final jsonString = await rootBundle.loadString(
      'localization/$languageCode.json',
    );
    _localizedStrings = json.decode(jsonString) as Map<String, dynamic>;
    notifyListeners();
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }
}

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> _localizedStrings = {};

  Future<bool> load() async {
    final jsonString = await rootBundle.loadString(
      'localization/${locale.languageCode}.json',
    );
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = jsonMap.map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return true;
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'fil'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
