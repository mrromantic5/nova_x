/*
 * NOVA X Dev Tools — page agent (3.11.0)
 * Injected into the inspected page only while Dev Tools is open (or after the
 * developer used it on this tab). Read/modify the page on request: DOM tree,
 * styles, storage, performance, audits. It never sends anything off the
 * phone; results go back to the app through the method's return value.
 */
(function () {
  'use strict';
  if (window.__nxdt && window.__nxdt.v === 3) return;
  var MAX_TEXT = 20000;

  function clip(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) + '…' : s; }

  // ── Node paths: child-element indices from <html> (stable within a page) ──
  function pathOf(el) {
    var p = [];
    while (el && el !== document.documentElement && el.parentNode) {
      var parent = el.parentNode, i = 0;
      if (parent.nodeType === 11 && parent.host) { // shadow root
        p.unshift(-1 - Array.prototype.indexOf.call(parent.childNodes, el)); el = parent.host; continue;
      }
      i = Array.prototype.indexOf.call(parent.childNodes, el);
      p.unshift(i); el = parent;
    }
    return p;
  }
  function nodeAt(path) {
    var n = document.documentElement;
    for (var k = 0; k < (path || []).length && n; k++) {
      var i = path[k];
      if (i < 0) { n = n.shadowRoot ? n.shadowRoot.childNodes[-1 - i] : null; }
      else n = n.childNodes[i];
    }
    return n || null;
  }
  function selectorOf(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id && document.querySelectorAll('#' + CSS.escape(el.id)).length === 1) return '#' + CSS.escape(el.id);
    var parts = [];
    while (el && el.nodeType === 1 && el !== document.documentElement) {
      var s = el.localName;
      if (el.id && document.querySelectorAll('#' + CSS.escape(el.id)).length === 1) { parts.unshift('#' + CSS.escape(el.id)); break; }
      var cls = Array.prototype.filter.call(el.classList || [], function (c) { return !/^\d/.test(c); }).slice(0, 2);
      if (cls.length) s += '.' + cls.map(function (c) { return CSS.escape(c); }).join('.');
      var p = el.parentElement;
      if (p) {
        var same = Array.prototype.filter.call(p.children, function (c) { return c.localName === el.localName; });
        if (same.length > 1) s += ':nth-of-type(' + (same.indexOf(el) + 1) + ')';
      }
      parts.unshift(s); el = p;
    }
    return parts.length ? 'html > ' + parts.join(' > ') : 'html';
  }
  function xpathOf(el) {
    var parts = [];
    while (el && el.nodeType === 1) {
      var i = 1, s = el.previousElementSibling;
      while (s) { if (s.localName === el.localName) i++; s = s.previousElementSibling; }
      parts.unshift(el.localName + '[' + i + ']'); el = el.parentElement;
    }
    return '/' + parts.join('/');
  }

  function summarize(n, path) {
    if (n.nodeType === 1) {
      var attrs = [];
      for (var i = 0; i < n.attributes.length && i < 12; i++) attrs.push([n.attributes[i].name, clip(n.attributes[i].value, 200)]);
      var kids = 0;
      for (var j = 0; j < n.childNodes.length; j++) { var c = n.childNodes[j]; if (c.nodeType === 1 || (c.nodeType === 3 && c.nodeValue.trim()) || c.nodeType === 8) kids++; }
      if (n.shadowRoot) kids += n.shadowRoot.childNodes.length;
      return { k: 'el', path: path, tag: n.localName, attrs: attrs, kids: kids, shadow: !!n.shadowRoot,
        text: kids === 1 && n.childNodes.length === 1 && n.firstChild.nodeType === 3 ? clip(n.firstChild.nodeValue.trim(), 80) : null };
    }
    if (n.nodeType === 3) return { k: 'text', path: path, text: clip(n.nodeValue.trim(), 300) };
    if (n.nodeType === 8) return { k: 'comment', path: path, text: clip(n.nodeValue.trim(), 200) };
    if (n.nodeType === 10) return { k: 'doctype', path: path, text: '<!DOCTYPE ' + n.name + '>' };
    return null;
  }

  function children(path) {
    var n = path && path.length ? nodeAt(path) : document.documentElement;
    if (!n) return { error: 'Node not found (the page changed). Refresh the tree.' };
    var out = [], base = path || [];
    if (!path || !path.length) { if (document.doctype) out.push({ k: 'doctype', path: [], text: '<!DOCTYPE ' + document.doctype.name + '>' }); out.push(summarize(n, [])); return { nodes: out }; }
    if (n.shadowRoot) for (var s = 0; s < n.shadowRoot.childNodes.length && out.length < 400; s++) { var sn = summarize(n.shadowRoot.childNodes[s], base.concat([-1 - s])); if (sn && !(sn.k === 'text' && !sn.text)) { sn.inShadow = true; out.push(sn); } }
    for (var i = 0; i < n.childNodes.length && out.length < 500; i++) {
      var c = n.childNodes[i];
      var x = summarize(c, base.concat([i]));
      if (x && !(x.k === 'text' && !x.text)) out.push(x);
    }
    return { nodes: out, more: n.childNodes.length > 500 };
  }

  var STYLE_PROPS = ['display', 'position', 'top', 'right', 'bottom', 'left', 'z-index', 'width', 'height', 'min-width', 'max-width',
    'min-height', 'max-height', 'margin', 'padding', 'border', 'border-radius', 'box-sizing', 'overflow', 'color', 'background-color',
    'background-image', 'opacity', 'font-family', 'font-size', 'font-weight', 'line-height', 'letter-spacing', 'text-align',
    'text-decoration', 'text-transform', 'white-space', 'flex', 'flex-direction', 'flex-wrap', 'justify-content', 'align-items',
    'align-content', 'gap', 'grid-template-columns', 'grid-template-rows', 'transform', 'transition', 'animation', 'box-shadow',
    'filter', 'visibility', 'cursor', 'pointer-events', 'object-fit', 'content'];

  function matchedRules(el) {
    var out = [];
    var sheets = document.styleSheets;
    for (var i = 0; i < sheets.length && out.length < 80; i++) {
      var sh = sheets[i], rules;
      try { rules = sh.cssRules; } catch (e) { continue; } // cross-origin sheet
      var src = sh.href ? sh.href.split('/').pop().split('?')[0] : (sh.ownerNode && sh.ownerNode.localName === 'style' ? '<style>' : 'inline');
      (function walk(list, media) {
        for (var r = 0; r < list.length && out.length < 80; r++) {
          var rule = list[r];
          if (rule.type === 1) {
            try { if (el.matches(rule.selectorText)) out.push({ selector: rule.selectorText, css: clip(rule.style.cssText, 3000), source: src, media: media || '' }); } catch (e) {}
          } else if (rule.cssRules && (rule.type === 4 || rule.type === 12 || rule.type === 0)) {
            var ok = rule.type !== 4 || window.matchMedia(rule.media.mediaText).matches;
            if (ok) walk(rule.cssRules, rule.media ? '@media ' + rule.media.mediaText : media);
          }
        }
      })(rules, '');
    }
    return out.reverse(); // most specific/last first (roughly)
  }

  function a11y(el) {
    var role = el.getAttribute('role') || ({ a: el.hasAttribute('href') ? 'link' : '', button: 'button', input: (el.type === 'checkbox' ? 'checkbox' : el.type === 'radio' ? 'radio' : el.type === 'submit' || el.type === 'button' ? 'button' : 'textbox'),
      img: 'img', nav: 'navigation', main: 'main', header: 'banner', footer: 'contentinfo', h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading',
      h5: 'heading', h6: 'heading', ul: 'list', ol: 'list', li: 'listitem', select: 'combobox', textarea: 'textbox', form: 'form', table: 'table' }[el.localName] || '');
    return { role: role, name: clip(accName(el), 200), focusable: el.tabIndex >= 0, hidden: el.getAttribute('aria-hidden') === 'true' };
  }
  function accName(el) {
    if (el.getAttribute('aria-label')) return el.getAttribute('aria-label');
    var lb = el.getAttribute('aria-labelledby');
    if (lb) return lb.split(/\s+/).map(function (id) { var x = document.getElementById(id); return x ? x.textContent.trim() : ''; }).join(' ');
    if (el.localName === 'img') return el.getAttribute('alt') || '';
    if (el.id) { var l = document.querySelector('label[for="' + CSS.escape(el.id) + '"]'); if (l) return l.textContent.trim(); }
    if (el.closest && el.closest('label')) return el.closest('label').textContent.trim();
    if (el.getAttribute('title')) return el.getAttribute('title');
    if (el.getAttribute('placeholder')) return el.getAttribute('placeholder');
    if (/^(input)$/.test(el.localName) && (el.type === 'submit' || el.type === 'button')) return el.value || '';
    return (el.textContent || '').trim().replace(/\s+/g, ' ');
  }

  function details(path) {
    var el = nodeAt(path);
    if (!el) return { error: 'Node not found (the page changed). Refresh the tree.' };
    window.$0 = el;
    if (el.nodeType !== 1) return { k: el.nodeType === 3 ? 'text' : 'other', text: clip(el.nodeValue, MAX_TEXT) };
    var cs = getComputedStyle(el), styles = [];
    STYLE_PROPS.forEach(function (p) { var v = cs.getPropertyValue(p); if (v !== '') styles.push([p, v]); });
    var r = el.getBoundingClientRect();
    function px(v) { return parseFloat(v) || 0; }
    var box = {
      x: Math.round(r.left + scrollX), y: Math.round(r.top + scrollY), w: Math.round(r.width * 100) / 100, h: Math.round(r.height * 100) / 100,
      margin: [px(cs.marginTop), px(cs.marginRight), px(cs.marginBottom), px(cs.marginLeft)],
      border: [px(cs.borderTopWidth), px(cs.borderRightWidth), px(cs.borderBottomWidth), px(cs.borderLeftWidth)],
      padding: [px(cs.paddingTop), px(cs.paddingRight), px(cs.paddingBottom), px(cs.paddingLeft)]
    };
    var attrs = [];
    for (var i = 0; i < el.attributes.length; i++) attrs.push([el.attributes[i].name, el.attributes[i].value]);
    return {
      k: 'el', tag: el.localName, attrs: attrs, outer: clip(el.outerHTML, MAX_TEXT), outerLength: el.outerHTML.length,
      inline: el.getAttribute('style') || '', styles: styles, rules: matchedRules(el), box: box,
      selector: selectorOf(el), xpath: xpathOf(el), a11y: a11y(el), childElements: el.childElementCount,
      listeners: Object.keys(el).filter(function (k) { return /^on/.test(k) && typeof el[k] === 'function'; })
        .concat(Array.prototype.filter.call(el.attributes, function (a) { return /^on/.test(a.name); }).map(function (a) { return a.name + ' (attribute)'; }))
    };
  }

  // ── Highlight overlay ──
  var overlay = null;
  function highlight(path) {
    unhighlight();
    var el = nodeAt(path);
    if (!el || el.nodeType !== 1) return false;
    var r = el.getBoundingClientRect(), cs = getComputedStyle(el);
    function px(v) { return parseFloat(v) || 0; }
    overlay = document.createElement('div');
    overlay.setAttribute('data-nxdt', '1');
    overlay.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;left:0;top:0;width:0;height:0';
    function box(x, y, w, h, bg, border) {
      var d = document.createElement('div');
      d.style.cssText = 'position:fixed;left:' + x + 'px;top:' + y + 'px;width:' + Math.max(0, w) + 'px;height:' + Math.max(0, h) + 'px;background:' + bg + ';' + (border || '');
      overlay.appendChild(d);
    }
    var m = [px(cs.marginTop), px(cs.marginRight), px(cs.marginBottom), px(cs.marginLeft)];
    var p = [px(cs.paddingTop), px(cs.paddingRight), px(cs.paddingBottom), px(cs.paddingLeft)];
    var b = [px(cs.borderTopWidth), px(cs.borderRightWidth), px(cs.borderBottomWidth), px(cs.borderLeftWidth)];
    box(r.left - m[3], r.top - m[0], r.width + m[1] + m[3], r.height + m[0] + m[2], 'rgba(246,178,107,.35)');
    box(r.left, r.top, r.width, r.height, 'rgba(255,229,153,.35)');
    box(r.left + b[3], r.top + b[0], r.width - b[1] - b[3], r.height - b[0] - b[2], 'rgba(147,196,125,.45)');
    box(r.left + b[3] + p[3], r.top + b[0] + p[0], r.width - b[1] - b[3] - p[1] - p[3], r.height - b[0] - b[2] - p[0] - p[2], 'rgba(111,168,220,.55)');
    var tip = document.createElement('div');
    tip.textContent = el.localName + (el.id ? '#' + el.id : '') + (el.classList.length ? '.' + Array.prototype.slice.call(el.classList, 0, 2).join('.') : '') + '  ' + Math.round(r.width) + ' × ' + Math.round(r.height);
    tip.style.cssText = 'position:fixed;left:' + Math.max(4, r.left) + 'px;top:' + (r.top > 30 ? r.top - 26 : r.bottom + 4) + 'px;background:#1b2b45;color:#fff;font:12px/1.4 monospace;padding:3px 7px;border-radius:4px;box-shadow:0 2px 8px rgba(0,0,0,.4);white-space:nowrap';
    overlay.appendChild(tip);
    document.documentElement.appendChild(overlay);
    return true;
  }
  function unhighlight() { if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay); overlay = null; return true; }

  // ── Tap-to-inspect ──
  var picking = null;
  function pick() {
    cancelPick();
    var last = null;
    function move(e) {
      var t = e.touches ? e.touches[0] : e;
      var el = document.elementFromPoint(t.clientX, t.clientY);
      if (el && el !== last && !(el.closest && el.closest('[data-nxdt]'))) { last = el; highlight(pathOf(el)); }
    }
    function done(e) {
      e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation && e.stopImmediatePropagation();
      var t = e.changedTouches ? e.changedTouches[0] : e;
      var el = document.elementFromPoint(t.clientX, t.clientY) || last;
      cancelPick();
      if (el) {
        highlight(pathOf(el)); setTimeout(unhighlight, 1200);
        try { window.flutter_inappwebview.callHandler('novaxInspect', { path: pathOf(el), selector: selectorOf(el) }); } catch (x) {}
      }
    }
    function block(e) { e.preventDefault(); e.stopPropagation(); }
    picking = { move: move, done: done, block: block };
    document.addEventListener('touchmove', move, { capture: true, passive: true });
    document.addEventListener('touchstart', move, { capture: true, passive: true });
    document.addEventListener('touchend', done, { capture: true, passive: false });
    document.addEventListener('click', block, true);
    document.addEventListener('mousemove', move, true);
    document.addEventListener('mouseup', done, true);
    var hint = document.createElement('div');
    hint.setAttribute('data-nxdt', '1');
    hint.textContent = 'Tap an element to inspect it';
    hint.style.cssText = 'position:fixed;left:50%;top:12px;transform:translateX(-50%);z-index:2147483647;background:#1565c0;color:#fff;font:600 13px system-ui,sans-serif;padding:8px 14px;border-radius:20px;box-shadow:0 4px 14px rgba(0,0,0,.35);pointer-events:none';
    document.documentElement.appendChild(hint); picking.hint = hint;
    return true;
  }
  function cancelPick() {
    if (!picking) return false;
    document.removeEventListener('touchmove', picking.move, true);
    document.removeEventListener('touchstart', picking.move, true);
    document.removeEventListener('touchend', picking.done, true);
    document.removeEventListener('mousemove', picking.move, true);
    document.removeEventListener('mouseup', picking.done, true);
    var b = picking.block; setTimeout(function () { document.removeEventListener('click', b, true); }, 400);
    if (picking.hint && picking.hint.parentNode) picking.hint.parentNode.removeChild(picking.hint);
    picking = null; return true;
  }

  // ── Editing ──
  function edit(a) {
    var el = nodeAt(a.path);
    if (!el) return { error: 'Node not found' };
    switch (a.op) {
      case 'setAttr': el.setAttribute(a.name, a.value); break;
      case 'removeAttr': el.removeAttribute(a.name); break;
      case 'outer':
        var t = document.createElement('template'); t.innerHTML = a.html;
        var frag = t.content; var first = frag.firstChild; el.replaceWith(frag);
        return { ok: true, path: first ? pathOf(first) : a.path.slice(0, -1) };
      case 'text': el.textContent = a.value; break;
      case 'style': el.setAttribute('style', a.value); break;
      case 'delete': el.remove(); return { ok: true, path: a.path.slice(0, -1) };
      case 'hide': el.style.setProperty('display', 'none', 'important'); break;
      case 'scroll': el.scrollIntoView({ block: 'center', behavior: 'smooth' }); break;
      case 'duplicate': el.after(el.cloneNode(true)); break;
      case 'click': el.click(); break;
      case 'focus': el.focus(); break;
    }
    return { ok: true, path: a.path };
  }

  function query(sel) {
    var list;
    try { list = document.querySelectorAll(sel); } catch (e) { return { error: 'Invalid selector: ' + e.message }; }
    var out = [];
    for (var i = 0; i < list.length && i < 100; i++) out.push({ path: pathOf(list[i]), label: selectorOf(list[i]) });
    return { count: list.length, items: out };
  }

  function search(text) {
    // Find elements whose tag/id/class/attribute or own text contains the text.
    var t = String(text).toLowerCase(), out = [], all = document.getElementsByTagName('*');
    for (var i = 0; i < all.length && out.length < 100; i++) {
      var el = all[i];
      if (el.closest('[data-nxdt]')) continue;
      var own = '';
      for (var c = 0; c < el.childNodes.length; c++) if (el.childNodes[c].nodeType === 3) own += el.childNodes[c].nodeValue;
      var hay = el.localName + ' ' + (el.id || '') + ' ' + (el.getAttribute('class') || '') + ' ' + own;
      for (var a = 0; a < el.attributes.length; a++) hay += ' ' + el.attributes[a].value;
      if (hay.toLowerCase().indexOf(t) >= 0) out.push({ path: pathOf(el), label: selectorOf(el), text: clip(own.trim(), 80) });
    }
    return { items: out };
  }

  // ── Console REPL helpers: previews + expandable handles ──
  var handles = {}, hid = 0;
  function keep(v) { var id = ++hid; handles[id] = v; if (hid > 2000) { delete handles[hid - 2000]; } return id; }
  function typeOf(v) {
    if (v === null) return 'null';
    if (Array.isArray(v)) return 'array';
    if (v instanceof Element) return 'element';
    if (v instanceof Error) return 'error';
    if (v instanceof Date) return 'date';
    if (v instanceof RegExp) return 'regexp';
    if (v instanceof Map) return 'map';
    if (v instanceof Set) return 'set';
    if (typeof Promise !== 'undefined' && v instanceof Promise) return 'promise';
    return typeof v;
  }
  function short(v, depth) {
    var t = typeOf(v);
    try {
      switch (t) {
        case 'string': return depth ? JSON.stringify(clip(v, 200)) : clip(v, MAX_TEXT);
        case 'number': case 'boolean': case 'undefined': case 'null': case 'bigint': case 'symbol': return String(v) + (t === 'bigint' ? 'n' : '');
        case 'function': return 'ƒ ' + (v.name || 'anonymous') + '(' + (String(v).match(/^[^(]*\(([^)]*)\)/) || ['', ''])[1] + ')';
        case 'element': return '<' + v.localName + (v.id ? '#' + v.id : '') + (v.classList.length ? '.' + Array.prototype.join.call(v.classList, '.') : '') + '>';
        case 'error': return (v.stack || (v.name + ': ' + v.message));
        case 'date': return v.toISOString();
        case 'regexp': return String(v);
        case 'map': return 'Map(' + v.size + ')';
        case 'set': return 'Set(' + v.size + ')';
        case 'promise': return 'Promise';
        case 'array':
          if (depth > 1) return 'Array(' + v.length + ')';
          return '(' + v.length + ') [' + v.slice(0, 20).map(function (x) { return short(x, (depth || 0) + 1); }).join(', ') + (v.length > 20 ? ', …' : '') + ']';
        default:
          if (depth > 1) return (v.constructor && v.constructor.name !== 'Object' ? v.constructor.name + ' ' : '') + '{…}';
          var ks = Object.keys(v).slice(0, 12);
          return (v.constructor && v.constructor.name && v.constructor.name !== 'Object' ? v.constructor.name + ' ' : '') + '{' + ks.map(function (k) { var x; try { x = v[k]; } catch (e) { x = '?'; } return k + ': ' + short(x, (depth || 0) + 1); }).join(', ') + (Object.keys(v).length > 12 ? ', …' : '') + '}';
      }
    } catch (e) { return '[' + t + ']'; }
  }
  function preview(v) {
    var t = typeOf(v), expandable = (t === 'object' || t === 'array' || t === 'map' || t === 'set' || t === 'element' || t === 'function' || t === 'error');
    var o = { type: t, text: short(v, 0) };
    if (expandable) o.handle = keep(v);
    if (t === 'element') o.path = pathOf(v);
    return o;
  }
  function props(id) {
    var v = handles[id];
    if (v === undefined) return { error: 'Value is no longer available' };
    var out = [];
    function add(k, x) { var p = preview(x); p.key = String(k); out.push(p); }
    try {
      if (v instanceof Map) { v.forEach(function (x, k) { if (out.length < 200) add(short(k, 1), x); }); }
      else if (v instanceof Set) { var i = 0; v.forEach(function (x) { if (out.length < 200) add(i++, x); }); }
      else if (v instanceof Element) {
        ['id', 'className', 'tagName', 'innerText', 'value', 'href', 'src', 'dataset', 'style', 'attributes', 'children', 'parentElement', 'offsetWidth', 'offsetHeight']
          .forEach(function (k) { if (k in v) add(k, v[k]); });
      } else {
        var keys = Object.getOwnPropertyNames(v).slice(0, 300);
        keys.forEach(function (k) { if (out.length < 300) { var x; try { x = v[k]; } catch (e) { x = e; } add(k, x); } });
        var proto = Object.getPrototypeOf(v);
        if (proto && proto !== Object.prototype && proto !== Array.prototype) add('[[Prototype]]', proto);
      }
    } catch (e) { return { error: String(e) }; }
    return { items: out };
  }

  // ── Storage ──
  function storage(kind) {
    var s = kind === 'session' ? sessionStorage : localStorage, out = [];
    try { for (var i = 0; i < s.length && i < 2000; i++) { var k = s.key(i); out.push([k, clip(s.getItem(k), 100000)]); } }
    catch (e) { return { error: 'Not available on this page: ' + e.message }; }
    return { items: out };
  }
  function storageSet(a) {
    var s = a.kind === 'session' ? sessionStorage : localStorage;
    try {
      if (a.op === 'set') { if (a.oldKey && a.oldKey !== a.key) s.removeItem(a.oldKey); s.setItem(a.key, a.value); }
      else if (a.op === 'remove') s.removeItem(a.key);
      else if (a.op === 'clear') s.clear();
      return { ok: true };
    } catch (e) { return { error: e.message }; }
  }
  function cookies() {
    return { items: (document.cookie ? document.cookie.split(/;\s*/) : []).map(function (c) { var i = c.indexOf('='); return [decodeURIComponentSafe(c.slice(0, i)), decodeURIComponentSafe(c.slice(i + 1))]; }) };
  }
  function decodeURIComponentSafe(s) { try { return decodeURIComponent(s); } catch (e) { return s; } }
  function cookieDelete(name) {
    var host = location.hostname.split('.'), paths = location.pathname.split('/');
    for (var i = 0; i < host.length; i++) {
      var d = host.slice(i).join('.'), p = '';
      for (var j = 0; j < paths.length; j++) {
        p += (j ? '/' : '') + paths[j];
        document.cookie = encodeURIComponent(name) + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=' + (p || '/') + '; domain=' + d;
        document.cookie = encodeURIComponent(name) + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=' + (p || '/');
      }
    }
    return { ok: true };
  }
  function cookieSet(a) { document.cookie = encodeURIComponent(a.name) + '=' + encodeURIComponent(a.value) + '; path=/' + (location.protocol === 'https:' ? '; secure' : '') + '; samesite=lax'; return { ok: true }; }

  async function idb() {
    if (!window.indexedDB || !indexedDB.databases) return { error: 'IndexedDB listing is not supported here' };
    var dbs = await indexedDB.databases(), out = [];
    for (var i = 0; i < dbs.length && i < 30; i++) {
      var info = { name: dbs[i].name, version: dbs[i].version, stores: [] };
      try {
        var db = await new Promise(function (res, rej) { var r = indexedDB.open(dbs[i].name); r.onsuccess = function () { res(r.result); }; r.onerror = function () { rej(r.error); }; r.onupgradeneeded = function () { r.transaction.abort(); rej(new Error('missing')); }; });
        for (var s = 0; s < db.objectStoreNames.length; s++) {
          var name = db.objectStoreNames[s];
          var count = await new Promise(function (res) { try { var q = db.transaction(name, 'readonly').objectStore(name).count(); q.onsuccess = function () { res(q.result); }; q.onerror = function () { res(-1); }; } catch (e) { res(-1); } });
          info.stores.push({ name: name, count: count });
        }
        db.close();
      } catch (e) { info.error = String(e.message || e); }
      out.push(info);
    }
    return { items: out };
  }
  async function idbRecords(a) {
    var db = await new Promise(function (res, rej) { var r = indexedDB.open(a.db); r.onsuccess = function () { res(r.result); }; r.onerror = function () { rej(r.error); }; });
    var out = [];
    await new Promise(function (res) {
      try {
        var cur = db.transaction(a.store, 'readonly').objectStore(a.store).openCursor();
        cur.onsuccess = function () { var c = cur.result; if (c && out.length < 100) { var v; try { v = JSON.stringify(c.value); } catch (e) { v = String(c.value); } out.push([short(c.key, 1), clip(v, 4000)]); c.continue(); } else res(); };
        cur.onerror = function () { res(); };
      } catch (e) { res(); }
    });
    db.close();
    return { items: out };
  }
  async function cachesList() {
    if (!window.caches) return { error: 'Cache Storage needs a secure (https) page' };
    var keys = await caches.keys(), out = [];
    for (var i = 0; i < keys.length && i < 30; i++) {
      var c = await caches.open(keys[i]), reqs = await c.keys();
      out.push({ name: keys[i], count: reqs.length, urls: reqs.slice(0, 200).map(function (r) { return r.url; }) });
    }
    return { items: out };
  }
  async function workers() {
    if (!navigator.serviceWorker) return { error: 'Service workers need a secure (https) page' };
    var regs = await navigator.serviceWorker.getRegistrations();
    return { items: regs.map(function (r) { var w = r.active || r.waiting || r.installing; return { scope: r.scope, script: w ? w.scriptURL : '', state: w ? w.state : 'none', controlling: !!navigator.serviceWorker.controller }; }) };
  }
  async function workerAction(a) {
    var regs = await navigator.serviceWorker.getRegistrations();
    for (var i = 0; i < regs.length; i++) if (regs[i].scope === a.scope) { if (a.op === 'unregister') await regs[i].unregister(); else await regs[i].update(); }
    return { ok: true };
  }
  async function manifest() {
    var l = document.querySelector('link[rel~="manifest"]');
    if (!l) return { error: 'This page has no web app manifest (<link rel="manifest">).' };
    try { var r = await fetch(l.href, { credentials: 'include' }); var t = await r.text(); return { url: l.href, text: clip(t, 200000) }; }
    catch (e) { return { url: l.href, error: 'Could not load the manifest: ' + e.message }; }
  }
  async function estimate() {
    try { var e = await navigator.storage.estimate(); return { usage: e.usage || 0, quota: e.quota || 0, details: e.usageDetails || null }; } catch (x) { return { error: 'Not available' }; }
  }
  async function clearSite() {
    var done = [];
    try { localStorage.clear(); done.push('local storage'); } catch (e) {}
    try { sessionStorage.clear(); done.push('session storage'); } catch (e) {}
    try { cookies().items.forEach(function (c) { cookieDelete(c[0]); }); done.push('cookies (page-readable)'); } catch (e) {}
    try { if (window.caches) { var k = await caches.keys(); await Promise.all(k.map(function (n) { return caches.delete(n); })); done.push('cache storage'); } } catch (e) {}
    try { if (indexedDB.databases) { var d = await indexedDB.databases(); d.forEach(function (x) { indexedDB.deleteDatabase(x.name); }); done.push('IndexedDB'); } } catch (e) {}
    try { if (navigator.serviceWorker) { var r = await navigator.serviceWorker.getRegistrations(); await Promise.all(r.map(function (x) { return x.unregister(); })); done.push('service workers'); } } catch (e) {}
    return { done: done };
  }

  // ── Sources ──
  function resources() {
    var out = [], seen = {};
    function add(url, type, size, ms) { if (!url || seen[url]) return; seen[url] = 1; out.push({ url: url, type: type, size: size || 0, ms: ms || 0 }); }
    add(location.href, 'document', 0, 0);
    performance.getEntriesByType('resource').forEach(function (e) {
      var t = e.initiatorType, ext = (e.name.split('?')[0].split('.').pop() || '').toLowerCase();
      var type = /^(js|mjs)$/.test(ext) || t === 'script' ? 'script' : ext === 'css' || (t === 'link' && /css/.test(ext)) ? 'stylesheet'
        : /^(png|jpe?g|gif|webp|svg|avif|ico)$/.test(ext) || t === 'img' ? 'image' : /^(woff2?|ttf|otf)$/.test(ext) ? 'font'
        : t === 'fetch' || t === 'xmlhttprequest' ? 'fetch' : t === 'iframe' ? 'document' : 'other';
      add(e.name, type, e.transferSize || e.encodedBodySize || 0, Math.round(e.duration));
    });
    Array.prototype.forEach.call(document.scripts, function (s) { if (s.src) add(s.src, 'script'); });
    Array.prototype.forEach.call(document.querySelectorAll('link[rel~="stylesheet"]'), function (l) { add(l.href, 'stylesheet'); });
    var inline = [];
    Array.prototype.forEach.call(document.scripts, function (s, i) { if (!s.src && s.textContent.trim()) inline.push({ kind: 'script', index: i, size: s.textContent.length, type: s.type || 'text/javascript' }); });
    Array.prototype.forEach.call(document.querySelectorAll('style'), function (s, i) { if (s.textContent.trim()) inline.push({ kind: 'style', index: i, size: s.textContent.length }); });
    return { items: out, inline: inline };
  }
  function inlineSource(a) {
    var list = a.kind === 'style' ? document.querySelectorAll('style') : document.scripts;
    var el = list[a.index];
    return el ? { text: clip(el.textContent, 3000000) } : { error: 'Not found' };
  }
  async function fetchText(url) {
    if (url === location.href) return { text: clip('<!DOCTYPE html>\n' + document.documentElement.outerHTML, 3000000), live: true };
    try {
      var r = await fetch(url, { credentials: 'include', cache: 'force-cache' });
      var ct = r.headers.get('content-type') || '';
      if (/image|font|video|audio|octet-stream|wasm/.test(ct)) return { error: 'binary', contentType: ct };
      var t = await r.text();
      return { text: clip(t, 3000000), status: r.status, contentType: ct };
    } catch (e) { return { error: 'blocked', message: String(e.message || e) }; }
  }

  // ── Performance ──
  async function perf() {
    var nav = performance.getEntriesByType('navigation')[0] || {};
    var paints = {}; performance.getEntriesByType('paint').forEach(function (p) { paints[p.name] = Math.round(p.startTime); });
    function observe(type) {
      return new Promise(function (res) {
        var list = [];
        try {
          var po = new PerformanceObserver(function (l) { list = list.concat(l.getEntries()); });
          po.observe({ type: type, buffered: true });
          setTimeout(function () { try { po.disconnect(); } catch (e) {} res(list); }, 250);
        } catch (e) { res(list); }
      });
    }
    var lcpList = await observe('largest-contentful-paint');
    var cls = 0, shifts = await observe('layout-shift');
    // session windows (Web Vitals definition, simplified)
    var win = 0, last = 0, first = 0;
    shifts.forEach(function (s) { if (s.hadRecentInput) return; if (s.startTime - last > 1000 || s.startTime - first > 5000) { win = 0; first = s.startTime; } win += s.value; last = s.startTime; cls = Math.max(cls, win); });
    var longTasks = await observe('longtask');
    var lcpEntry = lcpList[lcpList.length - 1];
    var byType = {};
    performance.getEntriesByType('resource').forEach(function (e) {
      var t = e.initiatorType || 'other';
      var b = byType[t] || (byType[t] = { count: 0, bytes: 0, ms: 0 });
      b.count++; b.bytes += e.transferSize || 0; b.ms = Math.max(b.ms, Math.round(e.duration));
    });
    var slow = performance.getEntriesByType('resource').slice().sort(function (a, b) { return b.duration - a.duration; }).slice(0, 15)
      .map(function (e) { return { url: e.name, type: e.initiatorType, ms: Math.round(e.duration), bytes: e.transferSize || 0, start: Math.round(e.startTime) }; });
    var mem = performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize, limit: performance.memory.jsHeapSizeLimit } : null;
    return {
      ttfb: nav.responseStart ? Math.round(nav.responseStart - (nav.startTime || 0)) : null,
      dns: nav.domainLookupEnd != null ? Math.round(nav.domainLookupEnd - nav.domainLookupStart) : null,
      tcp: nav.connectEnd != null ? Math.round(nav.connectEnd - nav.connectStart) : null,
      tls: nav.secureConnectionStart ? Math.round(nav.connectEnd - nav.secureConnectionStart) : 0,
      request: nav.responseStart ? Math.round(nav.responseStart - nav.requestStart) : null,
      download: nav.responseEnd ? Math.round(nav.responseEnd - nav.responseStart) : null,
      domInteractive: nav.domInteractive ? Math.round(nav.domInteractive) : null,
      dcl: nav.domContentLoadedEventEnd ? Math.round(nav.domContentLoadedEventEnd) : null,
      load: nav.loadEventEnd ? Math.round(nav.loadEventEnd) : null,
      fp: paints['first-paint'] || null, fcp: paints['first-contentful-paint'] || null,
      lcp: lcpEntry ? Math.round(lcpEntry.startTime) : null,
      lcpElement: lcpEntry && lcpEntry.element ? { label: selectorOf(lcpEntry.element), path: pathOf(lcpEntry.element) } : null,
      cls: Math.round(cls * 1000) / 1000,
      longTasks: longTasks.length, blocking: longTasks.reduce(function (s, t) { return s + Math.max(0, t.duration - 50); }, 0),
      transfer: nav.transferSize || 0, docSize: nav.decodedBodySize || 0,
      protocol: nav.nextHopProtocol || '',
      requests: performance.getEntriesByType('resource').length + 1,
      byType: byType, slow: slow, memory: mem,
      dom: document.getElementsByTagName('*').length,
      depth: (function () { var max = 0; (function walk(n, d) { if (d > max) max = d; if (d > 60) return; for (var c = n.firstElementChild; c; c = c.nextElementSibling) walk(c, d + 1); })(document.documentElement, 1); return max; })()
    };
  }

  // ── Audits (Lighthouse-style, run on the page as it is now) ──
  function lum(c) {
    var m = String(c).match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?/);
    if (!m) return null;
    var a = m[4] === undefined ? 1 : parseFloat(m[4]);
    var rgb = [m[1], m[2], m[3]].map(function (v) { v = v / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
    return { l: 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2], a: a };
  }
  function bgOf(el) {
    while (el && el.nodeType === 1) {
      var cs = getComputedStyle(el);
      if (cs.backgroundImage && cs.backgroundImage !== 'none') return null; // can't know
      var b = lum(cs.backgroundColor);
      if (b && b.a > 0.9) return b.l;
      el = el.parentElement;
    }
    return 1; // white canvas
  }
  async function audit() {
    var A = [];
    function add(cat, id, title, pass, weight, detail, items) { A.push({ cat: cat, id: id, title: title, pass: !!pass, weight: weight || 1, detail: detail || '', items: (items || []).slice(0, 30) }); }
    function els(sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); }
    function it(el, note) { return { label: selectorOf(el), path: pathOf(el), note: note || '' }; }
    var https = location.protocol === 'https:';

    // SEO
    var title = document.title.trim();
    add('seo', 'title', 'Document has a <title>', title.length > 0, 3, title ? '“' + clip(title, 80) + '” (' + title.length + ' characters)' : 'Add a descriptive <title>.');
    var desc = document.querySelector('meta[name="description"]');
    add('seo', 'meta-description', 'Has a meta description', desc && desc.content.trim().length >= 50, 3, desc ? desc.content.trim().length + ' characters (aim for 50–160)' : 'Add <meta name="description" content="…">.');
    var vp = document.querySelector('meta[name="viewport"]');
    add('seo', 'viewport', 'Has a mobile viewport', vp && /width=device-width/.test(vp.content), 3, vp ? vp.content : 'Add <meta name="viewport" content="width=device-width, initial-scale=1">.');
    var h1 = els('h1');
    add('seo', 'h1', 'Exactly one <h1>', h1.length === 1, 1, h1.length + ' found', h1.slice(1).map(function (e) { return it(e); }));
    var canon = document.querySelector('link[rel="canonical"]');
    add('seo', 'canonical', 'Has a canonical URL', !!canon, 1, canon ? canon.href : 'Add <link rel="canonical" href="…">.');
    var robots = document.querySelector('meta[name="robots"]');
    add('seo', 'indexable', 'Page can be indexed', !(robots && /noindex/i.test(robots.content)), 3, robots ? 'robots: ' + robots.content : 'No robots blocking');
    var badLinks = els('a[href]').filter(function (a) { return !(a.textContent.trim() || a.getAttribute('aria-label') || a.querySelector('img[alt]:not([alt=""])')); });
    add('seo', 'link-text', 'Links have descriptive text', badLinks.length === 0, 1, badLinks.length + ' links without text', badLinks.map(function (e) { return it(e); }));
    add('seo', 'lang', '<html> has a lang attribute', !!document.documentElement.lang, 1, document.documentElement.lang || 'Add <html lang="en">.');
    var og = document.querySelector('meta[property="og:title"]');
    add('seo', 'open-graph', 'Has Open Graph tags (link previews)', !!og, 1, og ? 'og:title present' : 'Add og:title, og:description, og:image.');
    add('seo', 'structured-data', 'Has structured data (JSON-LD)', !!document.querySelector('script[type="application/ld+json"]'), 1, '');

    // Accessibility
    var noAlt = els('img').filter(function (i) { return !i.hasAttribute('alt'); });
    add('a11y', 'image-alt', 'Images have alt text', noAlt.length === 0, 3, noAlt.length + ' images without alt', noAlt.map(function (e) { return it(e, e.currentSrc || e.src); }));
    var unnamedBtn = els('button, [role="button"], input[type="submit"], input[type="button"]').filter(function (b) { return !accName(b).trim(); });
    add('a11y', 'button-name', 'Buttons have an accessible name', unnamedBtn.length === 0, 3, unnamedBtn.length + ' buttons without a name', unnamedBtn.map(function (e) { return it(e); }));
    var unlabeled = els('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), select, textarea').filter(function (i) { return !accName(i).trim(); });
    add('a11y', 'label', 'Form fields have labels', unlabeled.length === 0, 3, unlabeled.length + ' fields without a label', unlabeled.map(function (e) { return it(e); }));
    add('a11y', 'html-lang', '<html> has a lang attribute', !!document.documentElement.lang, 2, '');
    var ids = {}, dup = [];
    els('[id]').forEach(function (e) { if (ids[e.id]) dup.push(e); ids[e.id] = 1; });
    add('a11y', 'duplicate-id', 'IDs are unique', dup.length === 0, 1, dup.length + ' duplicate IDs', dup.map(function (e) { return it(e, '#' + e.id); }));
    var tabpos = els('[tabindex]').filter(function (e) { return parseInt(e.getAttribute('tabindex'), 10) > 0; });
    add('a11y', 'tabindex', 'No positive tabindex', tabpos.length === 0, 1, tabpos.length + ' elements', tabpos.map(function (e) { return it(e); }));
    var levels = els('h1,h2,h3,h4,h5,h6').map(function (h) { return +h.localName[1]; }), skip = [];
    for (var i = 1; i < levels.length; i++) if (levels[i] > levels[i - 1] + 1) skip.push(i);
    add('a11y', 'heading-order', 'Headings go down one level at a time', skip.length === 0, 1, skip.length ? skip.length + ' skipped levels' : '');
    if (vp) add('a11y', 'zoom', 'Users can zoom', !/user-scalable\s*=\s*(no|0)|maximum-scale\s*=\s*1(\.0)?\b/.test(vp.content), 2, vp.content);
    // contrast (sampled)
    var low = [];
    var texts = els('p, span, a, li, td, th, label, button, h1, h2, h3, h4, h5, h6, small, strong, em, div').filter(function (e) {
      for (var c = e.firstChild; c; c = c.nextSibling) if (c.nodeType === 3 && c.nodeValue.trim().length > 2) return true; return false;
    }).slice(0, 400);
    texts.forEach(function (e) {
      var r = e.getBoundingClientRect(); if (!r.width || !r.height) return;
      var cs = getComputedStyle(e); if (cs.visibility === 'hidden' || +cs.opacity === 0) return;
      var fg = lum(cs.color), bg = bgOf(e);
      if (!fg || bg == null) return;
      var L1 = Math.max(fg.l, bg), L2 = Math.min(fg.l, bg), ratio = (L1 + 0.05) / (L2 + 0.05);
      var large = parseFloat(cs.fontSize) >= 24 || (parseFloat(cs.fontSize) >= 18.66 && +cs.fontWeight >= 700);
      if (ratio < (large ? 3 : 4.5)) low.push(it(e, ratio.toFixed(2) + ':1'));
    });
    add('a11y', 'color-contrast', 'Text has enough contrast', low.length === 0, 3, low.length + ' text elements below WCAG AA', low);

    // Best practices
    add('best', 'https', 'Uses HTTPS', https, 3, location.protocol);
    var mixed = https ? performance.getEntriesByType('resource').filter(function (e) { return /^http:/.test(e.name); }).map(function (e) { return { label: e.name, note: e.initiatorType }; }) : [];
    add('best', 'mixed-content', 'No mixed (http) content', mixed.length === 0, 3, mixed.length + ' insecure requests', mixed);
    var blank = els('a[target="_blank"]').filter(function (a) { return !/noopener|noreferrer/.test(a.rel); });
    add('best', 'noopener', 'External links use rel="noopener"', blank.length === 0, 1, blank.length + ' links', blank.map(function (e) { return it(e, e.href); }));
    add('best', 'doctype', 'Has <!DOCTYPE html>', !!document.doctype && document.doctype.name === 'html', 1, '');
    add('best', 'charset', 'Declares a charset', !!document.querySelector('meta[charset], meta[http-equiv="Content-Type" i]'), 1, document.characterSet);
    var big = els('img').filter(function (im) { return im.naturalWidth > 0 && im.clientWidth > 0 && im.naturalWidth > im.clientWidth * devicePixelRatio * 2; });
    add('best', 'image-size', 'Images are not oversized', big.length === 0, 1, big.length + ' images much larger than shown', big.map(function (e) { return it(e, e.naturalWidth + '×' + e.naturalHeight + ' shown at ' + e.clientWidth + '×' + e.clientHeight); }));
    var inlineHandlers = els('*').filter(function (e) { for (var i = 0; i < e.attributes.length; i++) if (/^on/.test(e.attributes[i].name)) return true; return false; });
    add('best', 'inline-handlers', 'No inline event handlers (CSP-friendly)', inlineHandlers.length === 0, 1, inlineHandlers.length + ' elements', inlineHandlers.map(function (e) { return it(e); }));
    var aspect = els('img').filter(function (im) { return im.naturalWidth && im.clientWidth && Math.abs(im.naturalWidth / im.naturalHeight - im.clientWidth / im.clientHeight) > 0.05 && getComputedStyle(im).objectFit === 'fill'; });
    add('best', 'image-aspect', 'Images keep their aspect ratio', aspect.length === 0, 1, aspect.length + ' stretched images', aspect.map(function (e) { return it(e); }));

    // Performance
    var p = await perf();
    add('perf', 'fcp', 'First Contentful Paint ≤ 1.8 s', p.fcp != null && p.fcp <= 1800, 3, p.fcp != null ? (p.fcp / 1000).toFixed(2) + ' s' : 'not measured');
    add('perf', 'lcp', 'Largest Contentful Paint ≤ 2.5 s', p.lcp != null && p.lcp <= 2500, 4, p.lcp != null ? (p.lcp / 1000).toFixed(2) + ' s' : 'not measured', p.lcpElement ? [{ label: p.lcpElement.label, path: p.lcpElement.path, note: 'LCP element' }] : []);
    add('perf', 'cls', 'Cumulative Layout Shift ≤ 0.1', p.cls <= 0.1, 4, String(p.cls));
    add('perf', 'tbt', 'Little main-thread blocking (≤ 200 ms)', p.blocking <= 200, 3, Math.round(p.blocking) + ' ms in ' + p.longTasks + ' long tasks');
    add('perf', 'ttfb', 'Server responds fast (TTFB ≤ 800 ms)', p.ttfb != null && p.ttfb <= 800, 2, p.ttfb != null ? p.ttfb + ' ms' : 'not measured');
    add('perf', 'dom-size', 'DOM size ≤ 1,500 elements', p.dom <= 1500, 1, p.dom + ' elements, depth ' + p.depth);
    var blocking = els('head script[src]:not([async]):not([defer]):not([type="module"])').map(function (e) { return it(e, e.src); })
      .concat(els('head link[rel="stylesheet"]:not([media="print"])').map(function (e) { return it(e, e.href); }));
    add('perf', 'render-blocking', 'Few render-blocking resources', blocking.length <= 2, 2, blocking.length + ' scripts/styles block the first paint', blocking);
    var heavy = performance.getEntriesByType('resource').filter(function (e) { return (e.transferSize || 0) > 300000; }).map(function (e) { return { label: e.name, note: Math.round(e.transferSize / 1024) + ' KB' }; });
    add('perf', 'heavy', 'No very large downloads (> 300 KB)', heavy.length === 0, 2, heavy.length + ' large files', heavy);
    var lazy = els('img').filter(function (im) { var r = im.getBoundingClientRect(); return r.top > innerHeight * 1.5 && im.loading !== 'lazy'; });
    add('perf', 'lazy-images', 'Off-screen images load lazily', lazy.length === 0, 1, lazy.length + ' images', lazy.map(function (e) { return it(e, e.currentSrc || e.src); }));
    var total = performance.getEntriesByType('resource').reduce(function (s, e) { return s + (e.transferSize || 0); }, p.transfer || 0);
    add('perf', 'weight', 'Total page weight ≤ 2.5 MB', total <= 2.5 * 1048576, 1, (total / 1048576).toFixed(2) + ' MB in ' + p.requests + ' requests');

    // PWA
    var man = document.querySelector('link[rel~="manifest"]');
    add('pwa', 'manifest', 'Has a web app manifest', !!man, 3, man ? man.href : '');
    var sw = false; try { sw = !!(navigator.serviceWorker && navigator.serviceWorker.controller); } catch (e) {}
    add('pwa', 'service-worker', 'A service worker controls the page', sw, 3, sw ? 'Works offline when the worker caches the page' : '');
    add('pwa', 'theme-color', 'Sets a theme color', !!document.querySelector('meta[name="theme-color"]'), 1, '');
    add('pwa', 'apple-icon', 'Has an apple-touch-icon', !!document.querySelector('link[rel="apple-touch-icon"]'), 1, '');
    add('pwa', 'https', 'Served over HTTPS', https, 3, '');

    var cats = {};
    A.forEach(function (a) { var c = cats[a.cat] || (cats[a.cat] = { got: 0, max: 0 }); c.max += a.weight; if (a.pass) c.got += a.weight; });
    var scores = {}; Object.keys(cats).forEach(function (k) { scores[k] = Math.round(100 * cats[k].got / cats[k].max); });
    return { scores: scores, audits: A, url: location.href, at: Date.now() };
  }

  async function securityHeaders() {
    var names = ['content-security-policy', 'strict-transport-security', 'x-frame-options', 'x-content-type-options', 'referrer-policy',
      'permissions-policy', 'cross-origin-opener-policy', 'cross-origin-embedder-policy', 'cross-origin-resource-policy', 'server', 'x-powered-by', 'cache-control', 'content-type'];
    try {
      var r = await fetch(location.href, { method: 'GET', credentials: 'include', cache: 'no-store' });
      var h = {}; names.forEach(function (n) { var v = r.headers.get(n); if (v != null) h[n] = v; });
      var all = []; r.headers.forEach(function (v, k) { all.push([k, v]); });
      return { status: r.status, headers: h, all: all };
    } catch (e) { return { error: String(e.message || e) }; }
  }

  function info() {
    var vp = document.querySelector('meta[name="viewport"]');
    return {
      url: location.href, title: document.title, origin: location.origin, protocol: location.protocol, referrer: document.referrer,
      readyState: document.readyState, charset: document.characterSet, lang: document.documentElement.lang || '', mode: document.compatMode,
      doctype: document.doctype ? document.doctype.name : '', viewport: vp ? vp.content : '', ua: navigator.userAgent,
      screen: screen.width + '×' + screen.height, window: innerWidth + '×' + innerHeight, dpr: devicePixelRatio,
      online: navigator.onLine, cookies: navigator.cookieEnabled, secure: window.isSecureContext, lastModified: document.lastModified,
      counts: {
        elements: document.getElementsByTagName('*').length, scripts: document.scripts.length, styles: document.styleSheets.length,
        images: document.images.length, links: document.links.length, forms: document.forms.length, iframes: document.querySelectorAll('iframe').length
      },
      frameworks: (function () {
        var f = [];
        if (window.React || document.querySelector('[data-reactroot], #__next')) f.push('React');
        if (window.__NEXT_DATA__) f.push('Next.js');
        if (window.Vue || document.querySelector('[data-v-app], [data-server-rendered]')) f.push('Vue');
        if (window.__NUXT__) f.push('Nuxt');
        if (window.angular || document.querySelector('[ng-version]')) f.push('Angular');
        if (document.querySelector('[class*="svelte-"]')) f.push('Svelte');
        if (window.jQuery) f.push('jQuery ' + (window.jQuery.fn && window.jQuery.fn.jquery || ''));
        if (document.querySelector('meta[name="generator"][content*="WordPress"]')) f.push('WordPress');
        if (window.Shopify) f.push('Shopify');
        if (document.querySelector('script[src*="tailwind"], [class*="tw-"]')) f.push('Tailwind');
        if (window.bootstrap || document.querySelector('link[href*="bootstrap"]')) f.push('Bootstrap');
        if (window.gtag || window.ga || window.dataLayer) f.push('Google Analytics/Tag Manager');
        return f;
      })()
    };
  }

  window.__nxdt = {
    v: 3, children: children, details: details, highlight: highlight, unhighlight: unhighlight, pick: pick, cancelPick: cancelPick,
    edit: edit, query: query, search: search, preview: preview, props: props,
    storage: storage, storageSet: storageSet, cookies: cookies, cookieDelete: cookieDelete, cookieSet: cookieSet,
    idb: idb, idbRecords: idbRecords, caches: cachesList, workers: workers, workerAction: workerAction, manifest: manifest,
    estimate: estimate, clearSite: clearSite, resources: resources, inlineSource: inlineSource, fetchText: fetchText,
    perf: perf, audit: audit, securityHeaders: securityHeaders, info: info, selectorOf: selectorOf, pathOf: pathOf, nodeAt: nodeAt
  };
  // Console helpers (like Chrome): $0 selected, $(), $$(), copy()
  if (!window.$) window.$ = function (s) { return document.querySelector(s); };
  if (!window.$$) window.$$ = function (s) { return Array.prototype.slice.call(document.querySelectorAll(s)); };
  window.$x = function (xp) { var r = document.evaluate(xp, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null), out = []; for (var i = 0; i < r.snapshotLength; i++) out.push(r.snapshotItem(i)); return out; };
})();
