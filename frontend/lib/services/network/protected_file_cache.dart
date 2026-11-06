import 'dart:typed_data';

/// Session memory only: never writes authenticated documents to device storage.
/// Least recently used files are evicted before the byte budget is exceeded.
class ProtectedFileCache {
  ProtectedFileCache({
    this.maxBytes = 32 * 1024 * 1024,
    this.maxFileBytes = 16 * 1024 * 1024,
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxBytes;
  final int maxFileBytes;
  final Duration ttl;
  final DateTime Function() _now;
  final _files = <String, ({Uint8List bytes, DateTime expires})>{};
  int _size = 0;

  Uint8List? get(String key) {
    final file = _files.remove(key);
    if (file == null) return null;
    if (!_now().isBefore(file.expires)) {
      _size -= file.bytes.length;
      return null;
    }
    _files[key] = file;
    return file.bytes;
  }

  void put(String key, Uint8List bytes) {
    final previous = _files.remove(key);
    if (previous != null) _size -= previous.bytes.length;
    if (bytes.isEmpty ||
        bytes.length > maxFileBytes ||
        bytes.length > maxBytes) {
      return;
    }
    final now = _now();
    for (final key in _files.keys.toList()) {
      if (!now.isBefore(_files[key]!.expires)) _remove(key);
    }
    while (_size + bytes.length > maxBytes && _files.isNotEmpty) {
      _remove(_files.keys.first);
    }
    _files[key] = (bytes: bytes, expires: now.add(ttl));
    _size += bytes.length;
  }

  void _remove(String key) {
    _size -= _files.remove(key)!.bytes.length;
  }

  void clear() {
    _files.clear();
    _size = 0;
  }
}
