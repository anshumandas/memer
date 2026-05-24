import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Lets the user pick an image to use as the meme background.
///
/// Uses `file_selector`, which works on Android, iOS, web, Windows, macOS and
/// Linux. The image is read into memory as bytes so the rest of the app is
/// completely platform-agnostic (there are no file paths on the web).
class MediaPickerService {
  const MediaPickerService();

  Future<Uint8List?> pickImageBytes() async {
    const XTypeGroup imageGroup = XTypeGroup(
      label: 'Images',
      extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      mimeTypes: <String>['image/*'],
    );

    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[imageGroup],
    );
    if (file == null) return null; // cancelled
    return file.readAsBytes();
  }
}
