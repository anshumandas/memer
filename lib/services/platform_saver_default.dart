import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Native (Android/iOS/desktop) "save as" using a system file dialog.
Future<String?> savePng(Uint8List bytes, String suggestedName) async {
  const XTypeGroup pngGroup = XTypeGroup(
    label: 'PNG image',
    extensions: <String>['png'],
    mimeTypes: <String>['image/png'],
  );

  final FileSaveLocation? location = await getSaveLocation(
    acceptedTypeGroups: const <XTypeGroup>[pngGroup],
    suggestedName: suggestedName,
  );
  if (location == null) return null; // user cancelled

  final XFile file = XFile.fromData(
    bytes,
    mimeType: 'image/png',
    name: suggestedName,
  );
  await file.saveTo(location.path);
  return location.path;
}
