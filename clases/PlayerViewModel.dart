import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:soloveiko_media_player/data/local/model/playing_track_model.dart';
import 'package:soloveiko_media_player/data/local/model/track_model.dart';
import 'package:soloveiko_media_player/data/remote/model/comand_type.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_service.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_tags.dart';
import 'package:soloveiko_media_player/domain/service/player_service/system_sounds_player_service.dart';
import 'package:soloveiko_media_player/domain/service/player_service/video_player_manager_service.dart';
import 'package:soloveiko_media_player/domain/service/player_service/volume_manager.dart';
import 'package:soloveiko_media_player/domain/service/preload_slides_service/preload_slides_service.dart';
import 'package:soloveiko_media_player/domain/usecase/get_current_track_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/get_system_sounds_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/get_volume_use_case.dart';
import 'package:soloveiko_media_player/presentation/bloc/getrecenttrackbloc/get_recent_track_bloc.dart';
import 'package:soloveiko_media_player/presentation/bloc/getrecenttrackbloc/get_recent_track_event.dart';
import 'player_view_state.dart';

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
    _scheduleTrackPlayerService = GetIt.I<ScheduleTrackPlayerService>();
    _systemSoundsPlayerManager = GetIt.I<SystemSoundsPlayerService>();

    _getTrackBloc = GetRecentTrackBloc(
      _getCurrentTrackUseCase,
      _scheduleTrackPlayerService,
      _preloadSlidesService,
    )..add(LoadLocalTrackEvent());

    _initVolumeManager();
    _scheduleTrackPlayerService.addListener(_onPlayerManagerUpdate);
  }

  void _onPlayerManagerUpdate() {
    if (!isClosed) {
       emit(state.copyWith(updateTrigger: DateTime.now().millisecondsSinceEpoch));
    }
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
      }
    } catch (e, stackTrace) {
      LogService.logError(LogTags.playerViewModel, "handleCommand", "Error executing command", e, stackTrace);
    }
  }

  Future<void> onTrackChanged(PlayingMediaModel track) async {
    final file = track.file;
    if (file == null) {
      return;
    }

    final fileType = FileTypeX.fromString(track.track.type);

    if (fileType == FileType.slide) {
      await scheduleTrackPlayerService.pauseForSlide();
      return;
    }

    if (fileType != FileType.video && fileType != FileType.audio) {
      return;
    }

    if (scheduleTrackPlayerService.currentTrack?.path == file.path && !scheduleTrackPlayerService.isChangingTrack) {
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
    
    _volumeManager.dispose();
    _getTrackBloc.close();
    return super.close();
  }
}