// Conditional export based on platform
export 'pdf_viewer_stub.dart'
    if (dart.library.html) 'pdf_viewer_web.dart';
