/// 前端卡的**宿主包装**。
///
/// 这段代码原本长在 `chat_bubble.dart` 里（`_wrapFrontendCardHtml`），
/// 是踩坑攒出来的：它往卡片 HTML 里注入一层 CSS reset，以及一整套
/// **防高度振荡的自测量脚本**（防 ratchet、防宿主回声、比例守卫、跟随器）。
/// 注释里那些推理都是真金白银换来的，**不要顺手重构**。
///
/// 抽出来的原因：工坊的实时预览要和聊天里渲染的**完全一致**，
/// 否则「预览通过、聊天挂不上」。两边共用这一份。
///
/// 唯一的改动是把方法挪成静态，并加了一个 [extraScript] 注入点
/// （用来把变量垫片塞进 `<head>`，保证它先于卡片自己的脚本执行）。
class FrontendCardHost {
  const FrontendCardHost._();

  static String wrap(String rawHtml, {String extraScript = ''}) {
    final trimmed = rawHtml.trim();
    final hasHtmlTag =
        RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(trimmed);
    final hostStyle = '''
<style>
  html, body {
    margin: 0 !important;
    padding: 0 !important;
    background: transparent !important;
    -webkit-text-size-adjust: 100% !important;
    overflow-x: hidden !important;
  }
  img, video, canvas, svg {
    max-width: 100% !important;
    height: auto !important;
  }
  table {
    display: block !important;
    max-width: 100% !important;
    overflow-x: auto !important;
  }
  pre {
    white-space: pre-wrap !important;
    word-wrap: break-word !important;
    max-width: 100% !important;
  }
</style>
''';
    final hostScript = '''
<script>
  (function () {
    window.__frontendCardDebugErrors = [];
    var committedHeight = 0;

    // This page is measured in order to size the very viewport it is laid out
    // in, which closes a loop for any content sized against that viewport --
    // vh units, a percentage height chain, a fixed panel. The host applies the
    // height we reported, the shorter viewport makes that content measure
    // shorter still, and for a proportional card (height: 90vh) every pass
    // multiplies the height by the same factor, so it walks down geometrically
    // and only stops at the floor. That walk is the "height keeps dropping and
    // then finally holds still" seen after a tab switch.
    //
    // The walk is cut at its source: a host resize never starts a measurement.
    // This viewport is only ever resized by the host applying a height, so
    // re-measuring right after it can only read back our own echo -- and for a
    // proportional card that echo is shorter. Measurements start from content
    // signals only: a DOM mutation, an image load, an interaction, or a width
    // change (which really does reflow).
    //
    // A shrink that does come from a content signal still clears two guards:
    //   - no host resize is in flight, which would mean the "shorter" page is
    //     the height we just asked for coming back rather than content news; and
    //   - the height is not the same fraction of the viewport as the committed
    //     one, which is the signature of a height that tracks the viewport and
    //     would keep walking if it were followed.
    // Growth is always reported: it cannot ratchet, and a frame that is too
    // small clips content while a frame that is too large only wastes space.
    var MIN_REPORT_HEIGHT = 24;
    // A card that animates its tab height passes through many intermediate
    // heights. The follower polls until the height holds still and commits one
    // settled value, so the host never chases a moving target.
    var HEIGHT_FOLLOW_TICK_MS = 60;
    var HEIGHT_STABLE_TICKS = 3;
    var HEIGHT_FOLLOW_MAX_MS = 2000;
    // Two heights count as the same fraction of the viewport within this much.
    // Kept tight: a viewport-sized card reproduces its own ratio to floating
    // point precision (0.90, then 0.900 exactly), so anything looser would start
    // blocking legitimate small shrinks. The cost of the tight value is that a
    // card whose real content happens to land within 1% of the same fraction
    // keeps the taller frame, which only wastes a few pixels and never clips.
    var RATIO_TOLERANCE = 0.01;
    // How long a host resize keeps its echo protected. The resize arrives a frame
    // or two after the height is applied, and re-flows the body just after that.
    var HEIGHT_ECHO_MS = 250;
    // A shrink blocked by the echo window is re-measured this many times once the
    // window closes, so a real content change inside it is not lost.
    var ECHO_RETRY_LIMIT = 3;

    var followerTimer = null;
    var followerDeadline = 0;
    var followerLastHeight = -1;
    var followerStableTicks = 0;
    // Set by a content signal, consumed by the next committed shrink.
    var shrinkAllowed = false;
    // Fraction of the viewport the committed height occupied. A card sized
    // against the viewport keeps this fraction constant on every pass, which is
    // how it is told apart from a card whose content really got shorter.
    var committedRatio = -1;
    var lastViewportW = 0;
    var lastViewportH = 0;
    var echoActiveUntil = 0;
    var echoClearTimer = null;
    var echoRetryPending = false;
    var echoRetryCount = 0;
    var suppressedCount = 0;

    function viewportHeight() {
      return window.innerHeight || 0;
    }

    // Height as a fraction of the viewport, or -1 when it is not viewport-tied.
    function viewportRatio(height) {
      var vp = viewportHeight();
      if (height <= 0 || vp <= 0) return -1;
      return height / vp;
    }

    function pushLog(message) {
      try {
        if (!message) return;
        var text = String(message);
        window.__frontendCardDebugErrors.push(text);
        if (window.FlutterCardLog && window.FlutterCardLog.postMessage) {
          window.FlutterCardLog.postMessage(text);
        }
      } catch (_) {}
    }

    function getElementBottom(element, rootTop) {
      if (!element) return 0;
      var rect = element.getBoundingClientRect();
      return Math.max(0, (rect.bottom || 0) - rootTop);
    }

    function measureHeight() {
      var body = document.body;
      var html = document.documentElement;
      if (!body || !html) return 0;

      var bodyRect = body.getBoundingClientRect();
      var maxBottom = 0;
      var children = body.children || [];
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (!child || child.tagName === 'SCRIPT' || child.tagName === 'STYLE' || child.tagName === 'LINK') {
          continue;
        }
        var style = window.getComputedStyle(child);
        if (style && (style.position === 'fixed' || style.position === 'sticky')) {
          continue;
        }
        var offsetBottom = (child.offsetTop || 0) + (child.offsetHeight || 0);
        maxBottom = Math.max(
          maxBottom,
          getElementBottom(child, bodyRect.top || 0),
          offsetBottom
        );
      }

      var bodyStyle = window.getComputedStyle(body);
      var marginBottom = parseFloat(bodyStyle.marginBottom || '0') || 0;
      return Math.ceil(Math.max(
        body.scrollHeight || 0,
        body.offsetHeight || 0,
        maxBottom + marginBottom
      ));
    }

    // A card that animates its tab height moves through many intermediate
    // heights. Sampling that motion every frame and reporting each value makes
    // the host chase a moving target, so instead the follower polls until the
    // height holds still and then commits exactly one value.
    function measureOnce() {
      return Math.max(measureHeight(), MIN_REPORT_HEIGHT);
    }

    // Decides whether a measurement may be reported.
    //
    // Growing is always reported: a frame that is too small clips content, a
    // frame that is too large only wastes space, and growth cannot run away.
    // Shrinking is what closes the feedback loop, so it must clear both guards
    // documented at the top of this script.
    function commitHeight() {
      var height = measureOnce();

      if (committedHeight > 0 && Math.abs(height - committedHeight) <= 1) {
        return;
      }

      if (height < committedHeight) {
        var blockedBy = '';
        if (!shrinkAllowed) {
          blockedBy = 'no content change';
        } else if (Date.now() < echoActiveUntil) {
          // The host applied a height we asked for; the shorter page measured
          // now is that resize coming back, not the card getting shorter.
          // Re-check once the echo window closes, in case a real content change
          // landed inside it.
          blockedBy = 'viewport echo';
          if (echoRetryCount < ECHO_RETRY_LIMIT) {
            echoRetryCount++;
            scheduleEchoClear();
          }
        } else {
          // A proportional card measures the same fraction of the viewport on
          // every pass, so following it down would never converge.
          var after = viewportRatio(height);
          if (committedRatio > 0 && after > 0 &&
              Math.abs(committedRatio - after) <= RATIO_TOLERANCE) {
            blockedBy = 'viewport-bound';
          }
        }

        if (blockedBy !== '') {
          suppressedCount++;
          if (suppressedCount <= 5) {
            pushLog('[height] held ' + committedHeight + ' against ' + height +
                ' (' + blockedBy + ')');
          }
          return;
        }
      }

      committedHeight = height;
      committedRatio = viewportRatio(height);
      shrinkAllowed = false;
      if (window.FlutterCardHeight && window.FlutterCardHeight.postMessage) {
        window.FlutterCardHeight.postMessage(String(height));
      }
    }

    function stopFollower() {
      if (followerTimer) {
        clearTimeout(followerTimer);
        followerTimer = null;
      }
      followerStableTicks = 0;
      followerLastHeight = -1;
      followerDeadline = 0;
    }

    // Polls until the measured height stops moving (or the deadline passes) and
    // then commits the settled value once.
    function followerTick() {
      var height = measureOnce();
      if (height === followerLastHeight) {
        followerStableTicks++;
      } else {
        followerLastHeight = height;
        followerStableTicks = 0;
      }

      if (followerStableTicks >= HEIGHT_STABLE_TICKS ||
          Date.now() >= followerDeadline) {
        stopFollower();
        commitHeight();
        return;
      }

      followerTimer = setTimeout(function () {
        followerTimer = null;
        followerTick();
      }, HEIGHT_FOLLOW_TICK_MS);
    }

    function startFollower(allowShrink) {
      if (followerTimer == null) {
        // Fresh window: nothing may shrink the card until the caller says so.
        followerDeadline = Date.now() + HEIGHT_FOLLOW_MAX_MS;
        followerLastHeight = -1;
        followerStableTicks = 0;
        followerTimer = setTimeout(function () {
          followerTimer = null;
          followerTick();
        }, HEIGHT_FOLLOW_TICK_MS);
      }
      if (allowShrink) {
        // A content change outranks a plain viewport resize, and must not be
        // downgraded by a resize that arrives while the same window is running.
        shrinkAllowed = true;
      }
    }

    // The card's own DOM changed (tab switch, script update, image load), so the
    // new height may be shorter than the old one.
    function markContentChanged() {
      startFollower(true);
    }

    // Takes the current viewport metrics and reports how they moved since the
    // previous call. The host applies a height by resizing this viewport, so a
    // viewport change is our own echo; an unchanged viewport means the body
    // resized on its own, which is the card's own content changing.
    function noteViewport() {
      var w = window.innerWidth || 0;
      var h = window.innerHeight || 0;
      var hadMetrics = lastViewportW > 0 || lastViewportH > 0;
      var widthChanged = hadMetrics && Math.abs(w - lastViewportW) > 1;
      var heightChanged = hadMetrics && Math.abs(h - lastViewportH) > 1;
      lastViewportW = w;
      lastViewportH = h;
      // The first observation only establishes the baseline.
      return {
        changed: hadMetrics && (widthChanged || heightChanged),
        widthChanged: widthChanged,
      };
    }

    // Both the window resize event and the body ResizeObserver can observe the
    // same host resize, so whoever sees it first opens the echo window and the
    // other one is ignored rather than mistaken for a content change.
    function noteHostResize(widthChanged) {
      echoActiveUntil = Date.now() + HEIGHT_ECHO_MS;
      if (widthChanged) {
        // A width change really does reflow the content (rotation, split
        // screen), so the resulting height is legitimate and may be shorter.
        echoRetryPending = false;
        echoRetryCount = 0;
        startFollower(true);
      }
    }

    function scheduleEchoClear() {
      if (echoClearTimer) {
        clearTimeout(echoClearTimer);
      }
      echoRetryPending = true;
      echoClearTimer = setTimeout(function () {
        echoClearTimer = null;
        if (!echoRetryPending) {
          return;
        }
        echoRetryPending = false;
        echoRetryCount = 0;
        startFollower(true);
      }, Math.max(HEIGHT_ECHO_MS, echoActiveUntil - Date.now()) + 30);
    }

    // This window only ever resizes because the host applied a height, so a
    // resize here is our own echo: the page is legitimately shorter now, but
    // that is a consequence of the height we asked for, not new content
    // information. Accepting it would let a viewport-sized card walk itself down
    // to the floor. Width changes are handled by noteHostResize.
    function handleViewportResize() {
      var vp = noteViewport();
      if (!vp.changed) {
        return;
      }
      noteHostResize(vp.widthChanged);
    }

    // A host resize is visible twice: once as a window resize and once as the
    // body resizing. The first one consumes it, so the second must not be read as
    // a content change just because the metrics already look settled. A real
    // content change always comes with a DOM mutation, which marks itself.
    function handleBodyResize() {
      var vp = noteViewport();
      if (vp.changed) {
        noteHostResize(vp.widthChanged);
        return;
      }
      if (Date.now() < echoActiveUntil) {
        return;
      }
      markContentChanged();
    }

    window.triggerSlash = function (text) {
      pushLog('[triggerSlash] ' + String(text));
      if (window.FlutterCardLog && window.FlutterCardLog.postMessage) {
        window.FlutterCardLog.postMessage('[triggerSlash] ' + String(text));
      }
    };

    // Minimal SillyTavern surface so cards written against the desktop
    // extension API fail loudly in the log instead of throwing during load.
    if (!window.SillyTavern) {
      window.SillyTavern = {};
    }
    if (typeof window.SillyTavern.getContext !== 'function') {
      window.SillyTavern.getContext = function () {
        return {
          name: 'SillyTavern',
          chatId: 'flutter-host',
          characters: [],
          chat: [],
          chatMetadata: {},
          extensionSettings: {},
          powerUserSettings: {},
          variables: {},
          getRequestHeaders: function () { return {}; },
          saveSettingsDebounced: function () {},
          saveMetadata: function () {},
          eventSource: {},
          eventTypes: {},
          substituteParams: function (value) { return value; },
          renderExtensionTemplateAsync: function () {
            return Promise.resolve('');
          }
        };
      };
    }

    if (!window.TavernHelper) {
      window.TavernHelper = {
        getVariables: function () { return {}; },
        replaceVariables: function (value) { return value; },
        setVariables: function (variables, options) {
          pushLog('[TavernHelper.setVariables] ' + JSON.stringify(variables));
          return Promise.resolve();
        },
        insertOrAssignVariables: function (variables) {
          pushLog(
            '[TavernHelper.insertOrAssignVariables] ' + JSON.stringify(variables)
          );
          return Promise.resolve();
        },
        triggerSlash: window.triggerSlash,
        getLastMessageId: function () { return -1; },
        getChatMessages: function () { return []; },
        formatAsTavernRegexedString: function (value) { return value; }
      };
    }

    window.addEventListener('error', function (event) {
      pushLog('[window.error] ' + (event && event.message ? event.message : 'unknown'));
    });

    window.addEventListener('unhandledrejection', function (event) {
      var reason = event && event.reason ? event.reason : 'unknown';
      pushLog('[unhandledrejection] ' + String(reason));
    });

    var originalConsoleError = console.error;
    console.error = function () {
      try {
        var args = Array.prototype.slice.call(arguments);
        pushLog('[console.error] ' + args.join(' '));
      } catch (_) {}
      if (originalConsoleError) {
        originalConsoleError.apply(console, arguments);
      }
    };

    window.addEventListener('load', function () {
      markContentChanged();
      setTimeout(markContentChanged, 120);
      setTimeout(markContentChanged, 400);
      setTimeout(markContentChanged, 1000);
    });
    window.addEventListener('resize', handleViewportResize);
    window.addEventListener('click', function () {
      markContentChanged();
      setTimeout(markContentChanged, 180);
      setTimeout(markContentChanged, 420);
    });

    document.addEventListener('DOMContentLoaded', function () {
      var images = document.querySelectorAll('img');
      for (var i = 0; i < images.length; i++) {
        images[i].addEventListener('load', markContentChanged);
        images[i].addEventListener('error', markContentChanged);
      }
      markContentChanged();
    });

    if (window.MutationObserver) {
      window.addEventListener('DOMContentLoaded', function () {
        var body = document.body;
        if (!body) return;
        var mutationObserver = new MutationObserver(function () {
          markContentChanged();
        });
        mutationObserver.observe(body, {
          childList: true,
          subtree: true,
          attributes: true,
          characterData: true
        });
      });
    }

    // The body resizes for two different reasons, and they must not be confused:
    // the card's own content changed (only the body moved), or the host applied a
    // height (the viewport moved too). The viewport metrics are the only
    // reliable witness; timestamps are not, because a tab switch can be followed
    // by the host's resize within a frame or two.
    if (window.ResizeObserver) {
      var observer = new ResizeObserver(handleBodyResize);
      window.addEventListener('DOMContentLoaded', function () {
        if (document.body) observer.observe(document.body);
      });
    } else {
      setInterval(markContentChanged, 1000);
    }

    window.__frontendCardForceResize = markContentChanged;
  })();
</script>
''';

    if (hasHtmlTag) {
      if (RegExp(r'<head[\s>]', caseSensitive: false).hasMatch(trimmed)) {
        return _injectAfterFirstMatch(
          trimmed,
          RegExp(r'<head(\s[^>]*)?>', caseSensitive: false),
          '$hostStyle$hostScript',
        );
      }

      return _injectAfterFirstMatch(
        trimmed,
        RegExp(r'<html(\s[^>]*)?>', caseSensitive: false),
        '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">$hostStyle$hostScript</head>',
      );
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  $hostStyle
  $hostScript
  $extraScript
</head>
<body>
$trimmed
</body>
</html>
''';
  }

  static String _injectAfterFirstMatch(
    String source,
    RegExp pattern,
    String injection,
  ) {
    final match = pattern.firstMatch(source);
    if (match == null) {
      return source;
    }

    final matchedText = match.group(0) ?? '';
    return source.replaceFirst(matchedText, '$matchedText$injection');
  }
}
