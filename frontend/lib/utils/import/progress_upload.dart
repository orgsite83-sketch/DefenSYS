import 'dart:async';
import 'package:http/http.dart' as http;

/// Subclass of http.MultipartRequest that intercepts the body stream to report progress.
class MultipartRequestWithProgress extends http.MultipartRequest {
  final void Function(int bytesSent, int totalBytes) onProgress;

  MultipartRequestWithProgress(
    super.method,
    super.url, {
    required this.onProgress,
  });

  @override
  http.ByteStream finalize() {
    // Replace files with a version that chunks the stream.
    // This prevents http.MultipartFile.fromBytes from sending the entire file
    // as a single massive chunk, which triggers 100% progress instantly.
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final originalStream = file.finalize();
      final chunkedStream = _chunkStream(originalStream, 32768); // 32KB chunks
      files[i] = http.MultipartFile(
        file.field,
        chunkedStream,
        file.length,
        filename: file.filename,
        contentType: file.contentType,
      );
    }

    final byteStream = super.finalize();
    final totalLength = contentLength;
    int bytesSent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        bytesSent += data.length;
        onProgress(bytesSent, totalLength);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }

  Stream<List<int>> _chunkStream(Stream<List<int>> source, int chunkSize) {
    late StreamSubscription<List<int>> subscription;
    final controller = StreamController<List<int>>(
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () => subscription.cancel(),
    );

    List<int> buffer = [];

    controller.onListen = () {
      subscription = source.listen(
        (data) {
          if (buffer.isEmpty && data.length <= chunkSize) {
            controller.add(data);
            return;
          }

          buffer.addAll(data);
          int offset = 0;
          while (buffer.length - offset >= chunkSize) {
            controller.add(buffer.sublist(offset, offset + chunkSize));
            offset += chunkSize;
          }
          if (offset > 0) {
            buffer = buffer.sublist(offset);
          }
        },
        onError: controller.addError,
        onDone: () {
          if (buffer.isNotEmpty) {
            controller.add(buffer);
          }
          controller.close();
        },
        cancelOnError: true,
      );
    };

    return controller.stream;
  }
}

