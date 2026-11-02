import 'package:file_picker/file_picker.dart';

class TestFilePicker extends FilePicker {
  FilePickerResult? result;
  Future<FilePickerResult?> Function()? onPick;
  int calls = 0;
  FileType? type;
  List<String>? extensions;
  bool? multiple;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    this.type = type;
    extensions = allowedExtensions;
    multiple = allowMultiple;
    return onPick != null ? await onPick!() : result;
  }
}
