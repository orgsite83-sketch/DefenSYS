// Conditional export based on platform
export 'universal_file_viewer_models.dart';
export 'universal_file_viewer_widgets.dart';
export 'universal_file_viewer_stub.dart'
    if (dart.library.html) 'universal_file_viewer_web.dart';
