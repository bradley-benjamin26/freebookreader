import 'package:flutter/material.dart';

import '../app.dart';

/// Stands in for a PDF viewer until the reader package is chosen.
class PdfLinkOut extends StatelessWidget {
  const PdfLinkOut({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This app cannot show PDF books yet.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Services.of(context).urlOpener.open(url),
              child: const Text('Open the PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
