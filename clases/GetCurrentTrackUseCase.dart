import 'dart:io';
import 'package:soloveiko_media_player/data/local/model/current_track_model.dart';
import 'package:soloveiko_media_player/data/local/model/daily_schedule_model.dart';
import 'package:soloveiko_media_player/data/local/model/playing_track_model.dart';
import 'package:soloveiko_media_player/data/local/model/queue_item_model.dart';
import 'package:soloveiko_media_player/data/local/model/track_status.dart';
import 'package:soloveiko_media_player/domain/repository/local_configuration_repository.dart';
import 'package:soloveiko_media_player/domain/repository/local_slides_repository.dart';
import 'package:soloveiko_media_player/domain/repository/local_tracks_repository.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_service.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_tags.dart';
import 'package:soloveiko_media_player/domain/service/playing_tracks_service/playing_tracks_service.dart';
import 'package:soloveiko_media_player/domain/usecase/build_media_filename_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/calculate_seek_position_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/download_slide_from_cdn_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/download_track_from_cdn_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/load_daily_schedule_use_case.dart';
import 'package:soloveiko_media_player/domain/usecase/within_working_hours_use_case.dart';
import 'package:timezone/timezone.dart' as tz;

class GetCurrentTrackUseCase {
  GetCurrentTrackUseCase(
      this._localConfigurationRepository,
      this._playingTracksService,
      this._loadDailyScheduleUseCase,
      this._calculateSeekPositionUseCase,
      this._downloadTrackFromCdnUseCase,
      this._localTracksRepository,
      this._buildMediaFilenameUseCase,
      this._withinWorkingHoursUseCase,
      this._downloadSlideFromCdnUseCase,
      this._localSlidesRepository,
      );

  final LocalConfigurationRepository _localConfigurationRepository;
  final PlayingTracksService _playingTracksService;
  final LoadDailyScheduleUseCase _loadDailyScheduleUseCase;
  final CalculateSeekPositionUseCase _calculateSeekPositionUseCase;
  final DownloadTrackFromCdnUseCase _downloadTrackFromCdnUseCase;
  final LocalTracksRepository _localTracksRepository;
  final BuildMediaFilenameUseCase _buildMediaFilenameUseCase;
  final WithinWorkingHoursUseCase _withinWorkingHoursUseCase;
  final DownloadSlideFromCdnUseCase _downloadSlideFromCdnUseCase;
  final LocalSlidesRepository _localSlidesRepository;

  bool _isInitialized = false;

  Future<File?> getLocalTrackFile(String fileName) async {
    return await _localTracksRepository.getTrackFromLocalStorage(fileName);
  }
  void Function(TrackStatus)? _onTrackChanged;

  void setTrackChangedCallback(void Function(TrackStatus) callback) {
    _onTrackChanged = callback;
  }

  void _notifyTrackChanged(TrackStatus status) {
    _onTrackChanged?.call(status);
  }

  Future<TrackStatus> startPeriodicWork() async {
    try {
      if (!await _withinWorkingHoursUseCase.isWithinWorkingHours()) {
        LogService.logInfo(LogTags.getCurrentTrackUseCase, "startPeriodicWork", "Out of working hours");
        final status = const TrackOutOfSchedule();
        _notifyTrackChanged(status);
        _playingTracksService.timerDispose();
        return status;
      }

      final trackResult = await determineCurrentTrack();
      if (trackResult == null) {
        LogService.logWarning(LogTags.getCurrentTrackUseCase, "startPeriodicWork", "Track not found");
        final status = const TrackNotFound();
        _notifyTrackChanged(status);
        return status;
      }

      final playingTrack = await _getTrack(trackResult);

      if (playingTrack == null) {
        final status = TrackError('Failed to prepare track');
        _notifyTrackChanged(status);
        return status;
      }

      _handleInitialization(playingTrack);

      final status = TrackPlaying(playingTrack);
      _notifyTrackChanged(status);
      return status;

    } catch (e, stackTrace) {
      LogService.logError(LogTags.getCurrentTrackUseCase, "startPeriodicWork", "StartPeriodicWork error: $e", stackTrace);
      final status = TrackError(e);
      _notifyTrackChanged(status);
      return status;
    } finally {
      await _startTimerToNextTrack();
    }
  }

