// Web implementation: trigger a browser download of the PNG bytes.
//
// Only compiled on the web (selected via the conditional import in
// image_export_service.dart), so `dart:html` never reaches native builds.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> savePng(Uint8List bytes, String suggestedName) async {
  final html.Blob blob = html.Blob(<Object>[bytes], 'image/png');
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = suggestedName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return suggestedName;
}
