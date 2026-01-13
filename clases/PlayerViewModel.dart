class PlayerViewModel extends Cubit<PlayerViewState> {
  PlayerViewModel({
    required GetCurrentTrackUseCase getCurrentTrackUseCase,
    required GetSystemSoundsUseCase getSystemSoundsUseCase,
    required GetVolumeUseCase getVolumeUseCase,
    required PreloadSlidesService preloadSlidesService,
  })  : _getCurrentTrackUseCase = getCurrentTrackUseCase,
        _getSystemSoundsUseCase = getSystemSoundsUseCase,
        _getVolumeUseCase = getVolumeUseCase,
        _preloadSlidesService = preloadSlidesService,
        super(const PlayerViewState()) {
    LogService.logInfoNavigation("Navigation", "PlayerScreen initialized");
    _initialize();
  }

  final GetCurrentTrackUseCase _getCurrentTrackUseCase;
  final GetSystemSoundsUseCase _getSystemSoundsUseCase;
  final GetVolumeUseCase _getVolumeUseCase;
  final PreloadSlidesService _preloadSlidesService;

  late final GetRecentTrackBloc _getTrackBloc;
  late final ScheduleTrackPlayerService _scheduleTrackPlayerService;
  late final SystemSoundsPlayerService _systemSoundsPlayerManager;
  late final VolumeManager _volumeManager;

  GetRecentTrackBloc get getTrackBloc => _getTrackBloc;
  ScheduleTrackPlayerService get scheduleTrackPlayerService => _scheduleTrackPlayerService;
  PreloadSlidesService get preloadSlidesService => _preloadSlidesService;

  void _initialize() {
    _scheduleTrackPlayerService = ScheduleTrackPlayerService();
    _systemSoundsPlayerManager = SystemSoundsPlayerService();

    _getTrackBloc = GetRecentTrackBloc(
      _getCurrentTrackUseCase,
      _scheduleTrackPlayerService,
      _preloadSlidesService,
    )..add(LoadLocalTrackEvent());

    _initVolumeManager();
    _scheduleTrackPlayerService.addListener(_onPlayerManagerUpdate);
  }

  void _onPlayerManagerUpdate() {
    emit(state.copyWith(updateTrigger: DateTime.now().millisecondsSinceEpoch));
  }

  Future<void> _initVolumeManager() async {
    _volumeManager = VolumeManager(
      _scheduleTrackPlayerService,
      _systemSoundsPlayerManager,
      _getVolumeUseCase,
    );
    await _volumeManager.initVolumeManager();
  }

  Future<void> handleCommand(CommandType commandType) async {
    try {
      final trackFile = await _getSystemSoundsUseCase.getSystemSound(
        commandType,
      );
      if (trackFile != null) {
        await _systemSoundsPlayerManager.playSystemSound(
          trackFile,
          Duration.zero,
        );
        _volumeManager.updateVolume(commandType);
      } else {
        LogService.logWarning(LogTags.playerViewModel, "handleCommand", "Track file is null");
      }
    } catch (e, stackTrace) {
      LogService.logError(LogTags.playerViewModel, "handleCommand", "Error executing command", e, stackTrace);
    }
  }

  Future<void> onTrackChanged(PlayingMediaModel track) async {
    final file = track.file;
    if (file == null) {
       LogService.logWarning(LogTags.playerViewModel, "onTrackChanged", "File is null");
       return;
    }

    final fileType = FileTypeX.fromString(track.track.type);
    LogService.logInfo(LogTags.playerViewModel, "onTrackChanged", "Incoming track: ${file.path}, Type: $fileType");

    if (fileType == FileType.slide) {
      LogService.logInfo(LogTags.playerViewModel, "onTrackChanged", "Type is SLIDE. Ignoring video player update.");
      return; 
    }

    if (fileType != FileType.video && fileType != FileType.audio) {
       LogService.logWarning(LogTags.playerViewModel, "onTrackChanged", "Unsupported file type: $fileType");
       return;
    }

    if (scheduleTrackPlayerService.currentTrack?.path == file.path) {
       LogService.logInfo(LogTags.playerViewModel, "onTrackChanged", "Track already playing. Skipping.");
       return;
    }

    final seekDuration = Duration(
      milliseconds: ((track.seekPosition ?? 0) * 1000).round(),
    );

    await scheduleTrackPlayerService.playTrack(
      file,
      seekDuration,
      track.tag,
      track.track.playlistSk,
      track.track.sk,
      track.track.filename,
      track.track.type,
      track.track.title,
      track.track.artist,
      track.track.campaignSk,
    );
  }

  @override
  Future<void> close() {
    _scheduleTrackPlayerService.removeListener(_onPlayerManagerUpdate);
    _scheduleTrackPlayerService.dispose();
    _systemSoundsPlayerManager.dispose();
    _volumeManager.dispose();
    _getTrackBloc.close();
    return super.close();
  }
}