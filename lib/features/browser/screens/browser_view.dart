import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/database/local_db.dart';

class BrowserView extends StatefulWidget {
  final String initialQuery;
  const BrowserView({super.key, required this.initialQuery});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  InAppWebViewController? webViewController;
  double progress = 0;
  String currentUrl = "";

  @override
  void initState() {
    super.initState();
    currentUrl = widget.initialQuery.contains('.') ? 'https://${widget.initialQuery}' : 'https://www.google.com/search?q=${Uri.encodeComponent(widget.initialQuery)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        title: Text(currentUrl, style: const TextStyle(fontSize: 14, color: AppTheme.accentCyan)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (await webViewController?.canGoBack() ?? false) {
              webViewController?.goBack();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          if (progress < 1.0) LinearProgressIndicator(value: progress, color: AppTheme.accentCyan, backgroundColor: Colors.transparent, minHeight: 3),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(currentUrl)),
              onWebViewCreated: (controller) => webViewController = controller,
              onLoadStop: (controller, url) async {
                if (url != null) {
                  setState(() => currentUrl = url.toString());
                  await LocalDB.saveHistoryItem(url.toString(), url.toString());
                }
              },
              onProgressChanged: (controller, progress) => setState(() => this.progress = progress / 100),
            ),
          ),
        ],
      ),
    );
  }
}
