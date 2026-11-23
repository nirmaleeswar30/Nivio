import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/widgets/stream_surfaces.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  final _url = TextEditingController();
  late Future<List<ExtensionRepo>> _repos;
  bool _busy = false;

  ExtensionRepository get _service => ref.read(extensionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _repos = _service.list();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _update(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Could not update extensions. Check the repository URL and try again.',
            ),
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _repos = _service.list();
        });
    }
  }

  Future<void> _enable(ExtensionProvider provider, bool enabled) async {
    if (enabled && provider.repository.format == ExtensionFormat.cloudstream) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Enable ${provider.name}?'),
          content: Text(
            '${provider.repository.name} supplies Android code that runs with Nivio’s app permissions. Enable it only if you trust the repository.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    await _update(() => _service.setEnabled(provider, enabled));
  }

  void _add() {
    final text = _url.text.trim();
    if (text.isEmpty) return;
    _update(() async {
      await _service.add(text);
      if (mounted && _url.text.trim() == text) _url.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Extensions'),
      titleTextStyle: Theme.of(
        context,
      ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
    ),
    body: DecoratedBox(
      decoration: BoxDecoration(
        gradient: NivioTheme.backgroundGradientOf(context),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: FutureBuilder<List<ExtensionRepo>>(
            future: _repos,
            builder: (context, snapshot) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StreamPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StreamSectionLabel(
                        'NUVIO AND CLOUDSTREAM REPOSITORIES',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _url,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onSubmitted: (_) => _add(),
                        decoration: const InputDecoration(
                          labelText: 'Repository URL',
                          hintText: 'https://…/manifest.json',
                          prefixIcon: Icon(PhosphorIconsRegular.link),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(PhosphorIconsRegular.plus),
                        label: const Text('Add repository'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_busy ||
                    (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData))
                  const LinearProgressIndicator(),
                if (snapshot.hasError)
                  const ListTile(
                    title: Text('Could not read installed repositories.'),
                  ),
                if (snapshot.data?.isEmpty == true)
                  const ListTile(title: Text('No repositories installed')),
                for (final repo in snapshot.data ?? const <ExtensionRepo>[])
                  _repositoryCard(repo),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _repositoryCard(ExtensionRepo repo) {
    final isCloudstream = repo.format == ExtensionFormat.cloudstream;
    final available = ExtensionResolver.supports(repo.format);
    final count = repo.enabledIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StreamPanel(
        child: ExpansionTile(
          leading: const StreamGlyph(PhosphorIconsRegular.puzzlePiece),
          title: Text(repo.name),
          subtitle: Text(
            '${isCloudstream ? 'Cloudstream' : 'Nuvio JavaScript'} · $count enabled${available ? '' : ' · Android only'}',
          ),
          children: [
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _update(() => _service.refresh(repo)),
                  child: const Text('Refresh'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _update(() => _service.remove(repo)),
                  child: const Text('Remove'),
                ),
              ],
            ),
            for (final provider in repo.providers)
              SwitchListTile(
                title: Text(provider.name),
                subtitle: provider.description.isEmpty
                    ? null
                    : Text(provider.description),
                value: provider.enabled,
                onChanged:
                    _busy ||
                        !available ||
                        provider.entry['enabled'] == false ||
                        (isCloudstream && provider.entry['status'] == 0)
                    ? null
                    : (enabled) => _enable(provider, enabled),
              ),
          ],
        ),
      ),
    );
  }
}
