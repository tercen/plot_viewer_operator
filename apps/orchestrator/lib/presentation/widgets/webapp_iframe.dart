import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../services/message_router.dart';

/// Renders a webapp as an iframe using HtmlElementView.
///
/// Each mount gets a unique platform view factory registration via a
/// monotonic counter — this avoids re-registration crashes when a tool
/// strip is closed and reopened (the old viewType becomes orphaned but
/// harmless).
class WebappIframe extends StatefulWidget {
  final String instanceId;
  final String url;
  final MessageRouter messageRouter;
  final VoidCallback? onDispose;

  const WebappIframe({
    super.key,
    required this.instanceId,
    required this.url,
    required this.messageRouter,
    this.onDispose,
  });

  @override
  State<WebappIframe> createState() => _WebappIframeState();
}

class _WebappIframeState extends State<WebappIframe> {
  static int _nextViewId = 0;

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    final viewId = _nextViewId++;
    _viewType = 'webapp-iframe-${widget.instanceId}-$viewId';
    _registerFactory();
  }

  void _registerFactory() {
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
          ..src = widget.url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'clipboard-read; clipboard-write';

        // Register with message router for postMessage routing
        widget.messageRouter.registerIframe(widget.instanceId, iframe);

        return iframe;
      },
    );
  }

  @override
  void dispose() {
    widget.messageRouter.unregisterIframe(widget.instanceId);
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
