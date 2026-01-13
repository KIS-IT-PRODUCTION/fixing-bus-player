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

  Future<void> playTrack(File file, Duration? seekPosition, String? tag, String? sk, String? playlistSk, String? filename, String? type, String? title, String? artist, String? campaignSk) async {
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", ">>> START playTrack: ${file.path}");

    if (_isChangingTrack) {
      LogService.logWarning(LogTags.scheduleTrackPlayerService, "playTrack", "Skipped: Already changing track");
      return;
    }
    
    _isChangingTrack = true;
    notifyListeners();
    
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
      
      await _player.pause();
      await _player.jump(index);
      await _waitForPlayerReady(index);
      await _player.play();
      
      _playbackLoggerService.logTrack(tag: tag, sk:sk, playlistSk: playlistSk, filename: filename, title: title, artist: artist, type: type, campaignSk: campaignSk);

      if (seekPosition != null && seekPosition > Duration.zero) {
        await _player.seek(seekPosition);
      }
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "CRITICAL ERROR in playTrack",  e,  stackTrace);
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      _isChangingTrack = false;
      notifyListeners();
      LogService.logInfo(LogTags.scheduleTrackPlayerService, "playTrack", "<<< END playTrack");
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