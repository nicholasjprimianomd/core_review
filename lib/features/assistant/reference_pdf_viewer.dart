import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reference_pdf_web_dialog_stub.dart'
    if (dart.library.html) 'reference_pdf_web_dialog.dart';

Uri buildReferencePdfUri(String pdfUrl, int page) {
  final base = Uri.parse(pdfUrl);
  return base.replace(fragment: 'page=$page');
}

Future<void> showReferencePdfViewer(
  BuildContext context, {
  required String pdfUrl,
  required int page,
}) async {
  final uri = buildReferencePdfUri(pdfUrl, page);
  if (kIsWeb) {
    await showPdfWebDialog(context, uri.toString());
    return;
  }
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
