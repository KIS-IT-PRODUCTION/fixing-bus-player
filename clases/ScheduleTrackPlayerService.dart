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
  var index = 0;

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
      LogService.logError(LogTags.scheduleTrackPlayerService, "addTrackToPlaylist", "Error adding track",  e,  stackTrace);
      _addedTrackPaths.remove(path);
    }
  }

  _initializePlaybackLoggerService() async{
    _playbackLoggerService = PlaybackLoggerService();
    _playbackLoggerService.initPlaybackLoggerService();
  }

  // ---> НОВИЙ МЕТОД ДЛЯ СЛАЙДІВ <---
  Future<void> pauseForSlide() async {
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "pauseForSlide", ">>> FREEZING PLAYER (Slide Active)");
    try {
      // Зупиняємо відео, щоб воно не перейшло на наступний трек під слайдом
      await _player.pause();
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "pauseForSlide", "Player paused successfully.");
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "pauseForSlide", "Error pausing player for slide", e, stackTrace);
    }
  }

  Future<void> playTrack(File file, Duration? seekPosition, String? tag, String? sk, String? playlistSk, String? filename, String? type, String? title, String? artist, String? campaignSk) async {
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", ">>> START playTrack: ${file.path}");

    if (_isChangingTrack) {
      LogService.logWarning(LogTags.scheduleTrackPlayerService, "playTrack", "Skipped: Already changing track");
      return;
    }
    
    _isChangingTrack = true;
    notifyListeners();
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "UI Blocked (Black Screen ON)");

    try {
      final playlist = _player.state.playlist;
      if (playlist.medias.isEmpty) {
        LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "Playlist is empty!", null, null);
        return;
      }

      final index = _findTrackIndex(playlist, file);
      if (index == -1) {
        LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "Track not found in playlist: ${file.path}", null, null);
        return;
      }

      _currentTrack = file;
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Track found at index: $index. Pausing...");
      
      await _player.pause();
      
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Jumping to index $index...");
      await _player.jump(index);
      
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Waiting for player ready...");
      await _waitForPlayerReady(index);
      
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Player ready. Sending PLAY command...");
      await _player.play();
      
      _playbackLoggerService.logTrack(tag: tag, sk:sk, playlistSk: playlistSk, filename: filename, title: title, artist: artist, type: type, campaignSk: campaignSk);

      if (seekPosition != null && seekPosition > Duration.zero) {
        LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Seeking to: $seekPosition");
        await _player.seek(seekPosition);
      }
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "CRITICAL ERROR in playTrack",  e,  stackTrace);
    } finally {
      // === ЗМІНА ТУТ ===
      // Збільшуємо час очікування до 400мс, щоб гарантувати, 
      // що попередній кадр з буфера відеокарти точно замінився новим.
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "Delaying removal of black screen (400ms)...");
      await Future.delayed(const Duration(milliseconds: 400));
      
      _isChangingTrack = false;
      notifyListeners();
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "<<< END playTrack (Black Screen OFF)");
    }
  }

  Future <void> setVolume(double volume) {
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "setVolume", "Volume set to: $volume");
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
    while ((_player.state.buffering ||
        _player.state.playlist.index != expectedIndex) &&
        attempts < 50) {
      
      if (attempts % 5 == 0) {
         LogService.logInfo(LogTags.scheduleTrackPlayerService, "_waitForPlayerReady", "Attempt $attempts: Buffering=${_player.state.buffering}, Index=${_player.state.playlist.index} vs $expectedIndex");
      }
      
      await Future.delayed(const Duration(milliseconds: 50));
      attempts++;
    }
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "_waitForPlayerReady", "Finished waiting. Attempts: $attempts");
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