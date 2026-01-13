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

  // Геттер для стану завантаження
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
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "addTrackToPlaylist", "Error adding track",  e,  stackTrace);
      _addedTrackPaths.remove(path);
    }
  }

  _initializePlaybackLoggerService() async{
    _playbackLoggerService = PlaybackLoggerService();
    _playbackLoggerService.initPlaybackLoggerService();
  }

  // Новий метод для зупинки
  Future<void> stop() async {
    _currentTrack = null;
    await _player.stop();
    notifyListeners();
  }

  Future<void> playTrack(File file, Duration? seekPosition, String? tag, String? sk, String? playlistSk, String? filename, String? type, String? title, String? artist, String? campaignSk) async {
    if (_isChangingTrack) return;
    
    _isChangingTrack = true;
    notifyListeners(); 

    try {
      final playlist = _player.state.playlist;
      if (playlist.medias.isEmpty) return;

      final index = _findTrackIndex(playlist, file);
      if (index == -1) return;

      _currentTrack = file;
      
      // Логіка перемикання
      await _player.pause();
      await _player.jump(index);
      await _waitForPlayerReady(index);
      await _player.play();
      
      _playbackLoggerService.logTrack(tag: tag, sk:sk, playlistSk: playlistSk, filename: filename, title: title, artist: artist, type: type, campaignSk: campaignSk);

      if (seekPosition != null && seekPosition > Duration.zero) {
        await _player.seek(seekPosition);
      }
      
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "Error playing track",  e,  stackTrace);
    } finally {
      _isChangingTrack = false;
      notifyListeners();
    }
  }

  Future <void> setVolume(double volume) {
    LogService.logInfo(LogTags.scheduleTrackPlayerService, "setVolume", "Track player volume: $volume");
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
        _player.state.duration == Duration.zero ||
        _player.state.playlist.index != expectedIndex) &&
        attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
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