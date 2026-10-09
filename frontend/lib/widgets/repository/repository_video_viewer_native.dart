import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> openRepositoryVideo({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required VoidCallback onReady,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) =>
        _VideoScreen(bytes: bytes, fileName: fileName, onReady: onReady),
  ),
);

class _VideoScreen extends StatefulWidget {
  const _VideoScreen({
    required this.bytes,
    required this.fileName,
    required this.onReady,
  });
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onReady;
  @override
  State<_VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<_VideoScreen> {
  VideoPlayerController? _controller;
  Directory? _directory;
  File? _file;
  late Future<void> _initialization;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _initialization = _load();
  }

  Future<void> _load() async {
    try {
      _directory = await (await getTemporaryDirectory()).createTemp(
        'defensys_video_',
      );
      final extension = widget.fileName
          .split('.')
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      _file = File('${_directory!.path}/preview.$extension');
      await _file!.writeAsBytes(widget.bytes);
      _controller = VideoPlayerController.file(_file!);
      await _controller!.initialize();
      if (mounted) {
        widget.onReady();
        setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _cleanUp() async {
    await _initialization;
    await _controller?.dispose();
    if (_file != null && await _file!.exists()) await _file!.delete();
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete();
    }
  }

  @override
  void dispose() {
    unawaited(_cleanUp().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Promotional video')),
    body: _failed
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(25),
              child: Text(
                'This video could not be played. The file format may not be supported on this device.',
              ),
            ),
          )
        : _controller?.value.isInitialized != true
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller!,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: value.aspectRatio > 0
                        ? value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(_controller!),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: () => value.isPlaying
                            ? _controller!.pause()
                            : _controller!.play(),
                      ),
                      Expanded(
                        child: Slider(
                          value: value.position.inMilliseconds.toDouble().clamp(
                            0,
                            value.duration.inMilliseconds.toDouble(),
                          ),
                          max: value.duration.inMilliseconds.toDouble().clamp(
                            1,
                            double.infinity,
                          ),
                          onChanged: (position) => _controller!.seekTo(
                            Duration(milliseconds: position.round()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );
}
