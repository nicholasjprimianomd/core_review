import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Thin JS-interop surface for the Cloudflare Turnstile global injected by
/// `https://challenges.cloudflare.com/turnstile/v0/api.js` (see `web/index.html`).
@JS('turnstile')
external _Turnstile? get _turnstile;

extension type _Turnstile._(JSObject _) implements JSObject {
  external JSAny? render(web.Element container, _TurnstileOptions options);
  external void reset(JSAny widgetId);
  external void remove(JSAny widgetId);
}

extension type _TurnstileOptions._(JSObject _) implements JSObject {
  external factory _TurnstileOptions({
    required String sitekey,
    required JSFunction callback,
    // ignore: non_constant_identifier_names
    JSFunction? error_callback,
    // ignore: non_constant_identifier_names
    JSFunction? expired_callback,
    String? theme,
    String? size,
  });
}

/// Renders a Cloudflare Turnstile widget in a HtmlElementView and invokes
/// [onToken] whenever a token is issued or cleared (null on error/expiry).
///
/// Exposes [TurnstileController] via [controller] so callers can reset the
/// widget after a single-use token has been consumed.
class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    required this.siteKey,
    required this.onToken,
    this.controller,
    this.theme = 'auto',
    super.key,
  });

  final String siteKey;
  final ValueChanged<String?> onToken;
  final TurnstileController? controller;

  /// One of `light`, `dark`, `auto`.
  final String theme;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

/// Public handle that lets the enclosing form clear the captcha token
/// (e.g. after a failed auth attempt, since Turnstile tokens are single-use).
class TurnstileController {
  _TurnstileWidgetState? _state;

  void _attach(_TurnstileWidgetState state) {
    _state = state;
  }

  void _detach(_TurnstileWidgetState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  void reset() {
    _state?._reset();
  }
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  static int _nextId = 0;

  late final String _viewType;
  web.HTMLDivElement? _container;
  JSAny? _widgetId;
  Timer? _readyPoll;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _viewType = 'cf-turnstile-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

    if (!kIsWeb) {
      return;
    }

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final div = web.HTMLDivElement();
      div.style
        ..display = 'inline-block'
        ..minHeight = '65px';
      _container = div;
      _scheduleRender();
      return div;
    });
  }

  void _scheduleRender() {
    if (!kIsWeb) {
      return;
    }
    if (_tryRender()) {
      return;
    }
    _readyPoll?.cancel();
    _readyPoll = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_tryRender()) {
        timer.cancel();
      }
    });
  }

  bool _tryRender() {
    final container = _container;
    final turnstile = _turnstile;
    if (container == null || turnstile == null) {
      return false;
    }
    if (_widgetId != null) {
      return true;
    }

    final options = _TurnstileOptions(
      sitekey: widget.siteKey,
      callback: ((JSString token) {
        widget.onToken(token.toDart);
      }).toJS,
      error_callback: ((JSAny? _) {
        widget.onToken(null);
      }).toJS,
      expired_callback: ((JSAny? _) {
        widget.onToken(null);
      }).toJS,
      theme: widget.theme,
      size: 'flexible',
    );

    _widgetId = turnstile.render(container, options);
    return _widgetId != null;
  }

  void _reset() {
    widget.onToken(null);
    if (!kIsWeb) {
      return;
    }
    final turnstile = _turnstile;
    final id = _widgetId;
    if (turnstile != null && id != null) {
      turnstile.reset(id);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _readyPoll?.cancel();
    if (kIsWeb) {
      final turnstile = _turnstile;
      final id = _widgetId;
      if (turnstile != null && id != null) {
        turnstile.remove(id);
      }
    }
    _widgetId = null;
    _container = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 70,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