  Future<void> _fetchNextTrack() async {
    try {
      File? file;
      final isWithinWorkingHours = await _withinWorkingHoursUseCase.isWithinWorkingHours();
      if (!isWithinWorkingHours) {
        LogService.logInfo(LogTags.getCurrentTrackUseCase, "_fetchNextTrack", "Out of working hours");
        _notifyTrackChanged(const TrackOutOfSchedule());
        return;
      }

      final trackResult = await determineCurrentTrack();
      if (trackResult == null) {
        _notifyTrackChanged(const TrackNotFound());
        return;
      }

      final fileType = FileTypeX.fromString(trackResult.track.type);
      if (fileType == FileType.video || fileType == FileType.audio) {
        final originalFileName = trackResult.track.filename;
        final modifiedFileName = await _buildMediaFilenameUseCase
            .buildFilename(trackResult.track.filename);
        file = await getTrackFile(modifiedFileName, originalFileName);
      } else {
        file = await getSlideFile(trackResult);
      }

      if (file == null) {
        LogService.logWarning(LogTags.getCurrentTrackUseCase, "_fetchNextTrack", "Failed to download media file");
        _notifyTrackChanged(TrackError("Failed to download media file"));
        return;
      }

      final queueInfo = await _getQueueInfo();
      if (queueInfo == null) return;

      final seekPosition = await _getSeekPosition();
      final playingTrack = PlayingMediaModel(
          track: trackResult.track,
          file: file,
          seekPosition: seekPosition,
          tag: queueInfo.tag
      );

      _notifyTrackChanged(TrackPlaying(playingTrack));

    } catch (e, stackTrace) {
      LogService.logError(LogTags.getCurrentTrackUseCase, "_fetchNextTrack", "Media fetch error", e, stackTrace);
      _notifyTrackChanged(TrackError(e));
    } finally {
      await _startTimerToNextTrack();
    }
  }

  Future<File?> getSlideFile(CurrentTrackModel trackResult) async {
    File? file = await _localSlidesRepository.getSlideLocally(trackResult.track.filename);
    if (file == null) {
      final slideContent = await _downloadSlideFromCdnUseCase.downloadSlideFile(trackResult.track.filename);
      if (slideContent?.data == null) {
        return null;
      }
      await _localSlidesRepository.saveSlideLocally(slideContent!.data, trackResult.track.filename);
      file = await _localSlidesRepository.getSlideLocally(trackResult.track.filename);
      if (file == null) {
        return null;
      }
    }
    return file;
  }

  Future<PlayingMediaModel?> _getTrack(CurrentTrackModel trackResult) async {
    File? file;
    final fileType = FileTypeX.fromString(trackResult.track.type);
    if (fileType == FileType.video || fileType == FileType.audio) {
      final originalFileName = trackResult.track.filename;
      final modifiedFileName = await _buildMediaFilenameUseCase
          .buildFilename(trackResult.track.filename);
      file = await getTrackFile(modifiedFileName, originalFileName);
    } else {
      file = await getSlideFile(trackResult);
    }

    if (file == null) {
      LogService.logWarning(LogTags.getCurrentTrackUseCase, "_getTrack", "Failed to download track from CDN");
      _notifyTrackChanged(TrackError("Failed to download track"));
      return null;
    }

    final playingTrack = await _createPlayingTrackModel(trackResult, file);
    _notifyTrackChanged(TrackPlaying(playingTrack));
    return playingTrack;
  }

  Future<void> _startTimerToNextTrack() async {
    final schedule = await _loadDailyScheduleUseCase();
    if (schedule == null) return;

    final scheduleStartTime = getScheduleStartTimeInKyiv(schedule);
    final currentTime = _getCurrentTimeInKyiv();

    final currentIndex = _findCurrentTrackIndex(schedule, scheduleStartTime, currentTime);
    
    if (currentIndex >= schedule.queue.length - 1) {
      return;
    }

    final duration = _calculateDurationToNextTrack(
      scheduleStartTime: scheduleStartTime,
      queue: schedule.queue,
      currentTime: currentTime,
    );

    final timerDuration = duration > Duration.zero 
        ? duration 
        : const Duration(milliseconds: 50);

    _playingTracksService.startSingleTimer(timerDuration, _fetchNextTrack);
  }

  Future<File?> getTrackFile(String modifiedFileName, String originalFileName) async {
    File? file = await getLocalTrackFile(modifiedFileName);
    file ??= await _downloadTrackFromCdnUseCase
        .downloadTrackFile(modifiedFileName);
    file ??= await getLocalTrackFile(originalFileName);
    file ??= await _downloadTrackFromCdnUseCase
        .downloadTrackFile(originalFileName);
    return file;
  }

  void _handleInitialization(PlayingMediaModel? playingTrack) {
    if (playingTrack == null) {
      _notifyTrackChanged(TrackError("Playing track is null"));
      return;
    }
    final status = TrackPlaying(playingTrack);

    if (!_isInitialized) {
      _isInitialized = true;
      _notifyTrackChanged(status);
    } else {
      _notifyTrackChanged(status);
    }
  }

  Future<PlayingMediaModel?> _createPlayingTrackModel(CurrentTrackModel trackResult, File file) async {
    final queueInfo = await _getQueueInfo();
    if (queueInfo == null) return null;

    final seekPosition = await _getSeekPosition();

    return PlayingMediaModel(
        track: trackResult.track,
        file: file,
        seekPosition: seekPosition,
        tag: queueInfo.tag
    );
  }

