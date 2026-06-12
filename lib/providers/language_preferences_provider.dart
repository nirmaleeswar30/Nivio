import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Language preference model
class LanguagePreferences {
  final bool showAnime;
  final bool showTamil;
  final bool showTelugu;
  final bool showHindi;
  final bool showKorean;
  final String animePreferredAudio; // 'sub' or 'dub'

  const LanguagePreferences({
    this.showAnime = true,
    this.showTamil = true,
    this.showTelugu = true,
    this.showHindi = true,
    this.showKorean = true,
    this.animePreferredAudio = 'sub',
  });

  LanguagePreferences copyWith({
    bool? showAnime,
    bool? showTamil,
    bool? showTelugu,
    bool? showHindi,
    bool? showKorean,
    String? animePreferredAudio,
  }) {
    return LanguagePreferences(
      showAnime: showAnime ?? this.showAnime,
      showTamil: showTamil ?? this.showTamil,
      showTelugu: showTelugu ?? this.showTelugu,
      showHindi: showHindi ?? this.showHindi,
      showKorean: showKorean ?? this.showKorean,
      animePreferredAudio: animePreferredAudio ?? this.animePreferredAudio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showAnime': showAnime,
      'showTamil': showTamil,
      'showTelugu': showTelugu,
      'showHindi': showHindi,
      'showKorean': showKorean,
      'animePreferredAudio': animePreferredAudio,
    };
  }

  factory LanguagePreferences.fromJson(Map<String, dynamic> json) {
    return LanguagePreferences(
      showAnime: json['showAnime'] ?? true,
      showTamil: json['showTamil'] ?? true,
      showTelugu: json['showTelugu'] ?? true,
      showHindi: json['showHindi'] ?? true,
      showKorean: json['showKorean'] ?? true,
      animePreferredAudio: json['animePreferredAudio'] ?? 'sub',
    );
  }
}

// Language preferences notifier
class LanguagePreferencesNotifier extends StateNotifier<LanguagePreferences> {
  LanguagePreferencesNotifier() : super(const LanguagePreferences()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showAnime = prefs.getBool('showAnime') ?? true;
    final showTamil = prefs.getBool('showTamil') ?? true;
    final showTelugu = prefs.getBool('showTelugu') ?? true;
    final showHindi = prefs.getBool('showHindi') ?? true;
    final showKorean = prefs.getBool('showKorean') ?? true;
    final animePreferredAudio = prefs.getString('animePreferredAudio') ?? 'sub';

    state = LanguagePreferences(
      showAnime: showAnime,
      showTamil: showTamil,
      showTelugu: showTelugu,
      showHindi: showHindi,
      showKorean: showKorean,
      animePreferredAudio: animePreferredAudio,
    );
  }

  Future<void> toggleAnime(bool value) async {
    state = state.copyWith(showAnime: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showAnime', value);
  }

  Future<void> toggleTamil(bool value) async {
    state = state.copyWith(showTamil: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showTamil', value);
  }

  Future<void> toggleTelugu(bool value) async {
    state = state.copyWith(showTelugu: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showTelugu', value);
  }

  Future<void> toggleHindi(bool value) async {
    state = state.copyWith(showHindi: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showHindi', value);
  }

  Future<void> toggleKorean(bool value) async {
    state = state.copyWith(showKorean: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showKorean', value);
  }
  
  Future<void> setAnimePreferredAudio(String audio) async {
    state = state.copyWith(animePreferredAudio: audio);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('animePreferredAudio', audio);
  }
}

// Language preferences provider
final languagePreferencesProvider =
    StateNotifierProvider<LanguagePreferencesNotifier, LanguagePreferences>((
      ref,
    ) {
      return LanguagePreferencesNotifier();
    });
