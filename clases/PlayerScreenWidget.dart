class PlayerScreenWidget extends StatefulWidget {
  final VoidCallback? onOutOfSchedule;

  const PlayerScreenWidget({super.key, this.onOutOfSchedule});

  @override
  State<PlayerScreenWidget> createState() => _PlayerScreenWidgetState();
}

class _PlayerScreenWidgetState extends State<PlayerScreenWidget> {
  late final PlayerViewModel _viewModel;
  late final GetRecentTrackBloc _getTrackBloc;
  late final GetSystemSoundsBloc _getSystemSoundsBloc;
  late final StreamSubscription _systemSoundsSubscription;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<PlayerViewModel>();
    _getTrackBloc = _viewModel.getTrackBloc;
    _getSystemSoundsBloc = context.read<GetSystemSoundsBloc>();
    _listenToSqsCommands();
  }

  void _listenToSqsCommands() {
    _systemSoundsSubscription = _getSystemSoundsBloc.stream.listen((state) {
      if (state is SystemSoundsCommandExecuting) {
        _viewModel.handleCommand(state.commandType);
      }
    });
  }

  @override
  void dispose() {
    _systemSoundsSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _getTrackBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<GetRecentTrackBloc, GetRecentTrackState>(
            listener: (context, state) {
              if (state is RecentTrackOutOfSchedule) {
                widget.onOutOfSchedule?.call();
              }

              if (state is RecentTrackSuccess && state.currentTrack != null) {
                context.read<PlayerViewModel>().onTrackChanged(state.currentTrack!);
              }
            },
          ),
        ],
        child: BlocBuilder<GetRecentTrackBloc, GetRecentTrackState>(
          builder: (context, state) {
            if (state is RecentTrackLoading) {
              return _buildLoadingState();
            }

            if (state is RecentTrackError) {
              return _buildErrorState();
            }

            if (state is RecentTrackSuccess) {
              return _buildTrackState(context, state);
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
        SizedBox(height: 16),
        Text(
          "Wait a moment...",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    ),
  );

  Widget _buildErrorState() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: Colors.red, size: 64),
        SizedBox(height: 16),
        Text(
          'Error loading track',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    ),
  );

  Widget _buildTrackState(BuildContext context, RecentTrackSuccess state) {
    final track = state.currentTrack;
    final file = track?.file;
    final viewModel = context.read<PlayerViewModel>();
    if (file == null) {
      return const Center(
        child: Text(
          'No file',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    final image = viewModel.preloadSlidesService.getDecodedImage(file.path);
    final fileType = FileTypeX.fromString(track?.track.type);
    final controller = context
        .read<PlayerViewModel>()
        .scheduleTrackPlayerService
        .videoController;
    return Stack(
      children: [
        _buildMediaByType(
          fileType: fileType,
          file: file,
          controller: controller,
          slideImage: image,
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoText('Filename: ${file.path.split('/').last}'),
                _buildInfoText('Artist: ${track?.track.artist ?? '-'}'),
                _buildInfoText('Track: ${track?.track.source ?? '-'}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaByType({
    required FileType fileType,
    File? file,
    VideoController? controller,
    ui.Image? slideImage,
  }) {
    final service = context.read<PlayerViewModel>().scheduleTrackPlayerService;

    switch (fileType) {
      case FileType.video:
        if (controller == null) {
          return const SizedBox.shrink(key: ValueKey('video_empty'));
        }
        
        return ListenableBuilder(
          listenable: service,
          builder: (context, child) {
            // щоб не миготів старий кадр
            if (service.isChangingTrack) {
               return Container(color: Colors.black); 
            }
            return MediaPlayerWrapper(
              key: const ValueKey('video_player'),
              controller: controller,
            );
          },
        );

      case FileType.slide:
        if (slideImage != null && file != null) {
          return RawImage(
            key: const ValueKey('video_surface'),
            image: slideImage,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          );
        }

        return Image.asset(
          'assets/no_image.jpg',
          key: const ValueKey('slide_asset'),
          fit: BoxFit.contain,
        );

      case FileType.audio:
        return _AudioPlaceholder(controller: controller);

      default:
        return const SizedBox.shrink(key: ValueKey('empty'));
    }
  }

  Widget _buildInfoText(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.none,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _AudioPlaceholder extends StatelessWidget {
  final VideoController? controller;

  const _AudioPlaceholder({this.controller});

  @override
  Widget build(BuildContext context) {
    final videoController = controller;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Icon(
            Icons.music_note,
            size: 120,
            color: Colors.white,
          ),
        ),
        if (videoController != null)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Video(controller: videoController),
          ),
      ],
    );
  }
}