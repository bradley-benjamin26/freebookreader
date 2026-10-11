import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'common.dart';

/// What a source is, how the app uses it, how to use it directly, and a
/// donation button.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Future<SourceInfo>? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _info ??= _load();
  }

  Future<SourceInfo> _load() async {
    final sources = await Services.of(context).api.sources();
    return sources.firstWhere((s) => s.id == widget.sourceId);
  }

  @override
  Widget build(BuildContext context) {
    final name = sourceName(widget.sourceId);
    return Scaffold(
      key: const Key('about-page'),
      appBar: AppBar(title: Text('About $name')),
      body: FutureBuilder<SourceInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveRegion(
                      key: const Key('about-error'),
                      child: Text('Could not load the details of $name.', textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('retry'),
                      onPressed: () => setState(() {
                        _info = _load();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading'));
          }
          return _AboutBody(info: snapshot.data!);
        },
      ),
    );
  }
}

class _AboutBody extends StatelessWidget {
  const _AboutBody({required this.info});

  final SourceInfo info;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final urls = Services.of(context).urlOpener;
    Widget section(String title, String body, Key key) => Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Heading(title, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(body, key: key, style: text.bodyLarge),
            ],
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            Heading(info.name, key: const Key('about-title'), style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(info.description, key: const Key('about-description'), style: text.bodyLarge),
            section('How this app uses it', info.howItWorks, const Key('about-how-it-works')),
            section('Using it directly', info.howToAccess, const Key('about-how-to-access')),
            const SizedBox(height: 16),
            Text(
              info.inApp
                  ? 'Books from ${info.name} open in this app.'
                  : 'Books from ${info.name} open on its website.',
              key: const Key('about-reading-note'),
              style: text.bodyLarge,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (info.donationUrl != null)
                  FilledButton(
                    key: const Key('donate'),
                    onPressed: () => urls.open(Uri.parse(info.donationUrl!)),
                    child: Text('Donate to ${info.name}'),
                  ),
                OutlinedButton(
                  key: const Key('visit-website'),
                  onPressed: () => urls.open(Uri.parse(info.websiteUrl)),
                  child: Text('Visit the ${info.name} website'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
