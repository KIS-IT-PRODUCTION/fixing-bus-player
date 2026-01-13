class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlayerViewModel(
        getCurrentTrackUseCase: GetIt.I<GetCurrentTrackUseCase>(),
        getSystemSoundsUseCase: GetIt.I<GetSystemSoundsUseCase>(),
        getVolumeUseCase: GetIt.I<GetVolumeUseCase>(),
        preloadSlidesService: GetIt.I<PreloadSlidesService>(),
      ),
      child: Builder(
        builder: (context) {
          final viewModel = context.read<PlayerViewModel>();
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: viewModel.getTrackBloc),
            ],
            child: PlayerScreenWidget(
              onOutOfSchedule: () {
                Navigator.pushReplacementNamed(context, AppRoute.closedScreen.name);
              },
            ),
          );
        },
      ),
    );
  }
}

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
            return Container(
              color: Colors.black,
              child: _buildContent(context, state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, GetRecentTrackState state) {
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
  }

  Widget _buildLoadingState() => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );

  Widget _buildErrorState() => const Center(
        child: Icon(Icons.error_outline, color: Colors.red, size: 64),
      );

  Widget _buildTrackState(BuildContext context, RecentTrackSuccess state) {
    final track = state.currentTrack;
    final file = track?.file;
    final viewModel = context.read<PlayerViewModel>();
    
    if (file == null) {
      return const Center(child: Text('No file', style: TextStyle(color: Colors.white)));
    }
    
    final image = viewModel.preloadSlidesService.getDecodedImage(file.path);
    final fileType = FileTypeX.fromString(track?.track.type);
    
    final rawController = context.read<PlayerViewModel>().scheduleTrackPlayerService.videoController;
    final activeController = (fileType == FileType.video) ? rawController : null;
    
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Colors.black),
        ),

        _buildMediaByType(
          fileType: fileType,
          file: file,
          controller: activeController,
          slideImage: image,
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black54],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoText('Filename: ${file.path.split('/').last}'),
                _buildInfoText('Title: ${track?.track.title ?? '-'}'),
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

    if (fileType == FileType.video && controller != null) {
      return ListenableBuilder(
        listenable: service,
        builder: (context, child) {
          final isChanging = service.isChangingTrack;
          
          return Stack(
            fit: StackFit.expand,
            children: [
              MediaPlayerWrapper(
                key: const ValueKey('video_player'),
                controller: controller,
              ),
              if (isChanging)
                Container(
                  key: const ValueKey('black_curtain'),
                  color: Colors.black, 
                ),
            ],
          );
        },
      );
    }

    if (fileType == FileType.slide) {
      return Container(
        key: ValueKey('slide_container_${file?.path}'),
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: (slideImage != null)
            ? RawImage(
                image: slideImage,
                fit: BoxFit.contain,
              )
            : Image.asset('assets/no_image.jpg', fit: BoxFit.contain),
      );
    }
          
    if (fileType == FileType.audio) {
      return _AudioPlaceholder(controller: controller);
    }

    return const SizedBox.shrink();
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
    return Stack(
      alignment: Alignment.center,
      children: [
        const Center(
          child: Icon(Icons.music_note, size: 120, color: Colors.white),
        ),
        if (controller != null)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Video(controller: controller),
          ),
      ],
    );
  }
}