  Future<QueueItemModel?> _getQueueInfo() async {
    final schedule = await _loadDailyScheduleUseCase();
    if (schedule == null) return null;
    final scheduleStartTime = getScheduleStartTimeInKyiv(schedule);
    final currentTime = _getCurrentTimeInKyiv();
    final queueInfo = _getCurrentQueueInfo(schedule, scheduleStartTime, currentTime);
    return queueInfo;
  }

  Future<double> _getSeekPosition() async {
    return await _calculateSeekPositionUseCase.getSeekPosition();
  }

  Future<CurrentTrackModel?> determineCurrentTrack() async {
    try {
      final schedule = await _loadDailyScheduleUseCase();
      if (schedule == null) return null;

      final scheduleStartTime = getScheduleStartTimeInKyiv(schedule);
      final currentTime = _getCurrentTimeInKyiv();
      if (currentTime.isBefore(scheduleStartTime)) {
        return null;
      }

      final queueInfo = _getCurrentQueueInfo(schedule, scheduleStartTime, currentTime);
      if (queueInfo == null) return null;

      final track = schedule.getTrackBySk(queueInfo.trackSk);
      if (track == null) return null;
      return CurrentTrackModel(track: track);
    } catch (e) {
      return null;
    }
  }

  QueueItemModel? _getCurrentQueueInfo(DailySchedule schedule, tz.TZDateTime scheduleStartTime, tz.TZDateTime currentTime) {
    final currentIndex = _findCurrentTrackIndex(schedule, scheduleStartTime, currentTime);
    if (currentIndex == -1) return null;

    final queueItem = schedule.queue[currentIndex];

    return QueueItemModel(
      tag: queueItem.tag,
      trackSk: queueItem.trackSk,
      startTrackTime: queueItem.startTrackTime,
      type: queueItem.type,
      startDeltaSec: queueItem.startDeltaSec,
    );
  }

  tz.TZDateTime getScheduleStartTimeInKyiv(DailySchedule schedule) {
    final scheduleStartUtc = _parseTimeToUtc(schedule.queue[0].startTrackTime);
    final kyiv = tz.getLocation('Europe/Kyiv');
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      kyiv,
      scheduleStartUtc.millisecondsSinceEpoch,
    );
  }

  DateTime _parseTimeToUtc(String timeString) {
    final parts = timeString.split(':');
    if (parts.length < 2) {
      throw FormatException('Invalid time format: $timeString');
    }
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final currentTime = _getCurrentTimeInKyiv();

    return DateTime.utc(currentTime.year, currentTime.month, currentTime.day, hour, minute);
  }

  int _findCurrentTrackIndex(DailySchedule schedule, tz.TZDateTime scheduleStartTime, tz.TZDateTime currentTime) {
    int left = 0;
    int right = schedule.queue.length - 1;
    int result = -1;

    while (left <= right) {
      final mid = (left + right) ~/ 2;
      final trackStartTime = scheduleStartTime.add(
        Duration(
          microseconds: (schedule.queue[mid].startDeltaSec * 1000000).round(),
        ),
      );

      if (trackStartTime.isAfter(currentTime)) {
        right = mid - 1;
      } else {
        result = mid;
        left = mid + 1;
      }
    }
    return result;
  }

  tz.TZDateTime _getCurrentTimeInKyiv() {
    return _localConfigurationRepository.getCurrentTime();
  }

  Duration _calculateDurationToNextTrack({
    required tz.TZDateTime scheduleStartTime,
    required List<QueueItemModel> queue,
    required tz.TZDateTime currentTime,
  }) {
    final currentIndex = _findCurrentTrackIndex(
      DailySchedule(queue: queue, tracks: {}),
      scheduleStartTime,
      currentTime,
    );

    if (queue.isEmpty || currentIndex >= queue.length - 1) {
      return Duration.zero;
    }

    final currentTrackStartDeltaSec = queue[currentIndex].startDeltaSec;
    final nextTrackStartDeltaSec = queue[currentIndex + 1].startDeltaSec;
    final trackDurationSec = nextTrackStartDeltaSec - currentTrackStartDeltaSec;

    final trackDuration = Duration(
      microseconds: (trackDurationSec * 1e6).toInt(),
    );

    final currentTrackStartTime = scheduleStartTime.add(
      Duration(microseconds: (currentTrackStartDeltaSec * 1e6).toInt()),
    );

    final elapsedSinceTrackStart = currentTime.difference(currentTrackStartTime);
    final remainingDuration = trackDuration - elapsedSinceTrackStart;
    
    final result = remainingDuration.isNegative ? Duration.zero : remainingDuration;

    return result;
  }
}

extension ListExtensions<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}