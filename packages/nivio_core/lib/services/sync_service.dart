import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final syncServiceProvider = ChangeNotifierProvider((ref) => SyncService().._init());

class SyncService extends ChangeNotifier {
  static const String _anilistClientId = 'YOUR_ANILIST_CLIENT_ID_HERE';
  static const String _malClientId = 'YOUR_MAL_CLIENT_ID_HERE';

  String? _anilistToken;
  String? _malToken;

  bool get isAniListConnected => _anilistToken != null;
  bool get isMALConnected => _malToken != null;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _anilistToken = prefs.getString('anilist_access_token');
    _malToken = prefs.getString('mal_access_token');
    notifyListeners();
  }

  Future<void> loginAniList() async {
    final url = Uri.parse(
        'https://anilist.co/api/v2/oauth/authorize?client_id=$_anilistClientId&response_type=token');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> loginMAL() async {
    final url = Uri.parse(
        'https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=$_malClientId&code_challenge=PLACEHOLDER');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> syncWatchHistory({
    required int mediaId,
    required int episode,
    required String type,
  }) async {
    if (isAniListConnected) {
      print('Syncing episode $episode of media $mediaId to AniList...');
    }
    
    if (isMALConnected) {
      print('Syncing episode $episode of media $mediaId to MyAnimeList...');
    }
  }
}
