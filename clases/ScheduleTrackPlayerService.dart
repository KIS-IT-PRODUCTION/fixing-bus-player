import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_service.dart';
import 'package:soloveiko_media_player/domain/service/log_service/log_tags.dart';
import 'package:soloveiko_media_player/domain/service/playback_logger_service/playback_logger_service.dart';

class ScheduleTrackPlayerService with ChangeNotifier {
  ScheduleTrackPlayerService() {
    _videoController = VideoController(_player);
    _player.setPlaylistMode(PlaylistMode.none);
    _initializePlaybackLoggerService();
  }

  final Player _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 32 * 1024 * 1024, 
    ),
  );
  late final VideoController _videoController;
  late final PlaybackLoggerService _playbackLoggerService;

  File? get currentTrack => _currentTrack;
  VideoController get videoController => _videoController;

  bool get isChangingTrack => _isChangingTrack;

  File? _currentTrack;
  bool _isChangingTrack = false;
  StreamSubscription? _completedSubscription;

  Future<void> addTrackToPlaylist(File file) async {
    try {
      _currentTrack = file;
      final media = Media(file.path);

      await _player.open(media, play: false);
      
      await _player.play();
      
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "addTrackToPlaylist", "Error opening track", e, stackTrace);
    }
  }

  _initializePlaybackLoggerService() async {
    _playbackLoggerService = PlaybackLoggerService();
    _playbackLoggerService.initPlaybackLoggerService();
  }

  Future<void> pauseForSlide() async {
    await stopAndClear();
  }

  Future<void> stopAndClear() async {
    try {
      await _player.stop();
    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "stopAndClear", "Error stopping player", e, stackTrace);
    }
  }

  Future<void> playTrack(File file, Duration? seekPosition, String? tag, String? sk, String? playlistSk, String? filename, String? type, String? title, String? artist, String? campaignSk) async {
    if (_isChangingTrack) {
      return;
    }

    _isChangingTrack = true;
    notifyListeners();

    try {
      await _player.play();

      if (seekPosition != null && seekPosition > Duration.zero) {
        await _player.seek(seekPosition);
      }

      _playbackLoggerService.logTrack(tag: tag, sk: sk, playlistSk: playlistSk, filename: filename, title: title, artist: artist, type: type, campaignSk: campaignSk);

    } catch (e, stackTrace) {
      LogService.logError(LogTags.scheduleTrackPlayerService, "playTrack", "Error in playTrack", e, stackTrace);
    } finally {
      _isChangingTrack = false;
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) {
    return _player.setVolume(volume);
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
