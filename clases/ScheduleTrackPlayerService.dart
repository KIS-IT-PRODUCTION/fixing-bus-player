class ScheduleTrackPlayerService with ChangeNotifier {
  ScheduleTrackPlayerService() {
    _videoController = VideoController(_player);
    _player.setPlaylistMode(PlaylistMode.none);
    _initializePlaybackLoggerService();
  }

  final Player _player = Player();
  late final VideoController _videoController;
  late final PlaybackLoggerService _playbackLoggerService;

  File? get currentTrack => _currentTrack;
  VideoController get videoController => _videoController;

  bool get isChangingTrack => _isChangingTrack;

  File? _currentTrack;
  bool _isChangingTrack = false;
  StreamSubscription? _completedSubscription;
  final List<String> _addedTrackPaths = [];

  Future<void> addTrackToPlaylist(File file) async {
    final path = file.path;

    if (_addedTrackPaths.contains(path)) {
      return;
    }
    _addedTrackPaths.add(path);

    try {
      final media = Media(path);
      await _player.add(media);
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "addTrackToPlaylist", "Added to playlist: $path");
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "addTrackToPlaylist", "Error adding track", e, stackTrace);
      _addedTrackPaths.remove(path);
    }
  }

  _initializePlaybackLoggerService() async {
    _playbackLoggerService = PlaybackLoggerService();
    _playbackLoggerService.initPlaybackLoggerService();
  }

  Future<void> pauseForSlide() async {
    try {
      await _player.pause();
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "pauseForSlide", "Error pausing player for slide", e, stackTrace);
    }
  }

  Future<void> playTrack(File file, Duration? seekPosition, String? tag, String? sk, String? playlistSk, String? filename, String? type, String? title, String? artist, String? campaignSk) async {
    if (_isChangingTrack) {
      return;
    }

    _isChangingTrack = true;
    notifyListeners();

    try {
      await _player.stop();

      final playlist = _player.state.playlist;
      if (playlist.medias.isEmpty) {
        _isChangingTrack = false;
        notifyListeners();
        return;
      }

      final index = _findTrackIndex(playlist, file);
      if (index == -1) {
        _isChangingTrack = false;
        notifyListeners();
        return;
      }

      _currentTrack = file;

      await _player.jump(index);
      await _waitForPlayerReady(index);

      if (seekPosition != null && seekPosition > Duration.zero) {
        await _player.seek(seekPosition);
      }
      
      await _player.play();

      _playbackLoggerService.logTrack(tag: tag, sk: sk, playlistSk: playlistSk, filename: filename, title: title, artist: artist, type: type, campaignSk: campaignSk);

    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "Error in playTrack", e, stackTrace);
    } finally {
      await Future.delayed(const Duration(milliseconds: 350));
      _isChangingTrack = false;
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) {
    return _player.setVolume(volume);
  }

  int _findTrackIndex(Playlist playlist, File file) {
    return playlist.medias.indexWhere((media) {
      final mediaName = media.uri.split('/').last;
      final fileName = file.path.split('/').last;
      return mediaName == fileName;
    });
  }

  Future<void> _waitForPlayerReady(int expectedIndex) async {
    int attempts = 0;
    while (attempts < 20) {
      if (_player.state.playlist.index == expectedIndex) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _completedSubscription?.cancel();
    _currentTrack = null;
    _playbackLoggerService.disposePlaybackLoggerService();
    super.dispose();
  }
}