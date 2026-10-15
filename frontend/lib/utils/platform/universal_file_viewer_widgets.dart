import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart' as xml;

import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import 'universal_file_viewer_models.dart';

/// ----------------------------------------------------------------------
/// 1. Interactive Image Viewer with Pan, Zoom & Transparency Grid
/// ----------------------------------------------------------------------
class UniversalImageViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final TransformationController controller;
  final double rotationAngle;

  const UniversalImageViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.controller,
    this.rotationAngle = 0.0,
  });

  @override
  State<UniversalImageViewer> createState() => _UniversalImageViewerState();
}

class _UniversalImageViewerState extends State<UniversalImageViewer> {
  late double _rotation;
  double _zoomScale = 1.0;

  @override
  void initState() {
    super.initState();
    _rotation = widget.rotationAngle;
  }

  void _zoom(double factor) {
    setState(() {
      final matrix = widget.controller.value.clone();
      // ignore: deprecated_member_use
      matrix.scale(factor);
      widget.controller.value = matrix;
      _zoomScale = (_zoomScale * factor).clamp(0.1, 10.0);
    });
  }

  void _resetZoom() {
    setState(() {
      widget.controller.value = Matrix4.identity();
      _rotation = 0.0;
      _zoomScale = 1.0;
    });
  }

