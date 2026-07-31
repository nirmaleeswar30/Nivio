import 'package:flutter/foundation.dart';
import '../../../core/interfaces/details_repository.dart';
import '../../../core/errors/network_errors.dart';
import '../models/detail_models.dart';
import '../models/detail_route_args.dart';

enum DetailStatus { loading, loaded, empty, offline, apiError, retrying, error }

class DetailController extends ChangeNotifier {
  final DetailsRepository repository;

  DetailController({required this.repository});

  DetailStatus _status = DetailStatus.loading;
  DetailMedia? _media;
  String? _errorMessage;
  DetailRouteArgs? _currentArgs;

  // Active episodes state
  bool _isLoadingEpisodes = false;
  List<DetailEpisode> _episodes = [];
  String? _episodesError;
  int _episodeRequestId = 0;

  DetailStatus get status => _status;
  DetailMedia? get media => _media;
  String? get errorMessage => _errorMessage;
  DetailRouteArgs? get currentArgs => _currentArgs;

  bool get isLoadingEpisodes => _isLoadingEpisodes;
  List<DetailEpisode> get episodes => _episodes;
  String? get episodesError => _episodesError;

  Future<void> loadDetail(DetailRouteArgs args, {bool isRetry = false}) async {
    _currentArgs = args;
    _status = isRetry ? DetailStatus.retrying : DetailStatus.loading;
    _errorMessage = null;
    _media = null;
    _episodes = [];
    _episodesError = null;
    _episodeRequestId++;
    notifyListeners();

    try {
      final details = await repository.loadCompleteDetail(args);
      _media = details;
      _status = DetailStatus.loaded;

      if (details.isSeries && details.seasons.isNotEmpty) {
        final firstPlayableSeason = details.seasons.firstWhere(
          (season) => season.number > 0,
          orElse: () => details.seasons.first,
        );
        await loadSeasonEpisodes(args.mediaId, firstPlayableSeason.number);
      }
    } on TimeoutError catch (e) {
      _status = DetailStatus.offline;
      _errorMessage = e.message;
    } on ApiError catch (e) {
      _status = DetailStatus.apiError;
      _errorMessage = e.message;
    } on NetworkError catch (e) {
      _status = DetailStatus.offline;
      _errorMessage = e.message;
    } catch (e) {
      _status = DetailStatus.error;
      _errorMessage = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> loadSeasonEpisodes(int tvId, int seasonNumber) async {
    final requestId = ++_episodeRequestId;
    _isLoadingEpisodes = true;
    _episodes = [];
    _episodesError = null;
    notifyListeners();

    try {
      final results = await repository.getSeasonEpisodes(
        tvId: tvId,
        seasonNumber: seasonNumber,
      );
      if (requestId != _episodeRequestId) return;
      _episodes = results;
    } catch (e) {
      if (requestId != _episodeRequestId) return;
      _episodes = [];
      _episodesError = e.toString();
    } finally {
      if (requestId == _episodeRequestId) {
        _isLoadingEpisodes = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() async {
    final args = _currentArgs;
    if (args != null) {
      await loadDetail(args, isRetry: true);
    }
  }
}
