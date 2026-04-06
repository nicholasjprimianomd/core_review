import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

Future<void> showPdfWebDialog(BuildContext context, String url) async {
  if (!context.mounted) {
    return;
  }
  final viewType = 'ref-pdf-${DateTime.now().microsecondsSinceEpoch}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return iframe;
  });
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final screen = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: SizedBox(
          width: screen.width * 0.95,
          height: screen.height * 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Textbook PDF',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: HtmlElementView(viewType: viewType),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open in new tab'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
