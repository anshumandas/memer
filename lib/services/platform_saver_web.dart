// Web implementation: trigger a browser download of the PNG bytes.
//
// Only compiled on the web (selected via the conditional import in
// image_export_service.dart), so this file is never reachable on native
// builds. Uses `package:web` + `dart:js_interop` (the modern replacement
// for the deprecated `dart:html`).
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> savePng(Uint8List bytes, String suggestedName) async {
  // `Blob`'s first arg is a JSArray of blob parts. A `Uint8List` becomes a
  // JS typed array via `.toJS`, then we wrap it in a one-element JS array.
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = suggestedName
        ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return suggestedName;
}
