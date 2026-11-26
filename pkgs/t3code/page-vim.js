/* Graphide's browser keys, in T3 Code's preview.
 *
 * gred drives a page with its own grammar (graphide-ide's
 * gred-rs/crates/page/src/keys.rs): Normal is grim's keys, `i` gives every
 * key to the page until Shift+Escape, a field has them while it is focused,
 * and `f` puts a label on everything in view. This is that table, as far as
 * a script inside the page can carry it.
 *
 * Where it runs. T3's preview is an Electron <webview> whose preload,
 * preview-pick-preload.cjs, runs in its own JavaScript world and already
 * listens for keydown there; the build appends this to it, so it sees the
 * page's keys and its DOM without touching T3's own code. Anything only the
 * app can do (the zoom, the address bar, the find bar) goes back to T3
 * through its own preview:page-unhandled-shortcut channel, which is how the
 * preload forwards a chord the page did not take: the chord T3 already binds
 * for that command is sent, so no new binding is needed and this never names
 * a T3 command.
 *
 * Off: Shift+Escape gives every key to the page, which is gred's own way
 * out, and `ai.t3code.vimComposer = false` leaves the preload stock.
 */
(() => {
  "use strict";

  /* Frames get their own preload; only the page's own top frame takes keys. */
  if (typeof window === "undefined" || window.top !== window) return;
  if (window.__t3pagevim) return;

  /* ------------------------------------------------------------ bridge -- */

  /* The preload's own channel for a chord the page did not take. T3 matches
     it against the shortcuts it forwards and runs the command in the app.
     It only forwards what carries a modifier, which every chord here does. */
  const CHANNEL = "preview:page-unhandled-shortcut";
  let ipc = null;
  try {
    ipc = typeof require === "function" ? require("electron").ipcRenderer : null;
  } catch { ipc = null; }

  /* The chords T3 already binds for the preview, from its own keybindings:
     mod+= zoom in, mod+- zoom out, mod+0 back to 100%, alt+shift+l the
     address, alt+shift+f the find bar. On Linux mod is ctrl. */
  const CHORDS = {
    zoomIn: { key: "=", code: "Equal", ctrlKey: true },
    zoomOut: { key: "-", code: "Minus", ctrlKey: true },
    zoomReset: { key: "0", code: "Digit0", ctrlKey: true },
    address: { key: "L", code: "KeyL", altKey: true, shiftKey: true },
    find: { key: "F", code: "KeyF", altKey: true, shiftKey: true },
  };
  const sent = [];
  function toApp(name) {
    const chord = CHORDS[name];
    if (!chord) return false;
    const shortcut = {
      key: chord.key, code: chord.code,
      metaKey: !!chord.metaKey, ctrlKey: !!chord.ctrlKey,
      shiftKey: !!chord.shiftKey, altKey: !!chord.altKey,
    };
    sent.push(name);
    if (ipc) ipc.send(CHANNEL, shortcut);
    return true;
  }

  /* -------------------------------------------------------------- feel -- */

  /* gred's own measures: page/src/keys.rs's STEP and LINE, and ui::motion's
     GLIDE, the spring its scrolls run on. */
  const STEP = 60;        // j k h l
  const LINE = 40;        // <C-e> <C-y>: about two lines of a page's text
  const GLIDE_MS = 90;
  const FLASH_MS = 1600;

  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

  /* ------------------------------------------------------------ scroll -- */

  /* gred scrolls the area under the point: where the pointer last clicked, a
     label last pressed or a find last landed. */
  let point = null;
  window.addEventListener("pointerdown", (e) => {
    if (e.isTrusted) point = { x: e.clientX, y: e.clientY };
  }, true);

  const canScroll = (n, down) => {
    if (!n || n === document.body || n === document.documentElement) return false;
    const over = getComputedStyle(n)[down ? "overflowY" : "overflowX"];
    if (!/auto|scroll/.test(over)) return false;
    return down ? n.scrollHeight > n.clientHeight + 2 : n.scrollWidth > n.clientWidth + 2;
  };

  function area(down) {
    if (point) {
      let n = document.elementFromPoint(point.x, point.y);
      for (; n && n !== document.body; n = n.parentElement) if (canScroll(n, down)) return n;
    }
    return document.scrollingElement || document.documentElement;
  }

  const GLIDE = { el: null, to: 0, at: 0, raf: 0, last: 0, side: false };

  function glide(el, to, side) {
    const most = side
      ? Math.max(0, el.scrollWidth - el.clientWidth)
      : Math.max(0, el.scrollHeight - el.clientHeight);
    const going = GLIDE.raf && GLIDE.el === el && GLIDE.side === side;
    GLIDE.el = el;
    GLIDE.side = side;
    GLIDE.to = clamp(to, 0, most);
    if (going) return true;
    GLIDE.at = side ? el.scrollLeft : el.scrollTop;
    GLIDE.last = now();
    const tick = (stamp) => {
      const el2 = GLIDE.el;
      if (!el2 || !el2.isConnected) { GLIDE.raf = 0; return; }
      const is = GLIDE.side ? el2.scrollLeft : el2.scrollTop;
      /* Whoever else moved it wins: the wheel, or the page itself. */
      if (Math.abs(is - GLIDE.at) > 3) { GLIDE.raf = 0; return; }
      const dt = Math.min(64, Math.max(1, stamp - GLIDE.last));
      GLIDE.last = stamp;
      GLIDE.at += (GLIDE.to - GLIDE.at) * (1 - Math.exp(-dt / (GLIDE_MS / 3)));
      const land = Math.abs(GLIDE.to - GLIDE.at) < 0.5;
      const put = land ? GLIDE.to : GLIDE.at;
      if (GLIDE.side) el2.scrollLeft = put; else el2.scrollTop = put;
      if (land) { GLIDE.raf = 0; return; }
      GLIDE.raf = requestAnimationFrame(tick);
    };
    GLIDE.raf = requestAnimationFrame(tick);
    return true;
  }

  const now = () => (window.performance ? performance.now() : Date.now());
  const going = (el, side) =>
    (GLIDE.raf && GLIDE.el === el && GLIDE.side === side
      ? GLIDE.to
      : side ? el.scrollLeft : el.scrollTop);

  function by(amount, side) {
    const el = area(!side);
    return glide(el, going(el, side) + amount, side);
  }
  function to(where, side) {
    const el = area(!side);
    const most = side
      ? Math.max(0, el.scrollWidth - el.clientWidth)
      : Math.max(0, el.scrollHeight - el.clientHeight);
    return glide(el, where < 0 ? most : where, side);
  }
  function share(part) {
    const el = area(true);
    return glide(el, Math.max(0, el.scrollHeight - el.clientHeight) * clamp(part, 0, 1), false);
  }
  const screenOf = (el) => Math.max(LINE, el.clientHeight - 2 * LINE);

  /* ------------------------------------------------------------- walks -- */

  /* How far down the pane a walk stands what it goes to. */
  const WALK_PAD = 8;

  const WALK = {
    "]": "h1,h2,h3,h4,h5,h6",
    l: "a[href]",
    f: "input:not([type=hidden]),textarea,select",
    t: "table",
    c: "pre,code",
  };

  function walk(what, back) {
    const sel = WALK[what];
    if (!sel) return false;
    const el = area(true);
    const box = el === document.scrollingElement || el === document.documentElement
      ? { top: 0, bottom: window.innerHeight } : el.getBoundingClientRect();
    const all = Array.from(document.querySelectorAll(sel)).filter(seen);
    let found = null;
    if (back) {
      for (let i = all.length - 1; i >= 0; i--) {
        if (all[i].getBoundingClientRect().top < box.top - 2) { found = all[i]; break; }
      }
    } else {
      /* Past the one this walk last landed, which stands WALK_PAD down. */
      for (const n of all) if (n.getBoundingClientRect().top > box.top + WALK_PAD + 4) { found = n; break; }
    }
    if (!found) return to(back ? 0 : -1, false);
    return glide(el, el.scrollTop + found.getBoundingClientRect().top - box.top - WALK_PAD, false);
  }

  function seen(n) {
    const r = n.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const style = getComputedStyle(n);
    return style.visibility !== "hidden" && style.display !== "none" && Number(style.opacity) > 0.05;
  }

  /* ------------------------------------------------------------- marks -- */

  const marks = new Map();
  function setMark(ch) {
    const el = area(true);
    /* Where the view is going, not where it has got to: a mark set straight
       after a G is the bottom, not halfway down the glide. */
    marks.set(ch, { top: going(el, false), left: going(el, true), url: location.href });
    flash("mark " + ch);
    return true;
  }
  function goMark(ch) {
    const m = marks.get(ch);
    if (!m) { flash("no mark " + ch); return true; }
    if (m.url !== location.href && /[A-Z]/.test(ch)) { location.href = m.url; return true; }
    const el = area(true);
    glide(el, m.top, false);
    el.scrollLeft = m.left;
    return true;
  }

  /* ----------------------------------------------------------- the bar -- */

  /* What gred says on its message line, said here in the page's own corner,
     since the app's statusline cannot see in. A label is the shared control's
     accent tag: 18 tall, radius 4, pad 7, caption at 600. */
  let bar = null, barTimer = 0;
  function chrome() {
    if (bar && bar.isConnected) return bar;
    const host = document.createElement("div");
    host.setAttribute("data-t3pagevim", "");
    host.style.cssText = "all:initial;position:fixed;z-index:2147483647;left:0;bottom:0;pointer-events:none";
    const root = host.attachShadow ? host.attachShadow({ mode: "open" }) : host;
    const el = document.createElement("div");
    el.style.cssText = [
      "margin:6px;padding:0 7px;height:18px;border-radius:4px;display:none;",
      "align-items:center;font:600 11px/1.3 ui-sans-serif,system-ui,sans-serif;",
      "letter-spacing:.01em;background:#4fa396;color:#04120f;white-space:nowrap",
    ].join("");
    root.appendChild(el);
    (document.body || document.documentElement).appendChild(host);
    bar = el;
    return el;
  }
  function say(text) {
    const el = chrome();
    el.textContent = text;
    el.style.display = text ? "inline-flex" : "none";
  }
  function flash(text) {
    say(text);
    if (barTimer) clearTimeout(barTimer);
    barTimer = setTimeout(() => { barTimer = 0; say(S.mode === "PAGEKEYS" ? "Page keys" : ""); }, FLASH_MS);
  }

  /* ------------------------------------------------------------- hints -- */

  /* Tridactyl's keys, home row first, as ui::hints has them. */
  const HINT_KEYS = "hjklasdfgyuiopqwertnmzxcvb";
  const PICKABLE = [
    "a[href]", "button", "input:not([type=hidden])", "textarea", "select",
    "summary", "label[for]", "[role=button]", "[role=link]", "[role=checkbox]",
    "[role=tab]", "[role=menuitem]", "[onclick]", "[tabindex]:not([tabindex='-1'])",
  ].join(",");

  const HINTS = { on: false, at: "", items: [], host: null, newTab: false };

  function labels(count) {
    const n = HINT_KEYS.length;
    const singles = Math.min(n, Math.floor(Math.max(0, n * n - count) / (n - 1)));
    const out = [];
    for (let i = 0; i < count; i++) {
      if (i < singles) out.push(HINT_KEYS[i]);
      else {
        const rest = i - singles;
        out.push(HINT_KEYS[singles + Math.floor(rest / n)] + HINT_KEYS[rest % n]);
      }
    }
    return out;
  }

  function hintsOpen(newTab) {
    hintsClose();
    const found = Array.from(document.querySelectorAll(PICKABLE)).filter((n) => {
      if (!seen(n)) return false;
      const r = n.getBoundingClientRect();
      return r.bottom > 0 && r.top < window.innerHeight && r.right > 0 && r.left < window.innerWidth;
    });
    if (!found.length) { flash("nothing to label"); return true; }
    const keys = labels(found.length);
    const host = document.createElement("div");
    host.setAttribute("data-t3pagevim-hints", "");
    host.style.cssText = "all:initial;position:fixed;inset:0;z-index:2147483646;pointer-events:none";
    const root = host.attachShadow ? host.attachShadow({ mode: "open" }) : host;
    HINTS.items = found.map((el, i) => {
      const r = el.getBoundingClientRect();
      const tag = document.createElement("div");
      tag.style.cssText = [
        "position:absolute;left:" + Math.max(0, r.left) + "px;top:" + Math.max(0, r.top) + "px;",
        "height:18px;padding:0 7px;border-radius:4px;display:inline-flex;align-items:center;",
        "font:600 11px/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.01em;",
        "background:#4fa396;color:#04120f",
      ].join("");
      tag.textContent = keys[i];
      root.appendChild(tag);
      return { el, keys: keys[i], tag };
    });
    (document.body || document.documentElement).appendChild(host);
    HINTS.host = host;
    HINTS.on = true;
    HINTS.at = "";
    HINTS.newTab = newTab;
    return true;
  }

  function hintsClose() {
    if (HINTS.host && HINTS.host.isConnected) HINTS.host.remove();
    HINTS.on = false;
    HINTS.at = "";
    HINTS.items = [];
    HINTS.host = null;
  }

  function hintsKey(k) {
    if (k === "Escape") { hintsClose(); return true; }
    if (k === "Backspace") { HINTS.at = HINTS.at.slice(0, -1); hintsPaint(); return true; }
    if (k.length !== 1 || HINT_KEYS.indexOf(k) < 0) return true;
    HINTS.at += k;
    const hit = HINTS.items.find((h) => h.keys === HINTS.at);
    if (hit) {
      const el = hit.el;
      const newTab = HINTS.newTab;
      hintsClose();
      pick(el, newTab);
      return true;
    }
    if (!HINTS.items.some((h) => h.keys.indexOf(HINTS.at) === 0)) { hintsClose(); return true; }
    hintsPaint();
    return true;
  }

  function hintsPaint() {
    for (const h of HINTS.items) {
      const match = h.keys.indexOf(HINTS.at) === 0;
      h.tag.style.display = match ? "inline-flex" : "none";
      h.tag.textContent = match ? h.keys.slice(HINTS.at.length) : h.keys;
    }
  }

  function pick(el, newTab) {
    point = null;
    const href = el.getAttribute && el.getAttribute("href");
    if (newTab && href) { window.open(el.href, "_blank"); return; }
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) { el.focus(); return; }
    el.focus && el.focus({ preventScroll: true });
    el.click();
  }

  /* ----------------------------------------------------------- the rest -- */

  function copy(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
    } else fallbackCopy(text);
    flash("yanked");
    return true;
  }
  function fallbackCopy(text) {
    const box = document.createElement("textarea");
    box.value = text;
    box.style.cssText = "position:fixed;opacity:0;pointer-events:none";
    (document.body || document.documentElement).appendChild(box);
    box.select();
    try { document.execCommand("copy"); } catch { /* nothing else to try */ }
    box.remove();
  }

  const editable = (n) =>
    !!n && (/^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName) || n.isContentEditable === true);

  function field(last) {
    const all = Array.from(document.querySelectorAll("input:not([type=hidden]),textarea")).filter(seen);
    const el = last ? all[all.length - 1] : all[0];
    if (!el) { flash("no field"); return true; }
    el.focus();
    return true;
  }

  /* gu, gU and the address counted up or down, with `.` to do it again. */
  let again = null;
  function parent() {
    const u = new URL(location.href);
    if (u.hash) u.hash = "";
    else if (u.search) u.search = "";
    else {
      const parts = u.pathname.replace(/\/$/, "").split("/");
      parts.pop();
      u.pathname = parts.join("/") || "/";
    }
    again = parent;
    location.href = u.href;
    return true;
  }
  function root() {
    again = root;
    location.href = location.origin + "/";
    return true;
  }
  function count(up) {
    const m = /(\d+)(\D*)$/.exec(location.href);
    if (!m) { flash("no number in the address"); return true; }
    const n = Math.max(0, parseInt(m[1], 10) + (up ? 1 : -1));
    const made = String(n).padStart(m[1].length, "0");
    again = () => count(up);
    location.href = location.href.slice(0, m.index) + made + m[2];
    return true;
  }

  /* -------------------------------------------------------------- keys -- */

  const S = { mode: "NORMAL", count: "", pending: "", passOne: false };

  function reset() { S.count = ""; S.pending = ""; }
  const take = () => { const n = S.count ? parseInt(S.count, 10) : 1; S.count = ""; return n; };

  function onKey(e) {
    if (!e.isTrusted || e.isComposing) return;
    /* T3's own overlays, the element picker and the annotations, keep their
       keys: they are in a shadow root of their own over the page. */
    if (e.target && e.target.closest && e.target.closest("[data-t3code-overlay],[data-t3-annotation]")) return;

    const k = e.key;
    const eat = () => { e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };

    if (HINTS.on) { eat(); hintsKey(k); return; }

    if (S.passOne) { S.passOne = false; return; }      /* <C-v>: the next key is the page's */

    /* A field has the keys, as gred's insert mode does; Escape leaves it. */
    if (editable(document.activeElement)) {
      if (k === "Escape") {
        eat();
        document.activeElement.blur();
        if (S.mode === "PAGEKEYS") flash("Page keys");
      }
      return;
    }

    /* Every key to the page until Shift+Escape. */
    if (S.mode === "PAGEKEYS") {
      if (k === "Escape" && e.shiftKey) { eat(); S.mode = "NORMAL"; say(""); flash("Normal"); }
      return;
    }

    /* A sequence waiting for its second key: g, ], [, y, m, ', `, ;. It is
       asked before the chords, since g<C-a> and g<C-x> are two of them. */
    if (S.pending) {
      if (/^(Shift|Control|Alt|Meta|AltGraph)$/.test(k)) return;
      eat();
      const at = S.pending;
      S.pending = "";
      if (k !== "Escape") step(at, k, e);
      return;
    }

    if (e.metaKey) return;
    const ctrl = e.ctrlKey && !e.altKey && !e.metaKey;
    if (ctrl) {
      const el = area(true);
      if (k === "d") { eat(); by(Math.round(el.clientHeight / 2) * take(), false); return; }
      if (k === "u") { eat(); by(-Math.round(el.clientHeight / 2) * take(), false); return; }
      if (k === "f") { eat(); by(screenOf(el) * take(), false); return; }
      if (k === "b") { eat(); by(-screenOf(el) * take(), false); return; }
      if (k === "e") { eat(); by(LINE * take(), false); return; }
      if (k === "y") { eat(); by(-LINE * take(), false); return; }
      if (k === "v") { eat(); S.passOne = true; flash("the next key is the page's"); return; }
      return;                                           /* every other chord is T3's */
    }
    if (e.ctrlKey || e.altKey) return;

    /* A count typed ahead, as Vim takes it. 0 alone is the far left. */
    if (/^[1-9]$/.test(k) || (k === "0" && S.count)) { eat(); S.count += k; return; }

    switch (k) {
      case "j": case "ArrowDown": eat(); by(STEP * take(), false); return;
      case "k": case "ArrowUp": eat(); by(-STEP * take(), false); return;
      case "h": case "ArrowLeft": eat(); by(-STEP * take(), true); return;
      case "l": case "ArrowRight": eat(); by(STEP * take(), true); return;
      case "d": eat(); by(Math.round(area(true).clientHeight / 2) * take(), false); return;
      case "u": eat(); by(-Math.round(area(true).clientHeight / 2) * take(), false); return;
      case "G": case "End": eat(); to(-1, false); return;
      case "Home": eat(); to(0, false); return;
      case "0": eat(); to(0, true); return;
      case "$": eat(); to(-1, true); return;
      case "%": eat(); share((S.count ? parseInt(S.count, 10) : 50) / 100); S.count = ""; return;
      case "PageDown": eat(); by(screenOf(area(true)) * take(), false); return;
      case "PageUp": eat(); by(-screenOf(area(true)) * take(), false); return;
      case "H": eat(); again = () => history.back(); history.back(); return;
      case "L": eat(); again = () => history.forward(); history.forward(); return;
      case "r": eat(); again = () => location.reload(); location.reload(); return;
      case "i": eat(); S.mode = "PAGEKEYS"; say("Page keys"); return;
      case "f": eat(); hintsOpen(false); return;
      case "F": eat(); hintsOpen(true); return;
      case "o": case "O": eat(); toApp("address"); return;
      case "/": case "?": eat(); toApp("find"); return;
      case "+": eat(); for (let i = take(); i > 0; i--) toApp("zoomIn"); return;
      case "-": eat(); for (let i = take(); i > 0; i--) toApp("zoomOut"); return;
      case "=": eat(); toApp("zoomReset"); return;
      case ".": eat(); if (again) again(); else flash("nothing to do again"); return;
      case "Escape": eat(); reset(); hintsClose(); getSelection().removeAllRanges(); return;
      case "g": case "]": case "[": case "y": case "m": case "'": case "`": case ";":
        eat(); S.pending = k; return;
      default: return;                                  /* the page keeps the rest */
    }
  }

  /* The second key of a sequence. */
  function step(at, k, e) {
    if (at === "g") {
      if (k === "g") { to(S.count ? parseInt(S.count, 10) : 0, false); S.count = ""; return; }
      if (k === "i") { field(false); return; }
      if (k === "u") { parent(); return; }
      if (k === "U") { root(); return; }
      if (k === "a" && e.ctrlKey) { count(true); return; }
      if (k === "x" && e.ctrlKey) { count(false); return; }
      flash("g" + k + " is not mapped");
      return;
    }
    if (at === "]" || at === "[") {
      const back = at === "[";
      if (k === "]" || k === "[") { walk("]", back); return; }
      if (WALK[k]) { walk(k, back); return; }
      flash(at + k + " is not mapped");
      return;
    }
    if (at === "y") {
      if (k === "y") { copy(location.href); return; }
      if (k === "t") { copy(document.title); return; }
      if (k === "m") { copy("[" + document.title + "](" + location.href + ")"); return; }
      flash("y" + k + " is not mapped");
      return;
    }
    if (at === "m") { setMark(k); return; }
    if (at === "'" || at === "`") { goMark(k); return; }
    if (at === ";") { flash(";" + k + ": no T3 equivalent"); return; }
  }

  window.addEventListener("keydown", onKey, true);
  /* A page that navigates keeps the mode it was read in; the labels do not. */
  window.addEventListener("pagehide", hintsClose, true);

  window.__t3pagevim = {
    get state() { return { mode: S.mode, count: S.count, pending: S.pending, hints: HINTS.on }; },
    get sent() { return sent.slice(); },
    hints: () => HINTS.items.map((h) => h.keys),
    feed(key, mods) {
      const m = mods || {};
      onKey({
        isTrusted: true, isComposing: false, key,
        target: document.activeElement,
        ctrlKey: !!m.ctrl, shiftKey: !!m.shift, altKey: !!m.alt, metaKey: !!m.meta,
        preventDefault() {}, stopPropagation() {}, stopImmediatePropagation() {},
      });
      return this.state;
    },
    feedKeys(str) { for (const ch of String(str)) this.feed(ch); return this.state; },
    /* Land the glide at once, as the composer's scrollNow does. */
    scrollNow() {
      if (GLIDE.raf) { cancelAnimationFrame(GLIDE.raf); GLIDE.raf = 0; }
      if (GLIDE.el) { if (GLIDE.side) GLIDE.el.scrollLeft = GLIDE.to; else GLIDE.el.scrollTop = GLIDE.to; }
      return GLIDE.el ? (GLIDE.side ? GLIDE.el.scrollLeft : GLIDE.el.scrollTop) : 0;
    },
    /* Where the pointer last was, which is the area gred scrolls. Only a
       real press sets it, so a test says it outright. */
    pointAt(x, y) { point = x === undefined ? null : { x, y }; return point; },
    step: STEP, line: LINE,
    version: 1,
  };
})();
