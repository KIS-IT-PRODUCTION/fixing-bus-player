import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soloveiko_media_player/data/local/model/playing_track_model.dart';
import 'package:soloveiko_media_player/data/local/model/track_status.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_service.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_tags.dart';
import 'package:soloveiko_media_player/domain/service/player_service/video_player_manager_service.dart';
import 'package:soloveiko_media_player/domain/service/preload_slides_service/preload_slides_service.dart';
import 'package:soloveiko_media_player/domain/usecase/get_current_track_use_case.dart';
import 'get_recent_track_event.dart';
import 'get_recent_track_state.dart';

class GetRecentTrackBloc extends Bloc<GetRecentTrackEvent, GetRecentTrackState> {
  final GetCurrentTrackUseCase getCurrentlyPlayingTrackUseCase;
  final ScheduleTrackPlayerService _playerManager;
  PlayingMediaModel? _currentTrack;
  final PreloadSlidesService _preloadSlidesService;

  GetRecentTrackBloc(
      this.getCurrentlyPlayingTrackUseCase,
      this._playerManager,
      this._preloadSlidesService,
      ) : super(RecentTrackInitial()) {
    on<LoadLocalTrackEvent>(_onLoadLocalTrack);
    on<_InternalTrackChangedEvent>(_onInternalTrackChanged);
  }

  Future<void> _onLoadLocalTrack(
      LoadLocalTrackEvent event,
      Emitter<GetRecentTrackState> emit,
      ) async {
    emit(RecentTrackLoading());

    getCurrentlyPlayingTrackUseCase.setTrackChangedCallback((status) {
      if (!isClosed) {
        add(_InternalTrackChangedEvent(status));
      }
    });

    try {
      await getCurrentlyPlayingTrackUseCase.startPeriodicWork();
    } catch (e, stackTrace) {
      LogService.logError(LogTags.getRecentTrackBloc, "_onLoadLocalTrack", "Unexpected error", e, stackTrace);
      emit(RecentTrackError('Unexpected error: $e'));
    }
  }

  void _onInternalTrackChanged(
      _InternalTrackChangedEvent event,
      Emitter<GetRecentTrackState> emit,
      ) async {
    final status = event.status;

    if (status is TrackPlaying) {
      final newTrack = status.track;
      final newFile = newTrack?.file;
      

      final isNewTrack = _currentTrack?.file?.path != newFile?.path;
      
      _currentTrack = newTrack;

      final fileType = FileTypeX.fromString(newTrack?.track.type);
      
      if (fileType == FileType.slide) {
        await _preloadSlidesService.preCacheSlide(newTrack?.file, newTrack?.track.filename);
      } else if (fileType == FileType.video || fileType == FileType.audio) {
        if (newFile != null) {
          if (isNewTrack || _playerManager.currentTrack == null) {

             await _playerManager.addTrackToPlaylist(newFile);
          }
        }
      }
      
      emit(RecentTrackSuccess(currentTrack: _currentTrack));
      
    } else if (status is TrackOutOfSchedule) {
      _currentTrack = null;
      emit(RecentTrackOutOfSchedule());
    } else if (status is TrackNotFound) {
      emit(RecentTrackError('File not found'));
    } else if (status is TrackError) {
      emit(RecentTrackError('Failed to load track: ${status.error}'));
    }
  }
}

class _InternalTrackChangedEvent extends GetRecentTrackEvent {
  final TrackStatus status;
  _InternalTrackChangedEvent(this.status);
}
