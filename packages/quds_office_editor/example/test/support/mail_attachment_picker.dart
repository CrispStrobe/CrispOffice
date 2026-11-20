import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

final class MailAttachmentPickerFixture extends FilePicker {
  MailAttachmentPickerFixture(this.select);
  final Future<FilePickerResult?> Function() select;
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    calls++;
    expect(type, FileType.any);
    expect(allowMultiple, isTrue);
    expect(withData, isFalse);
    expect(withReadStream, isTrue);
    return select();
  }
}
