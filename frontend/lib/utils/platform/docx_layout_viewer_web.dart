// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/defensys_tokens.dart';
import 'universal_file_viewer_widgets.dart';

@JS()
extension type _BrowserMessage._(JSObject _) implements JSObject {
  external JSAny? get source;
}

@JS()
extension type _BrowserFrame._(JSObject _) implements JSObject {
  external JSAny? get contentWindow;
}

/// Renders the original DOCX layout locally in an isolated browser frame.
/// The shared text/table viewer remains the fallback for unreadable documents.
class DocxLayoutViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const DocxLayoutViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  State<DocxLayoutViewer> createState() => _DocxLayoutViewerState();
}

class _DocxLayoutViewerState extends State<DocxLayoutViewer> {
  static int _nextId = 0;
  late final String _channel;
  late final html.IFrameElement _frame;
  StreamSubscription<html.MessageEvent>? _messages;
  Timer? _timeout;
  bool _ready = false;
  bool _rendered = false;
  bool _failed = false;
  int _pages = 0;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _channel =
        'docx-layout-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    _frame = html.IFrameElement()
      ..title = 'Preview of ${widget.fileName}'
      // Omit allow-same-origin: document content cannot access the app/session.
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..src = Uri.parse(
        html.document.baseUri ?? Uri.base.toString(),
      ).resolve('docx_viewer/index.html#$_channel').toString();
    _messages = html.window.onMessage.listen(_onMessage);
    final frame = _frame;
    ui_web.platformViewRegistry.registerViewFactory(_channel, (_) => frame);
    _timeout = Timer(const Duration(seconds: 30), _fail);
  }

  void _send(String type, [Map<String, Object?> extra = const {}]) {
    _frame.contentWindow?.postMessage({
      'channel': _channel,
      'type': type,
      ...extra,
    }, '*');
  }

  void _onMessage(html.MessageEvent event) {
    if (!mounted ||
        _failed ||
        !_fromFrame(event) ||
        event.origin != 'null' ||
        event.data is! String) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(event.data as String);
    } on FormatException {
      return;
    }
    if (decoded is! Map || decoded['channel'] != _channel) return;
    switch (decoded['type']) {
      case 'ready':
        if (_ready) return;
        _ready = true;
        _send('render', {
          'blob': html.Blob([widget.bytes]),
          'dark': DefensysTokens.isDark(context),
        });
      case 'layout':
        final pages = decoded['pages'];
        final scale = decoded['scale'];
        if (pages is! int || scale is! num || !scale.isFinite) return;
        setState(() {
          _pages = pages;
          _scale = scale.toDouble();
        });
      case 'rendered':
        _timeout?.cancel();
        setState(() => _rendered = true);
      case 'error':
        _fail();
      case 'close':
        Navigator.of(context).maybePop();
    }
  }

  bool _fromFrame(html.MessageEvent event) {
    // dart:html creates fresh wrappers for cross-origin Window objects, so
    // comparing its source/contentWindow getters rejects genuine messages.
    // Compare the underlying browser WindowProxy identities instead.
    return identical(
      _BrowserMessage._(event as JSObject).source,
      _BrowserFrame._(_frame as JSObject).contentWindow,
    );
  }

  void _fail() {
    if (!mounted || _failed) return;
    _timeout?.cancel();
    _frame.src = 'about:blank';
    _frame.remove();
    setState(() => _failed = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) _send('theme', {'dark': DefensysTokens.isDark(context)});
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _messages?.cancel();
    _frame.src = 'about:blank';
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Document layout could not be displayed. Showing a simplified '
              'preview; download to view the original in Word.',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
          Expanded(
            child: UniversalDocxViewer(
              bytes: widget.bytes,
              fileName: widget.fileName,
              onDownload: widget.onDownload,
              onOpenInNewTab: widget.onOpenInNewTab,
              unavailablePreview: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 40,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No readable preview is available for this document.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: widget.onDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download original document'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            border: Border(
              bottom: BorderSide(color: DefensysTokens.borderOf(context)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Fonts and pagination may vary from Microsoft Word.',
                  child: Text(
                    _rendered
                        ? '$_pages ${_pages == 1 ? 'page' : 'pages'} • Document layout'
                        : 'Preparing document layout…',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: _rendered
                    ? () => _send('zoom', {'scale': _scale / 1.2})
                    : null,
                icon: const Icon(Icons.remove_rounded, size: 17),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
              ),
              Text(
                '${(_scale * 100).round()}%',
                style: const TextStyle(fontSize: 11),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: _rendered
                    ? () => _send('zoom', {'scale': _scale * 1.2})
                    : null,
                icon: const Icon(Icons.add_rounded, size: 17),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
              ),
              TextButton.icon(
                onPressed: _rendered ? () => _send('zoom') : null,
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.maroonTextOf(context),
                ),
                icon: const Icon(Icons.fit_screen_rounded, size: 16),
                label: const Text('Fit width', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: HtmlElementView(viewType: _channel)),
              if (!_rendered)
                Positioned.fill(
                  child: ColoredBox(
                    color: DefensysTokens.backgroundOf(context),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
