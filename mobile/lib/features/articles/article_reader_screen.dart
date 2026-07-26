import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/local/database.dart';
import '../../data/remote/takedown_repository.dart';
import '../../theme/app_theme.dart';

/// Loads the article's locally unzipped index.html directly from disk —
/// no network access needed, which is the whole point of the pipeline.
class ArticleReaderScreen extends StatefulWidget {
  const ArticleReaderScreen({super.key, required this.article});

  final LocalArticle article;

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final localPath = widget.article.localPath;
    if (localPath != null) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setBackgroundColor(const Color(0xFF10151C));
      _loadArticle(localPath);
    }
  }

  Future<void> _loadArticle(String localPath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final indexFile = File(p.join(docsDir.path, localPath, 'index.html'));
    if (await indexFile.exists()) {
      await _controller!.loadFile(indexFile.path);
    }
  }

  Future<void> _reportContent() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReportDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    try {
      await const TakedownRepository().fileReport(
        articleId: widget.article.id,
        reason: reason.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.article.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report content issue',
            onPressed: _reportContent,
          ),
        ],
      ),
      body: _controller != null ? WebViewWidget(controller: _controller!) : _SummaryOnlyView(article: widget.article),
    );
  }
}

/// Shown for paywalled articles, which have only an RSS-provided summary
/// and no rendered HTML to display in a WebView.
class _SummaryOnlyView extends StatelessWidget {
  const _SummaryOnlyView({required this.article});

  final LocalArticle article;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (article.byline != null) article.byline!,
      if (article.publishedAt != null) article.publishedAt!.toIso8601String().split('T').first,
    ].join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This article is behind a paywall — only a summary is available offline.',
            style: AppTheme.metadataStyle(color: AppTheme.accent, fontSize: 13),
          ),
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(metadata, style: AppTheme.metadataStyle()),
          ],
          const SizedBox(height: 16),
          Text(
            (article.summary?.isNotEmpty ?? false) ? article.summary! : 'No summary available for this article.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report content issue'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. copyright concern, incorrect rendering...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