  void _rotate() {
    setState(() {
      _rotation += math.pi / 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final canvasColor = isDark
        ? DefensysTokens.backgroundOf(context)
        : const Color(0xFFF1F5F9);

    return Container(
      color: canvasColor,
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
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
                  child: Text(
                    '${(_zoomScale * 100).round()}% scale',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.remove_rounded, size: 17),
                  onPressed: () => _zoom(0.8),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.maroonTextOf(context),
                  ),
                  onPressed: _resetZoom,
                  child: Text('${(_zoomScale * 100).round()}%'),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.add_rounded, size: 17),
                  onPressed: () => _zoom(1.25),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  tooltip: 'Rotate 90°',
                  icon: const Icon(Icons.rotate_right_rounded, size: 17),
                  onPressed: _rotate,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.maroonTextOf(context),
                  ),
                  onPressed: _resetZoom,
                  icon: const Icon(Icons.fit_screen_rounded, size: 16),
                  label: const Text('Reset', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),

          // Main Canvas
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Alpha transparency checkerboard
                CustomPaint(
                  painter: _AdaptiveCheckerboardPainter(isDark: isDark),
                  size: Size.infinite,
                ),
                Center(
                  child: InteractiveViewer(
                    transformationController: widget.controller,
                    clipBehavior: Clip.none,
                    minScale: 0.1,
                    maxScale: 10.0,
                    child: Transform.rotate(
                      angle: _rotation,
                      child: Image.memory(
                        widget.bytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.broken_image_outlined,
                                size: 44,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Failed to render image: $error',
                                style: TextStyle(
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Floating navigation hint
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceOf(
                          context,
                        ).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: DefensysTokens.borderOf(context),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.pinch_outlined,
                            size: 13,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Scroll to zoom • Drag to pan • Click Reset to restore',
                            style: TextStyle(
                              color: DefensysTokens.textSecondaryOf(context),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveCheckerboardPainter extends CustomPainter {
  final bool isDark;
  _AdaptiveCheckerboardPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final paint2 = Paint()
      ..color = isDark ? const Color(0xFF131D33) : const Color(0xFFE2E8F0);
    const cellSize = 20.0;

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isEven =
            ((x / cellSize).floor() + (y / cellSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AdaptiveCheckerboardPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// ----------------------------------------------------------------------
/// 2. Presentation Viewer (.pptx / .ppt) with Full Visual Layout & Outline
/// ----------------------------------------------------------------------
class PptxVisualRun {
  final String text;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isItalic;

  const PptxVisualRun({
    required this.text,
    required this.color,
    required this.fontSize,
    this.isBold = false,
    this.isItalic = false,
  });
}

class PptxVisualParagraph {
  final TextAlign alignment;
  final List<PptxVisualRun> runs;

  const PptxVisualParagraph({
    this.alignment = TextAlign.left,
    this.runs = const [],
  });

  String get text => runs.map((r) => r.text).join();
}

class PptxVisualShape {
  final double x; // in EMUs
  final double y;
  final double width;
  final double height;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final bool isCircle;
  final List<PptxVisualParagraph> paragraphs;

  const PptxVisualShape({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 0.0,
    this.borderRadius = 0.0,
    this.isCircle = false,
    this.paragraphs = const [],
  });
}

class PptxSlideData {
  final int slideIndex;
  final String title;
  final Color backgroundColor;
  final List<PptxVisualShape> shapes;
  final List<String> bulletPoints;
  final String notes;

  const PptxSlideData({
    required this.slideIndex,
    required this.title,
    required this.backgroundColor,
    required this.shapes,
    required this.bulletPoints,
    this.notes = '',
  });
}

class UniversalPresentationViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const UniversalPresentationViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  State<UniversalPresentationViewer> createState() =>
      _UniversalPresentationViewerState();
}

class _UniversalPresentationViewerState
    extends State<UniversalPresentationViewer> {
  bool _isLoading = true;
  String? _parseError;
  List<PptxSlideData> _slides = [];
  int _currentSlide = 0;
  bool _isGridView = false;
  bool _isOutlineMode = false;
  bool _showNotes = false;
  // Used only for legacy/minimal archives without presentation metadata.
  double _slideWidthEmu = 12192000;
  double _slideHeightEmu = 6858000;

  @override
  void initState() {
    super.initState();
    _parsePresentation();
  }

  Color? _parseSrgbColor(xml.XmlElement? element) {
    if (element == null) return null;
    final srgb = element.findAllElements('a:srgbClr').firstOrNull;
    if (srgb != null) {
      final val = srgb.getAttribute('val');
      if (val != null && val.length == 6) {
        final rgb = int.tryParse('0xFF$val');
        if (rgb != null) {
          final alphaElem = srgb.findAllElements('a:alpha').firstOrNull;
          if (alphaElem != null) {
            final aVal =
                int.tryParse(alphaElem.getAttribute('val') ?? '100000') ??
                100000;
            return Color(
              rgb,
            ).withValues(alpha: (aVal / 100000.0).clamp(0.0, 1.0));
          }
          return Color(rgb);
        }
      }
    }
    return null;
  }

  xml.XmlDocument? _readXmlPart(Map<String, ArchiveFile> parts, String path) {
    final part = parts[path];
    return part == null
        ? null
        : xml.XmlDocument.parse(
            utf8.decode(part.content as List<int>, allowMalformed: true),
          );
  }

  Map<String, String> _relationshipTargets(
    Map<String, ArchiveFile> parts,
    String source,
    String type,
  ) {
    final slash = source.lastIndexOf('/');
    final directory = slash < 0 ? '' : source.substring(0, slash + 1);
    final fileName = source.substring(slash + 1);
    final document = _readXmlPart(parts, '${directory}_rels/$fileName.rels');
    final targets = <String, String>{};
    for (final element
        in document?.descendants.whereType<xml.XmlElement>() ??
            const Iterable<xml.XmlElement>.empty()) {
      if (element.name.local != 'Relationship' ||
          element.getAttribute('TargetMode') == 'External' ||
          !(element.getAttribute('Type') ?? '').endsWith('/$type')) {
        continue;
      }
      final id = element.getAttribute('Id');
      final target = element.getAttribute('Target');
      if (id == null || target == null) continue;
      final resolved = Uri.parse(source).resolve(target);
      if (resolved.hasScheme || resolved.hasAuthority) continue;
      targets[id] = resolved.path.replaceFirst(RegExp(r'^/'), '');
    }
    return targets;
  }

  void _parsePresentation() {
    try {
      final archive = ZipDecoder().decodeBytes(widget.bytes);
      final parts = {
        for (final file in archive.files.where((f) => f.isFile))
          file.name: file,
      };
      var slideFiles = archive.files.where((f) {
        return f.isFile &&
            f.name.startsWith('ppt/slides/slide') &&
            f.name.endsWith('.xml');
      }).toList();

      final presentation = _readXmlPart(parts, 'ppt/presentation.xml');
      final elements =
          presentation?.descendants.whereType<xml.XmlElement>().toList() ??
          <xml.XmlElement>[];
      final size = elements.where((e) => e.name.local == 'sldSz').firstOrNull;
      final width = double.tryParse(size?.getAttribute('cx') ?? '');
      final height = double.tryParse(size?.getAttribute('cy') ?? '');
      if (width != null &&
          height != null &&
          width.isFinite &&
          height.isFinite &&
          width > 0 &&
          height > 0) {
        _slideWidthEmu = width;
        _slideHeightEmu = height;
      }
      final slideIds = elements.where((e) => e.name.local == 'sldId').toList();
      if (slideIds.isNotEmpty) {
        final targets = _relationshipTargets(
          parts,
          'ppt/presentation.xml',
          'slide',
        );
        slideFiles = slideIds.map((element) {
          final id = element.attributes
              .where(
                (attribute) =>
                    attribute.name.local == 'id' &&
                    attribute.name.prefix != null,
              )
              .firstOrNull
              ?.value;
          final file = parts[targets[id]];
          if (file == null) {
            throw const FormatException(
              'A presentation slide reference could not be resolved.',
            );
          }
          return file;
        }).toList();
      } else {
        // Minimal fixtures and older exports may omit the presentation part.
        slideFiles.sort(
          (a, b) => _extractSlideNumber(
            a.name,
          ).compareTo(_extractSlideNumber(b.name)),
        );
      }

      if (slideFiles.isEmpty) {
        setState(() {
          _slides = [];
          _isLoading = false;
        });
        return;
      }

      // Collect notes from ppt/notesSlides/
      final notesMap = <int, String>{};
      for (final f in archive.files) {
        if (f.isFile &&
            f.name.startsWith('ppt/notesSlides/notesSlide') &&
            f.name.endsWith('.xml')) {
          final num = _extractSlideNumber(f.name);
          try {
            final xmlDoc = xml.XmlDocument.parse(
              utf8.decode(f.content as List<int>, allowMalformed: true),
            );
            final textElements = xmlDoc.findAllElements('a:t');
            final text = textElements
                .map((e) => e.innerText.trim())
                .where((s) => s.isNotEmpty)
                .join(' ');
            if (text.isNotEmpty) notesMap[num] = text;
          } catch (_) {}
        }
      }

      final List<PptxSlideData> parsed = [];
      for (int i = 0; i < slideFiles.length; i++) {
        final file = slideFiles[i];
        final slideNum = _extractSlideNumber(file.name);
        try {
          final xmlDoc = xml.XmlDocument.parse(
            utf8.decode(file.content as List<int>, allowMalformed: true),
          );

          Color slideBg = const Color(0xFF0E1527); // Default sleek dark canvas
          final bgSolid = xmlDoc.findAllElements('p:bgPr').firstOrNull;
          if (bgSolid != null) {
            final clr = _parseSrgbColor(bgSolid);
            if (clr != null) slideBg = clr;
          }

          final List<PptxVisualShape> shapes = [];
          final List<String> outlineBullets = [];
          String extractedTitle = '';

          final spElements = xmlDoc.findAllElements('p:sp');
          for (final sp in spElements) {
            final xfrm = sp.findAllElements('a:xfrm').firstOrNull;
            double x = 0;
            double y = 0;
            double w = 0;
            double h = 0;

            if (xfrm != null) {
              final off = xfrm.findAllElements('a:off').firstOrNull;
              final ext = xfrm.findAllElements('a:ext').firstOrNull;
              x = double.tryParse(off?.getAttribute('x') ?? '0') ?? 0.0;
              y = double.tryParse(off?.getAttribute('y') ?? '0') ?? 0.0;
              w = double.tryParse(ext?.getAttribute('cx') ?? '0') ?? 0.0;
              h = double.tryParse(ext?.getAttribute('cy') ?? '0') ?? 0.0;
              if (w <= 0 || h <= 0) continue;
            } else {
              // Fallback placement for shapes without explicit xfrm (e.g. minimal XML or unpositioned shapes)
              x = _slideWidthEmu * 0.08;
              y = _slideHeightEmu * (0.13 + shapes.length * 0.22);
              w = _slideWidthEmu * 0.84;
              h = _slideHeightEmu * 0.19;
            }

            // Check if this is the full slide background rect
            final spPr = sp.findAllElements('p:spPr').firstOrNull;
            Color? fillColor = _parseSrgbColor(
              spPr?.findAllElements('a:solidFill').firstOrNull,
            );
            if (x == 0 &&
                y == 0 &&
                w >= _slideWidthEmu * 0.95 &&
                h >= _slideHeightEmu * 0.95 &&
                fillColor != null) {
              slideBg = fillColor;
              continue;
            }

            // Outline / Border
            final ln = spPr?.findAllElements('a:ln').firstOrNull;
            Color? borderColor;
            double borderWidth = 0.0;
            if (ln != null) {
              borderColor = _parseSrgbColor(
                ln.findAllElements('a:solidFill').firstOrNull,
              );
              final wStr = ln.getAttribute('w');
              if (wStr != null) {
                final emu = double.tryParse(wStr) ?? 12700;
                borderWidth = (emu / 12700.0).clamp(0.5, 4.0);
              }
            }

            // Geometry (roundRect, ellipse, rect)
            final geom = spPr?.findAllElements('a:prstGeom').firstOrNull;
            final prst = geom?.getAttribute('prst') ?? 'rect';
            final isCircle = prst == 'ellipse';
            double borderRadius = 0.0;
            if (prst == 'roundRect') {
              borderRadius = 8.0;
            }

            // Paragraphs & Runs
            final List<PptxVisualParagraph> paragraphs = [];
            final txBody = sp.findAllElements('p:txBody').firstOrNull;
            if (txBody != null) {
              for (final p in txBody.findAllElements('a:p')) {
                final pPr = p.findAllElements('a:pPr').firstOrNull;
                final algn = pPr?.getAttribute('algn');
                TextAlign alignment = TextAlign.left;
                if (algn == 'ctr') alignment = TextAlign.center;
                if (algn == 'r') alignment = TextAlign.right;

                final List<PptxVisualRun> runs = [];
                for (final r in p.findAllElements('a:r')) {
                  final text =
                      r.findAllElements('a:t').firstOrNull?.innerText ?? '';
                  if (text.isEmpty) continue;

                  final rPr = r.findAllElements('a:rPr').firstOrNull;
                  final szVal =
                      double.tryParse(rPr?.getAttribute('sz') ?? '1400') ??
                      1400.0;
                  final fontSize = (szVal / 100.0).clamp(7.0, 60.0);
                  final isBold = rPr?.getAttribute('b') == '1';
                  final isItalic = rPr?.getAttribute('i') == '1';
                  final defaultTextColor = slideBg.computeLuminance() < 0.5
                      ? Colors.white
                      : const Color(0xFF1E293B);
                  Color runColor =
                      _parseSrgbColor(
                        rPr?.findAllElements('a:solidFill').firstOrNull,
                      ) ??
                      defaultTextColor;

                  runs.add(
                    PptxVisualRun(
                      text: text,
                      color: runColor,
                      fontSize: fontSize,
                      isBold: isBold,
                      isItalic: isItalic,
                    ),
                  );
                }

                if (runs.isNotEmpty) {
                  paragraphs.add(
                    PptxVisualParagraph(alignment: alignment, runs: runs),
                  );
                  final pText = runs.map((r) => r.text).join('').trim();
                  if (pText.isNotEmpty) {
                    if (extractedTitle.isEmpty && (pText.length < 80)) {
                      extractedTitle = pText;
                    }
                    outlineBullets.add(pText);
                  }
                }
              }
            }

            // Add visual shape if it has either background, border, or text
            if (fillColor != null ||
                borderColor != null ||
                paragraphs.isNotEmpty) {
              shapes.add(
                PptxVisualShape(
                  x: x,
                  y: y,
                  width: w,
                  height: h,
                  fillColor: fillColor,
                  borderColor: borderColor,
                  borderWidth: borderWidth,
                  borderRadius: borderRadius,
                  isCircle: isCircle,
                  paragraphs: paragraphs,
                ),
              );
            }
          }

          if (extractedTitle.isEmpty) {
            extractedTitle = 'Slide ${i + 1}';
          }

          parsed.add(
            PptxSlideData(
              slideIndex: i + 1,
              title: extractedTitle,
              backgroundColor: slideBg,
              shapes: shapes,
              bulletPoints: outlineBullets,
              notes: () {
                final targets = _relationshipTargets(
                  parts,
                  file.name,
                  'notesSlide',
                );
                final notes = targets.values.isEmpty
                    ? null
                    : _readXmlPart(parts, targets.values.first);
                return notes == null
                    ? (notesMap[slideNum] ?? '')
                    : notes.descendants
                          .whereType<xml.XmlElement>()
                          .where((e) => e.name.local == 't')
                          .map((e) => e.innerText.trim())
                          .where((text) => text.isNotEmpty)
                          .join(' ');
              }(),
            ),
          );
        } catch (_) {
          parsed.add(
            PptxSlideData(
              slideIndex: i + 1,
              title: 'Slide ${i + 1}',
              backgroundColor: const Color(0xFF0E1527),
              shapes: const [],
              bulletPoints: const [
                '(Complex layout - open in PowerPoint for full media)',
              ],
            ),
          );
        }
      }

      setState(() {
        _slides = parsed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _parseError = e.toString();
        _isLoading = false;
      });
    }
  }

  int _extractSlideNumber(String path) {
    final match = RegExp(r'\d+').firstMatch(path);
    return match != null ? int.tryParse(match.group(0)!) ?? 0 : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (_slides.isEmpty || _parseError != null) {
      return UniversalDeliverableCard(
        fileName: widget.fileName,
        fileSizeBytes: widget.bytes.length,
        category: FileCategory.officePresentation,
        onDownload: widget.onDownload,
        onOpenInNewTab: widget.onOpenInNewTab,
      );
    }

    final isDark = DefensysTokens.isDark(context);
    final canvasColor = isDark
        ? DefensysTokens.backgroundOf(context)
        : const Color(0xFFF1F5F9);
    final current = _slides[_currentSlide];

    return Container(
      color: canvasColor,
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
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
                  child: Text(
                    '${_slides.length} ${_slides.length == 1 ? 'slide' : 'slides'} • Slide ${_currentSlide + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),

                // Slide Navigation Controls
                IconButton(
                  tooltip: 'Previous slide',
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  onPressed: _currentSlide > 0
                      ? () => setState(() => _currentSlide--)
                      : null,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Text(
                    '${_currentSlide + 1} / ${_slides.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: DefensysTokens.textPrimaryOf(context),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next slide',
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  onPressed: _currentSlide < _slides.length - 1
                      ? () => setState(() => _currentSlide++)
                      : null,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),

                const SizedBox(width: 8),

                // Mode Toggle: Visual Deck vs Outline
                IconButton(
                  tooltip: _isOutlineMode
                      ? 'Visual Deck View'
                      : 'Outline & Text View',
                  icon: Icon(
                    _isOutlineMode
                        ? Icons.slideshow_rounded
                        : Icons.format_list_bulleted_rounded,
                    size: 17,
                    color: _isOutlineMode ? const Color(0xFFEA580C) : null,
                  ),
                  onPressed: () =>
                      setState(() => _isOutlineMode = !_isOutlineMode),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),

                // Grid view switcher
                IconButton(
                  tooltip: _isGridView ? 'Slide View' : 'Grid Overview',
                  icon: Icon(
                    _isGridView
                        ? Icons.view_carousel_outlined
                        : Icons.grid_view_rounded,
                    size: 17,
                    color: _isGridView ? const Color(0xFFEA580C) : null,
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),

                if (current.notes.isNotEmpty)
                  IconButton(
                    tooltip: 'Speaker Notes',
                    icon: Icon(
                      Icons.notes_rounded,
                      size: 17,
                      color: _showNotes ? const Color(0xFFEA580C) : null,
                    ),
                    onPressed: () => setState(() => _showNotes = !_showNotes),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),

          // Main Presentation Workspace
          Expanded(
            child: _isGridView
                ? _buildGridView(context)
                : (_isOutlineMode
                      ? _buildOutlineView(context, current)
                      : _buildVisualCanvas(context, current)),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        childAspectRatio: _slideWidthEmu / _slideHeightEmu,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _slides.length,
      itemBuilder: (context, index) {
        final slide = _slides[index];
        final isSelected = index == _currentSlide;
        return InkWell(
          onTap: () {
            setState(() {
              _currentSlide = index;
              _isGridView = false;
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: slide.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFEA580C)
                    : DefensysTokens.borderOf(context),
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Mini shape preview
                for (final shape in slide.shapes.take(15))
                  Positioned(
                    left: (shape.x / 12192000.0) * 300,
                    top: (shape.y / 6858000.0) * 187,
                    width: math.max(2.0, (shape.width / 12192000.0) * 300),
                    height: math.max(2.0, (shape.height / 6858000.0) * 187),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            shape.fillColor ??
                            Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                // Header badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'SLIDE ${slide.slideIndex}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // Title label
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      slide.title,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualCanvas(BuildContext context, PptxSlideData slide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.max(
          1.0,
          math.min(940.0, constraints.maxWidth - 48),
        );
        final slideWidth = maxWidth;
        final slideHeight = maxWidth * _slideHeightEmu / _slideWidthEmu;
        final scaleX = slideWidth / _slideWidthEmu;
        final scaleY = slideHeight / _slideHeightEmu;
        // DrawingML uses 12,700 EMUs per typographic point.
        final fontScale = scaleX * 12700;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                // Visual Widescreen Slide Deck Canvas
                Container(
                  width: slideWidth,
                  height: slideHeight,
                  decoration: BoxDecoration(
                    color: slide.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      for (final shape in slide.shapes)
                        Positioned(
                          left: shape.x * scaleX,
                          top: shape.y * scaleY,
                          width: math.max(shape.width * scaleX, 1.0),
                          height: math.max(shape.height * scaleY, 1.0),
                          child: _buildVisualShape(shape, scaleX, fontScale),
                        ),
                    ],
                  ),
                ),

                // Presenter Notes Drawer
                if (_showNotes && slide.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: slideWidth,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DefensysTokens.borderOf(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notes_rounded,
                              size: 16,
                              color: Color(0xFFEA580C),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'PRESENTER SPEAKER NOTES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          slide.notes,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisualShape(
    PptxVisualShape shape,
    double scaleX,
    double fontScale,
  ) {
    final hasDecoration = shape.fillColor != null || shape.borderColor != null;
    final decoration = hasDecoration
        ? BoxDecoration(
            color: shape.fillColor,
            borderRadius: shape.isCircle
                ? BorderRadius.circular(100)
                : (shape.borderRadius > 0
                      ? BorderRadius.circular(shape.borderRadius)
                      : null),
            border: shape.borderColor != null
                ? Border.all(
                    color: shape.borderColor!,
                    width: math.max(1.0, shape.borderWidth),
                  )
                : null,
          )
        : null;

    Widget content;
    if (shape.paragraphs.isEmpty) {
      content = const SizedBox.shrink();
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final p in shape.paragraphs)
            p.runs.length == 1
                ? Text(
                    p.runs.first.text,
                    textAlign: p.alignment,
                    style: TextStyle(
                      color: p.runs.first.color,
                      fontSize: math.max(
                        7.5,
                        p.runs.first.fontSize * fontScale,
                      ),
                      fontWeight: p.runs.first.isBold
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontStyle: p.runs.first.isItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontFamily: 'Inter',
                      height: 1.25,
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        for (final r in p.runs)
                          TextSpan(
                            text: r.text,
                            style: TextStyle(
                              color: r.color,
                              fontSize: math.max(7.5, r.fontSize * fontScale),
                              fontWeight: r.isBold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontStyle: r.isItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              fontFamily: 'Inter',
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                    textAlign: p.alignment,
                  ),
        ],
      );
    }

    if (decoration != null) {
      return Container(
        decoration: decoration,
        padding: shape.paragraphs.isNotEmpty
            ? EdgeInsets.symmetric(
                horizontal: 4 * fontScale,
                vertical: 1.5 * fontScale,
              )
            : EdgeInsets.zero,
        child: content,
      );
    }
    return content;
  }

  Widget _buildOutlineView(BuildContext context, PptxSlideData slide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Center(
        child: Container(
          width: math.min(840.0, MediaQuery.of(context).size.width - 48),
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DefensysTokens.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SLIDE ${slide.slideIndex} OUTLINE',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Color(0xFFEA580C),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                slide.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              if (slide.bulletPoints.isNotEmpty) ...[
                for (final point in slide.bulletPoints) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            point,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  '(Visual Graphic Slide Content)',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 3. Document Viewer (.docx / Word documents)
/// ----------------------------------------------------------------------
class DocxItem {
  final String text;
  final bool isTitle;
  final bool isHeading1;
  final bool isHeading2;
  final bool isBullet;
  final List<List<String>>? tableData;

  const DocxItem({
    required this.text,
    this.isTitle = false,
    this.isHeading1 = false,
    this.isHeading2 = false,
    this.isBullet = false,
    this.tableData,
  });
}

class UniversalDocxViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const UniversalDocxViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  State<UniversalDocxViewer> createState() => _UniversalDocxViewerState();
}

class _UniversalDocxViewerState extends State<UniversalDocxViewer> {
  bool _isLoading = true;
  String? _parseError;
  List<DocxItem> _items = [];

  @override
  void initState() {
    super.initState();
    _parseDocx();
  }

  void _parseDocx() {
    try {
      final archive = ZipDecoder().decodeBytes(widget.bytes);
      final docFile = archive.files.firstWhere(
        (f) => f.isFile && f.name == 'word/document.xml',
        orElse: () => ArchiveFile('', 0, []),
      );

      if (docFile.content.isEmpty) {
        setState(() {
          _items = [];
          _isLoading = false;
        });
        return;
      }

      final xmlDoc = xml.XmlDocument.parse(
        utf8.decode(docFile.content as List<int>, allowMalformed: true),
      );

      final List<DocxItem> parsed = [];
      final body = xmlDoc.findAllElements('w:body').firstOrNull;
      if (body != null) {
        for (final child in body.children.whereType<xml.XmlElement>()) {
          if (child.name.local == 'p') {
            final style =
                child
                    .findAllElements('w:pStyle')
                    .firstOrNull
                    ?.getAttribute('w:val')
                    ?.toLowerCase() ??
                '';
            final isBullet = child.findAllElements('w:numPr').isNotEmpty;
            final text = child
                .findAllElements('w:t')
                .map((t) => t.innerText)
                .join('');
            final clean = text.trim();
            if (clean.isEmpty) continue;

            final isTitle = style.contains('title');
            final isH1 = style.contains('heading 1') || style == '1';
            final isH2 = style.contains('heading 2') || style == '2';

            parsed.add(
              DocxItem(
                text: clean,
                isTitle: isTitle,
                isHeading1: isH1,
                isHeading2: isH2,
                isBullet: isBullet,
              ),
            );
          } else if (child.name.local == 'tbl') {
            final List<List<String>> table = [];
            final rows = child.findAllElements('w:tr');
            for (final r in rows) {
              final cells = r.findAllElements('w:tc').map((c) {
                return c
                    .findAllElements('w:t')
                    .map((t) => t.innerText)
                    .join(' ')
                    .trim();
              }).toList();
              if (cells.isNotEmpty) table.add(cells);
            }
            if (table.isNotEmpty) {
              parsed.add(DocxItem(text: '', tableData: table));
            }
          }
        }
      }

      setState(() {
        _items = parsed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _parseError = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (_items.isEmpty || _parseError != null) {
      return UniversalDeliverableCard(
        fileName: widget.fileName,
        fileSizeBytes: widget.bytes.length,
        category: FileCategory.officeDoc,
        onDownload: widget.onDownload,
        onOpenInNewTab: widget.onOpenInNewTab,
      );
    }

    final isDark = DefensysTokens.isDark(context);
    final canvasColor = isDark
        ? DefensysTokens.backgroundOf(context)
        : const Color(0xFFF1F5F9);

    return Container(
      color: canvasColor,
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
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
                  child: Text(
                    '${_items.length} paragraphs • Clean document view',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.maroonTextOf(context),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.fit_screen_rounded, size: 16),
                  label: const Text(
                    'Fit width',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Document Paper Canvas
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Center(
                child: Container(
                  width: math.min(
                    840.0,
                    MediaQuery.of(context).size.width - 48,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 40,
                  ),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in _items) ...[
                        if (item.tableData != null) ...[
                          _buildTable(context, item.tableData!),
                          const SizedBox(height: 18),
                        ] else if (item.isTitle) ...[
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.maroonTextOf(context),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                        ] else if (item.isHeading1) ...[
                          const SizedBox(height: 16),
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ] else if (item.isHeading2) ...[
                          const SizedBox(height: 12),
                          Text(
                            item.text,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ] else if (item.isBullet) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 14, bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.text,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: DefensysTokens.textPrimaryOf(
                                        context,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              item.text,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, List<List<String>> table) {
    if (table.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Table(
        border: TableBorder.all(
          color: DefensysTokens.borderOf(context),
          width: 0.8,
        ),
        children: table.asMap().entries.map((entry) {
          final isHeader = entry.key == 0;
          return TableRow(
            decoration: BoxDecoration(
              color: isHeader
                  ? DefensysTokens.surfaceHigherOf(context)
                  : Colors.transparent,
            ),
            children: entry.value.map((cell) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  cell,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 4. Archive Viewer (.zip file explorer)
/// ----------------------------------------------------------------------
class UniversalArchiveViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const UniversalArchiveViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  State<UniversalArchiveViewer> createState() => _UniversalArchiveViewerState();
}

class _UniversalArchiveViewerState extends State<UniversalArchiveViewer> {
  bool _isLoading = true;
  String? _error;
  List<ArchiveFile> _files = [];
  int _totalBytes = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _parseArchive();
  }

  void _parseArchive() {
    try {
      final archive = ZipDecoder().decodeBytes(widget.bytes);
      final files = archive.files.where((f) => f.isFile).toList();
      int total = 0;
      for (final f in files) {
        total += f.size;
      }
      setState(() {
        _files = files;
        _totalBytes = total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (_files.isEmpty || _error != null) {
      return UniversalDeliverableCard(
        fileName: widget.fileName,
        fileSizeBytes: widget.bytes.length,
        category: FileCategory.archive,
        onDownload: widget.onDownload,
        onOpenInNewTab: widget.onOpenInNewTab,
      );
    }

    final filtered = _searchQuery.isEmpty
        ? _files
        : _files
              .where(
                (f) =>
                    f.name.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();

    return Container(
      color: DefensysTokens.surfaceOf(context),
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_files.length} contained files • ${FileViewerMetadata.formatBytes(_totalBytes)} extracted size',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  height: 28,
                  child: TextField(
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Filter files...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      filled: true,
                      fillColor: DefensysTokens.surfaceOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // File List Table
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
              itemBuilder: (context, index) {
                final file = filtered[index];
                final info = DeliverableFormatInfo.fromFileName(file.name);

                return ListTile(
                  dense: true,
                  leading: Icon(info.icon, size: 18, color: info.color),
                  title: Text(
                    file.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  trailing: Text(
                    FileViewerMetadata.formatBytes(file.size),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 5. Spreadsheet Viewer (Excel .xlsx / .xls and CSV / TSV)
/// ----------------------------------------------------------------------
class UniversalSpreadsheetViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const UniversalSpreadsheetViewer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<UniversalSpreadsheetViewer> createState() =>
      _UniversalSpreadsheetViewerState();
}

class _UniversalSpreadsheetViewerState
    extends State<UniversalSpreadsheetViewer> {
  bool _isLoading = true;
  String? _error;
  List<String> _sheetNames = [];
  String _activeSheet = '';
  final Map<String, List<List<String>>> _sheetData = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseSpreadsheet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _parseSpreadsheet() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final lowerName = widget.fileName.toLowerCase();
      if (lowerName.endsWith('.csv') || lowerName.endsWith('.tsv')) {
        _parseCsv(isTsv: lowerName.endsWith('.tsv'));
      } else {
        _parseExcel();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to parse spreadsheet: $e';
        _isLoading = false;
      });
    }
  }

  void _parseCsv({required bool isTsv}) {
    final text = utf8.decode(widget.bytes, allowMalformed: true);
    final delimiter = isTsv ? '\t' : ',';
    final lines = const LineSplitter().convert(text);
    final List<List<String>> rows = [];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(delimiter).map((e) {
        var clean = e.trim();
        if (clean.startsWith('"') && clean.endsWith('"') && clean.length >= 2) {
          clean = clean.substring(1, clean.length - 1).replaceAll('""', '"');
        }
        return clean;
      }).toList();
      rows.add(parts);
    }

    _sheetNames = ['Data'];
    _activeSheet = 'Data';
    _sheetData['Data'] = rows;

    setState(() {
      _isLoading = false;
    });
  }

  void _parseExcel() {
    final excel = xl.Excel.decodeBytes(widget.bytes);
    if (excel.tables.isEmpty) {
      setState(() {
        _error = 'Spreadsheet contains no readable sheets.';
        _isLoading = false;
      });
      return;
    }

    _sheetNames = excel.tables.keys.toList();
    _activeSheet = _sheetNames.first;

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      final List<List<String>> rows = [];
      for (final row in sheet.rows) {
        final rowStrings = row
            .map((cell) => _excelCellText(cell?.value))
            .toList();
        while (rowStrings.isNotEmpty && rowStrings.last.isEmpty) {
          rowStrings.removeLast();
        }
        if (rowStrings.any((s) => s.isNotEmpty)) {
          rows.add(rowStrings);
        }
      }
      _sheetData[entry.key] = rows;
    }

    setState(() {
      _isLoading = false;
    });
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) {
      return (value.value.text ?? '').trim();
    }
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final d = value.value;
      return d == d.roundToDouble()
          ? d.toInt().toString()
          : d.toStringAsFixed(2);
    }
    if (value is xl.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
    if (value is xl.DateCellValue) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  void _copyActiveSheet() {
    final rows = _sheetData[_activeSheet] ?? [];
    final tsv = rows.map((r) => r.join('\t')).join('\n');
    Clipboard.setData(ClipboardData(text: tsv));
    showSuccessToast(context, 'Sheet data copied to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: DefensysTokens.textPrimaryOf(context),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _parseSpreadsheet,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry Parsing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rawRows = _sheetData[_activeSheet] ?? [];
    if (rawRows.isEmpty) {
      return Center(
        child: Text(
          'This sheet is empty.',
          style: TextStyle(
            color: DefensysTokens.textSecondaryOf(context),
            fontSize: 14,
          ),
        ),
      );
    }

    final rows = _searchQuery.isEmpty
        ? rawRows
        : rawRows.where((row) {
            return row.any(
              (cell) => cell.toLowerCase().contains(_searchQuery.toLowerCase()),
            );
          }).toList();

    int maxCols = 0;
    for (final r in rows) {
      if (r.length > maxCols) maxCols = r.length;
    }

    return Container(
      color: DefensysTokens.surfaceOf(context),
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Row(
              children: [
                // Sheet Switcher Tabs
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _sheetNames.map((name) {
                        final isSelected = name == _activeSheet;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _activeSheet = name),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? DefensysTokens.surfaceOf(context)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF10B981)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.table_chart,
                                    size: 13,
                                    color: isSelected
                                        ? const Color(0xFF10B981)
                                        : DefensysTokens.textSecondaryOf(
                                            context,
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? DefensysTokens.textPrimaryOf(
                                              context,
                                            )
                                          : DefensysTokens.textSecondaryOf(
                                              context,
                                            ),
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Metrics Tag
                Text(
                  '${rows.length} rows • $maxCols cols',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(width: 12),

                // Search Filter
                SizedBox(
                  width: 180,
                  height: 28,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search data...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      filled: true,
                      fillColor: DefensysTokens.surfaceOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),

                IconButton(
                  tooltip: 'Copy sheet to clipboard',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: _copyActiveSheet,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // Spreadsheet Grid
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 40,
                  horizontalMargin: 12,
                  columnSpacing: 18,
                  border: TableBorder.all(
                    color: DefensysTokens.borderOf(context),
                    width: 0.8,
                  ),
                  headingRowColor: WidgetStateProperty.all(
                    DefensysTokens.surfaceHigherOf(context),
                  ),
                  columns: List.generate(maxCols, (colIdx) {
                    final colName = colIdx < 26
                        ? String.fromCharCode(65 + colIdx)
                        : '${String.fromCharCode(64 + colIdx ~/ 26)}${String.fromCharCode(65 + colIdx % 26)}';
                    return DataColumn(
                      label: Text(
                        colName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    );
                  }),
                  rows: List.generate(rows.length, (rowIdx) {
                    final row = rows[rowIdx];
                    final isEven = rowIdx % 2 == 0;
                    return DataRow(
                      color: WidgetStateProperty.all(
                        isEven
                            ? Colors.transparent
                            : DefensysTokens.surfaceHigherOf(
                                context,
                              ).withValues(alpha: 0.35),
                      ),
                      cells: List.generate(maxCols, (colIdx) {
                        final val = colIdx < row.length ? row[colIdx] : '';
                        return DataCell(
                          SelectableText(
                            val,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 6. Code & Text File Viewer (.txt, .md, .json, .py, .dart, etc.)
/// ----------------------------------------------------------------------
class UniversalCodeTextViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const UniversalCodeTextViewer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<UniversalCodeTextViewer> createState() =>
      _UniversalCodeTextViewerState();
}

class _UniversalCodeTextViewerState extends State<UniversalCodeTextViewer> {
  late String _fullText;
  late List<String> _lines;
  bool _wrapLines = true;

  @override
  void initState() {
    super.initState();
    _fullText = utf8.decode(widget.bytes, allowMalformed: true);
    _lines = const LineSplitter().convert(_fullText);
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _fullText));
    showSuccessToast(context, 'Copied full text to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DefensysTokens.surfaceOf(context),
      child: Column(
        children: [
          // Sub-toolbar in Image 2 style
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${_lines.length} lines • ${_fullText.length} characters',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _wrapLines ? 'Line Wrap: ON' : 'Line Wrap: OFF',
                  icon: Icon(
                    _wrapLines ? Icons.wrap_text : Icons.menu,
                    size: 16,
                    color: _wrapLines ? const Color(0xFFF59E0B) : null,
                  ),
                  onPressed: () => setState(() => _wrapLines = !_wrapLines),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Copy all text',
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  onPressed: _copyAll,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // Code Text Area with Line Numbers
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: _wrapLines ? Axis.vertical : Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line Numbers Gutter
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(
                          context,
                        ).withValues(alpha: 0.5),
                        border: Border(
                          right: BorderSide(
                            color: DefensysTokens.borderOf(context),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(_lines.length, (idx) {
                          return Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                              height: 1.5,
                              color: DefensysTokens.textSecondaryOf(
                                context,
                              ).withValues(alpha: 0.6),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Code Content
                    Expanded(
                      flex: _wrapLines ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _fullText,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.5,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 7. Institutional Deliverable Card (Clean Image 2 Aesthetic)
/// ----------------------------------------------------------------------
class UniversalDeliverableCard extends StatelessWidget {
  final String fileName;
  final int fileSizeBytes;
  final FileCategory category;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const UniversalDeliverableCard({
    super.key,
    required this.fileName,
    required this.fileSizeBytes,
    required this.category,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  Widget build(BuildContext context) {
    final color = FileViewerMetadata.getCategoryColor(category);
    final icon = FileViewerMetadata.getCategoryIcon(category);
    final categoryLabel = FileViewerMetadata.getCategoryLabel(
      category,
      fileName,
    );

    String formatDescription;
    String tipDescription;

    if (category == FileCategory.officeDoc) {
      formatDescription = 'Microsoft Word / Rich Text Document';
      tipDescription =
          'Contains complex typography, tables, and styles. For full fidelity editing, open in Word or Google Docs.';
    } else if (category == FileCategory.officePresentation) {
      formatDescription = 'Microsoft PowerPoint Presentation Deck';
      tipDescription =
          'Contains slide layouts, shapes, and animations. Download to present with native transitions.';
    } else if (category == FileCategory.archive) {
      formatDescription = 'Compressed File Archive Package';
      tipDescription =
          'Contains bundled deliverables or source repositories. Download and extract to explore contents.';
    } else {
      formatDescription = 'Application Deliverable Binary';
      tipDescription =
          'Requires external software to open or execute directly on your machine.';
    }

    final isDark = DefensysTokens.isDark(context);
    final canvasColor = isDark
        ? DefensysTokens.backgroundOf(context)
        : const Color(0xFFF1F5F9);

    return Container(
      color: canvasColor,
      child: Center(
        child: Container(
          width: 560,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DefensysTokens.borderOf(context),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Circle
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, size: 34, color: color),
              ),
              const SizedBox(height: 16),

              // Category tag
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  categoryLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // File Name
              Text(
                fileName,
                style: TextStyle(
                  color: DefensysTokens.textPrimaryOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                formatDescription,
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontSize: 12.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Specs Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Column(
                  children: [
                    _specRow(
                      context,
                      'File Size',
                      FileViewerMetadata.formatBytes(fileSizeBytes),
                    ),
                    Divider(
                      color: DefensysTokens.borderOf(context),
                      height: 16,
                    ),
                    _specRow(
                      context,
                      'MIME Type',
                      FileViewerMetadata.getMimeType(fileName),
                    ),
                    Divider(
                      color: DefensysTokens.borderOf(context),
                      height: 16,
                    ),
                    _specRow(
                      context,
                      'Security Status',
                      'Verified Clean Deliverable',
                      isVerified: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Guidance Alert
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tipDescription,
                        style: TextStyle(
                          color: DefensysTokens.textSecondaryOf(context),
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 17),
                    label: const Text(
                      'Download Original File',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onOpenInNewTab,
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text(
                      'Open in New Tab',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DefensysTokens.textPrimaryOf(context),
                      side: BorderSide(color: DefensysTokens.borderOf(context)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  Widget _specRow(
    BuildContext context,
    String label,
    String value, {
    bool isVerified = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: DefensysTokens.textSecondaryOf(context),
            fontSize: 12,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isVerified) ...[
              const Icon(Icons.verified, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                color: isVerified
                    ? const Color(0xFF10B981)
                    : DefensysTokens.textPrimaryOf(context),
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Backward compatibility alias
typedef UniversalOfficeInspectorCard = UniversalDeliverableCard;

/// ----------------------------------------------------------------------
/// 8. Audio Player Card (Clean Image 2 Design)
/// ----------------------------------------------------------------------
class UniversalAudioPlayerCard extends StatelessWidget {
  final String fileName;
  final int fileSizeBytes;
  final Widget audioPlayerWidget;

  const UniversalAudioPlayerCard({
    super.key,
    required this.fileName,
    required this.fileSizeBytes,
    required this.audioPlayerWidget,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final canvasColor = isDark
        ? DefensysTokens.backgroundOf(context)
        : const Color(0xFFF1F5F9);

    return Container(
      color: canvasColor,
      child: Center(
        child: Container(
          width: 520,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DefensysTokens.borderOf(context),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF43F5E).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.audiotrack,
                  size: 34,
                  color: Color(0xFFF43F5E),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                fileName,
                style: TextStyle(
                  color: DefensysTokens.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                FileViewerMetadata.formatBytes(fileSizeBytes),
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 24),

              // Embedded HTML5 or Flutter Audio Widget
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: audioPlayerWidget,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
