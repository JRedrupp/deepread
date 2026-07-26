import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/local/database.dart';
import '../../data/remote/takedown_repository.dart';

/// Loads the article's locally unzipped index.html directly from disk —
/// no network access needed, which is the whole point of the pipeline.
class ArticleReaderScreen extends StatefulWidget {
  const ArticleReaderScreen({super.key, required this.article});

  final LocalArticle article;

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFF10151C));
    _loadArticle();
  }

  Future<void> _loadArticle() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final indexFile = File(
      p.join(docsDir.path, widget.article.localPath, 'index.html'),
    );
    if (await indexFile.exists()) {
      await _controller.loadFile(indexFile.path);
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
      body: WebViewWidget(controller: _controller),
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
