/* ---------------------------------------------------------------------------
 * T3 Code - vim mode for the chat composer.
 *
 * T3's composer is a Tiptap (ProseMirror) contenteditable. T3's own keybinding
 * layer cannot reach it: a binding is one key plus modifiers with no modal
 * state, and the command registry holds no text-editing command at all. So
 * this runs in the renderer instead, and talks to the editor only through the
 * web platform and ProseMirror's own keymap:
 *
 *   motions   a DOM Range over a text<->offset map built from the live DOM
 *   deletes   execCommand('delete') on the native selection; PM's
 *             MutationObserver reconciles it, the same path IME takes
 *   inserts   execCommand('insertText')
 *   newline   synthetic Shift-Enter on view.dom -> HardBreak's own shortcut
 *   undo      synthetic Mod-z / Shift-Mod-z on view.dom -> History extension
 *
 * Synthetic events are dispatched with bubbles:false directly on view.dom, so
 * ProseMirror's listeners fire and T3's React tree never sees them. Nothing
 * here reads a minified symbol, so a T3 release only breaks this if the
 * composer stops being a ProseMirror contenteditable.
 *
 * Off switch, no rebuild needed:  localStorage['t3code:vim-composer'] = 'off'
 * or __t3vim.disable() in devtools. __t3vim.enable() turns it back on.
 * ------------------------------------------------------------------------- */
(() => {
  "use strict";

  const SWITCH = "t3code:vim-composer";
  const EDITABLE_SEL = ".composer-tiptap";
  const FORM_SEL = '[data-chat-composer-form="true"]';

  const lsGet = (k) => { try { return window.localStorage.getItem(k); } catch { return null; } };
  const lsSet = (k, v) => { try { window.localStorage.setItem(k, v); } catch { /* ignore */ } };

  /* An incomplete key sequence (<leader>a, <C-w>, g, ]) is dropped after this
     long. Graphide's timeoutlen is 300 ms, but it has a which-key bar to
     read; this gives the hint panel below time to be read too. */
  const SEQ_TIMEOUT_MS = 1000;
  /* How long a "no T3 equivalent" or "not mapped" message stays up. */
  const FLASH_MS = 1600;
  /* How long a pending prefix waits before the which-key panel paints.
     Graphide's `timeoutlen` default, which is what the which-key bar waits. */
  const HINT_DELAY_MS = 300;

  const NORMAL = "NORMAL", INSERT = "INSERT", VISUAL = "VISUAL", VLINE = "V-LINE";

  const WORDCH = /[A-Za-z0-9_]/;
  const WS = /\s/;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

  const S = {
    on: lsGet(SWITCH) !== "off",
    mode: INSERT,
    el: null,          // the focused .composer-tiptap
    count: "",         // pending count digits
    operator: null,    // 'd' 'c' 'y' '>' '<' 'gu' 'gU' 'g~'
    opCount: "",
    pending: null,     // 'f' 'F' 't' 'T' 'r' 'g' 'z' 'q' (quote reg) 'i' 'a'
    anchor: 0,         // visual anchor offset
    vpos: 0,           // visual cursor offset (vim's cursor sits ON a char)
    reg: { text: "", linewise: false },
    useClip: false,    // next y/p goes through the system clipboard ("+)
    lastFind: null,    // { cmd, ch }
    dot: null,         // { run, insert }
    rec: null,         // recording typed text for '.'
  };

  /* ---------------------------------------------------------------- model -- */

  /* Build the composer's plain text plus a map back to DOM positions.
     ProseMirror fillers are skipped so an empty paragraph is one line, not
     two, and a real <br> (HardBreak) is a newline. */
  function scan(root) {
    const segs = [];
    let text = "";
    /* UL/OL/TABLE are containers, not lines; their LI/TD children are. */
    const BLOCK = /^(P|DIV|LI|BLOCKQUOTE|PRE|H[1-6]|TD)$/;
    let started = false;
    const filler = (el) => {
      if (el.classList &&
          (el.classList.contains("ProseMirror-trailingBreak") ||
           el.classList.contains("ProseMirror-separator"))) return true;
      /* A <br> with nothing after it inside its own block is the browser's
         placeholder for an empty line, not a line break: <p><br></p> is one
         empty line, not two. ProseMirror marks its own placeholders with a
         class and always appends one after a real hard break that ends a
         block, so a bare trailing <br> is never a meaningful newline. */
      let n = el;
      while (n && n !== root) {
        if (n.nextSibling) return false;
        const up = n.parentNode;
        if (!up || up === root || BLOCK.test(up.tagName || "")) return true;
        n = up;
      }
      return true;
    };

    (function walk(node) {
      for (let c = node.firstChild; c; c = c.nextSibling) {
        if (c.nodeType === 3) {
          const v = (c.nodeValue || "").replace(/\u00a0/g, " ");
          segs.push({ node: c, start: text.length, len: v.length });
          text += v;
          if (v.length) started = true;
        } else if (c.nodeType === 1) {
          if (c.tagName === "BR") {
            if (filler(c)) continue;
            segs.push({ node: c, start: text.length, len: 0, br: true });
            text += "\n";
            started = true;
          } else if (BLOCK.test(c.tagName)) {
            if (started) text += "\n";
            started = true;
            segs.push({ node: c, start: text.length, len: 0, sep: true });
            walk(c);
          } else {
            walk(c);
          }
        }
      }
    })(root);

    return { text, segs, root };
  }

  function posToDom(map, pos) {
    for (const s of map.segs) {
      if (s.len > 0 && pos >= s.start && pos <= s.start + s.len) {
        return { node: s.node, offset: pos - s.start };
      }
    }
    let best = null;
    for (const s of map.segs) {
      if (s.start <= pos && (!best || s.start >= best.start)) best = s;
    }
    if (best) {
      if (best.br) {
        const p = best.node.parentNode;
        const i = Array.prototype.indexOf.call(p.childNodes, best.node);
        return { node: p, offset: pos > best.start ? i + 1 : i };
      }
      if (best.sep) return { node: best.node, offset: 0 };
      return { node: best.node, offset: Math.min(best.len, pos - best.start) };
    }
    return { node: map.root, offset: 0 };
  }

  function domToPos(map, node, offset) {
    if (!node) return 0;
    if (node.nodeType === 3) {
      for (const s of map.segs) {
        if (s.node === node) return s.start + Math.min(offset, s.len);
      }
      return 0;
    }
    const child = node.childNodes[offset];
    if (child) {
      for (const s of map.segs) if (s.node === child) return s.start;
      for (const s of map.segs) if (child.contains && child.contains(s.node)) return s.start;
    }
    let end = 0;
    for (const s of map.segs) {
      if (s.node === node || (node.contains && node.contains(s.node))) {
        end = Math.max(end, s.start + s.len);
      }
    }
    return end;
  }

  function here() {
    const sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || !S.el) return null;
    const map = scan(S.el);
    return {
      map,
      anchor: domToPos(map, sel.anchorNode, sel.anchorOffset),
      pos: domToPos(map, sel.focusNode, sel.focusOffset),
    };
  }

  function select(map, from, to) {
    const n = map.text.length;
    const A = posToDom(map, clamp(from, 0, n));
    const B = posToDom(map, clamp(to, 0, n));
    const sel = window.getSelection();
    try { sel.setBaseAndExtent(A.node, A.offset, B.node, B.offset); return true; }
    catch { return false; }
  }
  const caretTo = (map, p) => select(map, p, p);

  /* ------------------------------------------------------------ primitives - */

  function synth(key, mods) {
    if (!S.el) return;
    S.el.dispatchEvent(new KeyboardEvent("keydown", {
      key,
      bubbles: false,
      cancelable: true,
      ctrlKey: !!(mods && mods.ctrl),
      shiftKey: !!(mods && mods.shift),
      altKey: !!(mods && mods.alt),
      metaKey: !!(mods && mods.meta),
    }));
  }
  const undo = () => synth("z", { ctrl: true });
  const redo = () => synth("z", { ctrl: true, shift: true });
  const hardBreak = () => synth("Enter", { shift: true });
  const delSel = () => { try { document.execCommand("delete"); } catch { /* ignore */ } };
  /* Delete text[a, b).

     Not one execCommand over the whole range. A selection that crosses a
     block boundary is handled by the browser's own rules, and Chromium's
     differ from vim's: deleting [0,4) of "one\n\ntwo" (what `d}` asks for)
     takes the empty paragraph with it and leaves "two" instead of "\ntwo".

     So the range is taken apart instead: the text runs between newlines are
     deleted back to front, which never crosses a boundary and keeps the
     earlier offsets valid; then the bare newlines left behind are joined with
     a forward delete, which is the primitive that actually merges two blocks
     in both the browser and ProseMirror. A collapsed range is never deleted
     through, since that is a backspace. */
  function cut(map, a, b) {
    if (b <= a) return false;
    const text = map.text;
    const want = text.slice(0, a) + text.slice(b);

    const breaks = [];
    for (let i = a; i < b; i++) if (text[i] === "\n") breaks.push(i);

    const runs = [];
    let from = a;
    for (const i of breaks) { if (i > from) runs.push([from, i]); from = i + 1; }
    if (b > from) runs.push([from, b]);

    for (let i = runs.length - 1; i >= 0; i--) {
      const m = scan(S.el);
      if (select(m, runs[i][0], runs[i][1])) delSel();
    }
    /* Join the blocks the runs left behind. Convergent, not one per newline:
       emptying a paragraph sometimes removes it outright, and then there is
       one fewer seam to close than there were newlines. Stops as soon as the
       text matches, is short enough, or an attempt fails to shorten it, so it
       cannot run away. */
    for (let i = 0, cap = breaks.length + 3; i < cap; i++) {
      const m = scan(S.el);
      if (m.text === want || m.text.length <= want.length) break;
      caretTo(m, Math.min(a, m.text.length));
      try { document.execCommand("forwardDelete"); } catch { break; }
      if (scan(S.el).text.length >= m.text.length) break;
    }
    return true;
  }
  const insRaw = (s) => { if (s) { try { document.execCommand("insertText", false, s); } catch { /* ignore */ } } };

  /* Insert `str` at the caret. All the text goes in first, then the breaks,
     back to front. Chromium canonicalises a caret sitting just after a
     trailing <br> to the position in front of it, so inserting a break and
     then typing after it silently puts the text on the wrong side. Going
     back to front means every break lands with text already after it. */
  function insText(str) {
    const parts = String(str).split("\n");
    if (parts.length === 1) { insRaw(parts[0]); return; }
    const c0 = here();
    if (!c0) {
      for (let i = 0; i < parts.length; i++) { if (i) hardBreak(); if (parts[i]) insRaw(parts[i]); }
      return;
    }
    const at = c0.pos;
    insRaw(parts.join(""));
    const stops = [];
    let off = at;
    for (let i = 0; i < parts.length - 1; i++) { off += parts[i].length; stops.push(off); }
    for (let i = stops.length - 1; i >= 0; i--) {
      caretTo(scan(S.el), stops[i]);
      hardBreak();
    }
  }

  /* --------------------------------------------------------------- motions - */

  const lineStart = (t, p) => { const i = t.lastIndexOf("\n", Math.max(0, p - 1)); return i < 0 ? 0 : i + 1; };
  const lineEnd = (t, p) => { const i = t.indexOf("\n", p); return i < 0 ? t.length : i; };
  function firstNonBlank(t, p) {
    let i = lineStart(t, p); const e = lineEnd(t, p);
    while (i < e && WS.test(t[i])) i++;
    return i;
  }
  const cls = (ch) => (ch === undefined ? 0 : WS.test(ch) ? 0 : WORDCH.test(ch) ? 1 : 2);

  function downLine(t, p, n) {
    const col = p - lineStart(t, p);
    let q = p;
    for (let i = 0; i < n; i++) { const e = lineEnd(t, q); if (e >= t.length) break; q = e + 1; }
    const s = lineStart(t, q), e = lineEnd(t, q);
    return Math.min(s + col, Math.max(s, e));
  }
  function upLine(t, p, n) {
    const col = p - lineStart(t, p);
    let q = p;
    for (let i = 0; i < n; i++) { const s = lineStart(t, q); if (s === 0) break; q = s - 1; }
    const s = lineStart(t, q), e = lineEnd(t, q);
    return Math.min(s + col, Math.max(s, e));
  }

  function wordFwd(t, p, big) {
    const n = t.length;
    if (p >= n) return n;
    const c0 = big ? (WS.test(t[p]) ? 0 : 1) : cls(t[p]);
    let i = p;
    if (c0 !== 0) {
      while (i < n && (big ? !WS.test(t[i]) : cls(t[i]) === c0)) i++;
    }
    while (i < n && WS.test(t[i])) i++;
    return i;
  }
  function wordBack(t, p, big) {
    let i = p - 1;
    while (i > 0 && WS.test(t[i])) i--;
    if (i <= 0) return 0;
    const c = big ? 1 : cls(t[i]);
    while (i > 0 && (big ? !WS.test(t[i - 1]) : cls(t[i - 1]) === c)) i--;
    return Math.max(0, i);
  }
  function wordEnd(t, p, big) {
    const n = t.length;
    let i = p + 1;
    while (i < n && WS.test(t[i])) i++;
    if (i >= n) return Math.max(0, n - 1);
    const c = big ? 1 : cls(t[i]);
    while (i + 1 < n && (big ? !WS.test(t[i + 1]) : cls(t[i + 1]) === c)) i++;
    return i;
  }

  /* f F t T, line-local as in vim */
  function findChar(t, p, cmd, ch, count) {
    const ls = lineStart(t, p), le = lineEnd(t, p);
    let i = p;
    for (let k = 0; k < count; k++) {
      if (cmd === "f" || cmd === "t") {
        let j = t.indexOf(ch, i + 1);
        if (cmd === "t" && k === 0 && j === i + 1 && count === 1) {
          const j2 = t.indexOf(ch, i + 2);
          if (j2 >= 0 && j2 <= le) j = j2;
        }
        if (j < 0 || j > le) return null;
        i = j;
      } else {
        const j = t.lastIndexOf(ch, i - 1);
        if (j < 0 || j < ls) return null;
        i = j;
      }
    }
    if (cmd === "t") return i - 1;
    if (cmd === "T") return i + 1;
    return i;
  }

  const OPENERS = { ")": "(", "]": "[", "}": "{" };
  const CLOSERS = { "(": ")", "[": "]", "{": "}" };

  function matchPair(t, p) {
    const le = lineEnd(t, p);
    let i = p;
    while (i < le && !CLOSERS[t[i]] && !OPENERS[t[i]]) i++;
    if (i >= le) return null;
    const ch = t[i];
    if (CLOSERS[ch]) {
      let depth = 0;
      for (let j = i; j < t.length; j++) {
        if (t[j] === ch) depth++;
        else if (t[j] === CLOSERS[ch]) { depth--; if (depth === 0) return j; }
      }
    } else {
      const open = OPENERS[ch];
      let depth = 0;
      for (let j = i; j >= 0; j--) {
        if (t[j] === ch) depth++;
        else if (t[j] === open) { depth--; if (depth === 0) return j; }
      }
    }
    return null;
  }

  function paraFwd(t, p) {
    let i = lineEnd(t, p);
    while (i < t.length) {
      const s = i + 1, e = lineEnd(t, s);
      if (s >= t.length) return t.length;
      if (t.slice(s, e).trim() === "") return s;
      i = e;
    }
    return t.length;
  }
  function paraBack(t, p) {
    let i = lineStart(t, p);
    while (i > 0) {
      const e = i - 1, s = lineStart(t, e);
      if (t.slice(s, e).trim() === "") return s;
      i = s;
      if (s === 0) break;
    }
    return 0;
  }

  /* --------------------------------------------------------- text objects - */

  const QUOTES = /["'`]/;

  function textObject(t, p, kind, which) {
    if (which === "w" || which === "W") {
      const big = which === "W";
      if (WS.test(t[p] || "")) {
        let a = p, b = p;
        while (a > 0 && WS.test(t[a - 1])) a--;
        while (b < t.length && WS.test(t[b])) b++;
        if (kind === "a" && b < t.length) {
          const c2 = big ? 1 : cls(t[b]);
          while (b < t.length && (big ? !WS.test(t[b]) : cls(t[b]) === c2)) b++;
        }
        return { from: a, to: b };
      }
      const c = big ? 1 : cls(t[p]);
      let a = p, b = p;
      while (a > 0 && (big ? !WS.test(t[a - 1]) : cls(t[a - 1]) === c)) a--;
      while (b < t.length && (big ? !WS.test(t[b]) : cls(t[b]) === c)) b++;
      if (kind === "a") {
        const b0 = b;
        while (b < t.length && WS.test(t[b])) b++;
        if (b === b0) while (a > 0 && WS.test(t[a - 1])) a--;
      }
      return { from: a, to: b };
    }

    if (QUOTES.test(which)) {
      const ls = lineStart(t, p), le = lineEnd(t, p);
      let open = -1, close = -1, i = ls;
      while (i < le) {
        if (t[i] === which) {
          const j = t.indexOf(which, i + 1);
          if (j < 0 || j > le) break;
          if (p <= j) { open = i; close = j; break; }
          i = j + 1;
        } else i++;
      }
      if (open < 0) return null;
      return kind === "i" ? { from: open + 1, to: close } : { from: open, to: close + 1 };
    }

    const map = { "(": "(", ")": "(", b: "(", "[": "[", "]": "[", "{": "{", "}": "{", B: "{" };
    const open = map[which];
    if (!open) return null;
    const close = CLOSERS[open];
    let depth = 0, a = -1;
    for (let i = p; i >= 0; i--) {
      if (t[i] === close && i !== p) depth++;
      else if (t[i] === open) { if (depth === 0) { a = i; break; } depth--; }
    }
    if (a < 0) return null;
    depth = 0;
    let b = -1;
    for (let i = a; i < t.length; i++) {
      if (t[i] === open) depth++;
      else if (t[i] === close) { depth--; if (depth === 0) { b = i; break; } }
    }
    if (b < 0) return null;
    return kind === "i" ? { from: a + 1, to: b } : { from: a, to: b + 1 };
  }

  /* ------------------------------------------------------------- operators - */

  function setReg(text, linewise) {
    S.reg = { text, linewise: !!linewise };
    if (S.useClip) {
      S.useClip = false;
      try { navigator.clipboard.writeText(text); } catch { /* ignore */ }
    }
  }

  const lineAt = (t, n) => {
    let i = 0;
    for (let k = 1; k < n; k++) {
      const e = t.indexOf("\n", i);
      if (e < 0) return i;
      i = e + 1;
    }
    return i;
  };

  function indentRange(map, a, b, op) {
    const t = map.text;
    const s = lineStart(t, a), e = lineEnd(t, b);
    const out = t.slice(s, e).split("\n").map((L) =>
      op === ">" ? "\t" + L : L.startsWith("\t") ? L.slice(1) : L.replace(/^ {1,8}/, "")
    ).join("\n");
    if (cut(map, s, e)) insText(out);
    const m2 = scan(S.el);
    caretTo(m2, firstNonBlank(m2.text, Math.min(s, m2.text.length)));
    setMode(NORMAL);
  }

  function runOperator(op, from, to, linewise) {
    const map = scan(S.el);
    const t = map.text;
    let a = Math.min(from, to), b = Math.max(from, to);
    if (linewise) { a = lineStart(t, a); b = lineEnd(t, b); }
    a = clamp(a, 0, t.length); b = clamp(b, 0, t.length);
    const body = t.slice(a, b);

    if (op === "y") {
      setReg(body, linewise);
      caretTo(map, a);
      setMode(NORMAL);
      return;
    }
    if (op === ">" || op === "<") { indentRange(map, a, b, op); return; }
    if (op === "gu" || op === "gU" || op === "g~") {
      const out = op === "gu" ? body.toLowerCase()
        : op === "gU" ? body.toUpperCase()
        : body.replace(/[A-Za-z]/g, (c) => (c === c.toLowerCase() ? c.toUpperCase() : c.toLowerCase()));
      if (cut(map, a, b)) insText(out);
      const m2 = scan(S.el);
      caretTo(m2, clamp(a, 0, m2.text.length));
      setMode(NORMAL);
      return;
    }

    setReg(body, linewise);
    let ra = a, rb = b;
    if (linewise && op === "d") {
      if (rb < t.length) rb += 1;
      else if (ra > 0) ra -= 1;
    }
    cut(map, ra, rb);
    if (op === "c") {
      setMode(INSERT, true);
    } else {
      const m2 = scan(S.el);
      caretTo(m2, clampNormal(m2, clamp(ra, 0, m2.text.length)));
      setMode(NORMAL);
    }
  }

  function clampNormal(map, p) {
    const t = map.text;
    const ls = lineStart(t, p), le = lineEnd(t, p);
    if (le > ls && p >= le) return le - 1;
    return clamp(p, 0, t.length);
  }

  async function doPaste(before, count) {
    let reg = S.reg;
    if (S.useClip) {
      S.useClip = false;
      try { reg = { text: await navigator.clipboard.readText(), linewise: false }; }
      catch { /* keep the internal register */ }
    }
    if (!reg || !reg.text) return;
    const map = scan(S.el);
    const t = map.text;
    const ctx = here();
    const pos = ctx ? ctx.pos : 0;
    const body = reg.text.repeat(Math.max(1, count));
    if (reg.linewise) {
      const block = body.replace(/\n$/, "");
      if (before) {
        caretTo(map, lineStart(t, pos));
        insText(block + "\n");
      } else {
        caretTo(map, lineEnd(t, pos));
        insText("\n" + block);
      }
      const m2 = scan(S.el);
      const ctx2 = here();
      if (ctx2) caretTo(m2, firstNonBlank(m2.text, clamp(ctx2.pos, 0, m2.text.length)));
    } else {
      caretTo(map, before ? pos : Math.min(t.length, pos + 1));
      insText(body);
      const m2 = scan(S.el);
      const ctx2 = here();
      if (ctx2) caretTo(m2, clampNormal(m2, ctx2.pos - 1));
    }
    setMode(NORMAL);
    refresh();
  }

  /* --------------------------------------------------------------- motions - */

  function motionFor(k, t, pos, count) {
    switch (k) {
      case "h": return { to: Math.max(lineStart(t, pos), pos - count) };
      case "l": return { to: Math.min(lineEnd(t, pos), pos + count) };
      case " ": return { to: Math.min(t.length, pos + count) };
      case "j": case "+": return { to: downLine(t, pos, count), linewise: true };
      case "k": case "-": return { to: upLine(t, pos, count), linewise: true };
      case "w": { let p = pos; for (let i = 0; i < count; i++) p = wordFwd(t, p, false); return { to: p }; }
      case "W": { let p = pos; for (let i = 0; i < count; i++) p = wordFwd(t, p, true); return { to: p }; }
      case "b": { let p = pos; for (let i = 0; i < count; i++) p = wordBack(t, p, false); return { to: p }; }
      case "B": { let p = pos; for (let i = 0; i < count; i++) p = wordBack(t, p, true); return { to: p }; }
      case "e": { let p = pos; for (let i = 0; i < count; i++) p = wordEnd(t, p, false); return { to: p, inclusive: true }; }
      case "E": { let p = pos; for (let i = 0; i < count; i++) p = wordEnd(t, p, true); return { to: p, inclusive: true }; }
      case "0": return { to: lineStart(t, pos) };
      case "^": return { to: firstNonBlank(t, pos) };
      case "$": { let p = pos; for (let i = 1; i < count; i++) p = downLine(t, p, 1); return { to: lineEnd(t, p), inclusive: true }; }
      case "G": return { to: firstNonBlank(t, lineAt(t, count > 1 ? count : Number.MAX_SAFE_INTEGER)), linewise: true };
      case "{": return { to: paraBack(t, pos) };
      case "}": return { to: paraFwd(t, pos) };
      case "%": { const m = matchPair(t, pos); return m == null ? null : { to: m, inclusive: true }; }
      case ";": case ",": {
        if (!S.lastFind) return null;
        let { cmd, ch } = S.lastFind;
        if (k === ",") cmd = { f: "F", F: "f", t: "T", T: "t" }[cmd];
        const r = findChar(t, pos, cmd, ch, count);
        return r == null ? null : { to: r, inclusive: cmd === "f" || cmd === "t" };
      }
      default: return null;
    }
  }

  function applyMotion(m, pos) {
    if (!m) { reset(); refresh(); return; }
    const map = scan(S.el);
    if (S.operator) {
      const op = S.operator;
      S.operator = null;
      const to = m.inclusive ? m.to + 1 : m.to;
      const from = pos;
      recordDot(() => runOperator(op, from, to, !!m.linewise));
      runOperator(op, from, to, !!m.linewise);
    } else if (S.mode === VISUAL || S.mode === VLINE) {
      S.vpos = clamp(m.to, 0, map.text.length);
      paintVisual();
    } else {
      caretTo(map, clampNormal(map, m.to));
    }
    S.count = ""; S.opCount = "";
    refresh();
  }

  /* ------------------------------------------------------------------ dot -- */

  function recordDot(run) { S.dot = { run, insert: null }; }

  /* ---------------------------------------------------------------- modes -- */

  function setMode(m, startRecording) {
    S.mode = m;
    if (m !== INSERT) S.rec = null;
    else if (startRecording) S.rec = [];
    if (m === NORMAL && S.el) {
      const map = scan(S.el), ctx = here();
      if (ctx) caretTo(map, clampNormal(map, ctx.pos));
    }
    refresh();
  }

  function reset() {
    S.count = ""; S.opCount = ""; S.operator = null; S.pending = null; S.useClip = false;
  }

  const takeCount = () => {
    const n = parseInt(S.count || "0", 10) || 0;
    const o = parseInt(S.opCount || "0", 10) || 0;
    S.count = ""; S.opCount = "";
    const total = (n || 1) * (o || 1);
    return total < 1 ? 1 : total;
  };

  /* --------------------------------------------------------- visual paint - */

  function paintVisual() {
    if (!S.el) return;
    const m = scan(S.el), t = m.text;
    if (S.mode === VLINE) {
      const a = Math.min(S.anchor, S.vpos), b = Math.max(S.anchor, S.vpos);
      select(m, lineStart(t, a), lineEnd(t, b));
    } else {
      const a = S.anchor, b = S.vpos;
      if (b >= a) select(m, a, Math.min(t.length, b + 1));
      else select(m, Math.min(t.length, a + 1), b);
    }
  }

  function visualRange() {
    const m = scan(S.el), t = m.text;
    const a = Math.min(S.anchor, S.vpos), b = Math.max(S.anchor, S.vpos);
    return S.mode === VLINE
      ? { from: lineStart(t, a), to: lineEnd(t, b), linewise: true }
      : { from: a, to: Math.min(t.length, b + 1), linewise: false };
  }

  function collapse() {
    const m = scan(S.el);
    caretTo(m, clampNormal(m, S.vpos));
  }

  /* ------------------------------------------------------------- commands -- */

  function handleKey(k) {
    const ctx = here();
    if (!ctx) return;
    const map = ctx.map, t = map.text;
    const visual = S.mode === VISUAL || S.mode === VLINE;
    const pos = visual ? clamp(S.vpos, 0, t.length) : clampNormal(map, ctx.pos);

    /* ---- pending single-character consumers ---- */
    if (S.pending === "r") {
      S.pending = null;
      if (k.length !== 1) { reset(); refresh(); return; }
      const n = takeCount();
      const run = () => {
        const m = scan(S.el), c = here();
        if (!c) return;
        const p = clampNormal(m, c.pos);
        const b = Math.min(lineEnd(m.text, p), p + n);
        if (cut(m, p, b)) insRaw(k.repeat(b - p));
        const m2 = scan(S.el);
        caretTo(m2, clampNormal(m2, b - 1));
      };
      recordDot(run); run(); setMode(NORMAL); refresh(); return;
    }
    if (S.pending === "f" || S.pending === "F" || S.pending === "t" || S.pending === "T") {
      const cmd = S.pending; S.pending = null;
      if (k.length !== 1) { reset(); refresh(); return; }
      S.lastFind = { cmd, ch: k };
      const r = findChar(t, pos, cmd, k, takeCount());
      applyMotion(r == null ? null : { to: r, inclusive: cmd === "f" || cmd === "t" }, pos);
      return;
    }
    if (S.pending === "reg") {
      S.pending = null;
      S.useClip = (k === "+" || k === "*");
      refresh(); return;
    }
    if (S.pending === "i" || S.pending === "a") {
      const kind = S.pending; S.pending = null;
      const ob = textObject(t, pos, kind, k);
      if (!ob) { reset(); refresh(); return; }
      if (S.operator) {
        const op = S.operator; S.operator = null;
        recordDot(() => runOperator(op, ob.from, ob.to, false));
        runOperator(op, ob.from, ob.to, false);
      } else if (visual) {
        S.anchor = ob.from; S.vpos = Math.max(ob.from, ob.to - 1);
        paintVisual();
      }
      refresh(); return;
    }
    if (S.pending === "g") {
      S.pending = null;
      if (k === "g") {
        const n = parseInt(S.count || "0", 10) || 0;
        S.count = "";
        applyMotion({ to: firstNonBlank(t, lineAt(t, n || 1)), linewise: true }, pos);
        return;
      }
      if (k === "u" || k === "U" || k === "~") {
        if (visual) { const r = visualRange(); runOperator("g" + k, r.from, r.to, r.linewise); }
        else S.operator = "g" + k;
        refresh(); return;
      }
      if (k === "e" || k === "E") { applyMotion({ to: wordBack(t, pos, k === "E"), inclusive: true }, pos); return; }
      if (k === "_") { applyMotion({ to: lineEnd(t, pos), inclusive: true }, pos); return; }
      reset(); refresh(); return;
    }

    /* ---- counts, registers ---- */
    if (/[1-9]/.test(k) || (k === "0" && S.count)) { S.count += k; refresh(); return; }
    if (k === '"') { S.pending = "reg"; refresh(); return; }

    /* ---- visual-only shorthands ---- */
    if (visual) {
      if (k === "o") {
        const a = S.anchor; S.anchor = S.vpos; S.vpos = a;
        paintVisual(); refresh(); return;
      }
      if (k === "x" || k === "s") {
        const r = visualRange();
        runOperator(k === "x" ? "d" : "c", r.from, r.to, r.linewise);
        refresh(); return;
      }
      if (k === "p") {
        const r = visualRange();
        setReg(t.slice(r.from, r.to), r.linewise);
        cut(scan(S.el), r.from, r.to);
        setMode(NORMAL);
        void doPaste(true, 1);
        return;
      }
      if (k === "v") { if (S.mode === VISUAL) { setMode(NORMAL); collapse(); } else { S.mode = VISUAL; paintVisual(); } refresh(); return; }
      if (k === "V") { if (S.mode === VLINE) { setMode(NORMAL); collapse(); } else { S.mode = VLINE; paintVisual(); } refresh(); return; }
    }

    /* ---- operators ---- */
    if (k === "d" || k === "c" || k === "y" || k === ">" || k === "<") {
      if (visual) {
        const r = visualRange();
        runOperator(k, r.from, r.to, r.linewise);
        refresh(); return;
      }
      if (S.operator === k) {                       /* dd cc yy >> << */
        const n = takeCount();
        const a = lineStart(t, pos);
        const b = lineEnd(t, downLine(t, pos, n - 1));
        S.operator = null;
        recordDot(() => runOperator(k, a, b, true));
        runOperator(k, a, b, true);
        refresh(); return;
      }
      if (S.operator) { reset(); refresh(); return; }
      S.operator = k;
      S.opCount = S.count; S.count = "";
      refresh(); return;
    }
    if (k === "g") { S.pending = "g"; refresh(); return; }
    if (k === "i" || k === "a") {
      if (S.operator || visual) { S.pending = k; refresh(); return; }
      const run = () => {
        const m = scan(S.el), c = here();
        if (!c) return;
        const p = clampNormal(m, c.pos);
        caretTo(m, k === "a" ? Math.min(m.text.length, p + 1) : p);
      };
      run();
      S.dot = { run, insert: null };
      setMode(INSERT, true);
      refresh(); return;
    }

    switch (k) {
      case "f": case "F": case "t": case "T": S.pending = k; refresh(); return;
      case "I": { caretTo(map, firstNonBlank(t, pos)); S.dot = null; setMode(INSERT, true); break; }
      case "A": { caretTo(map, lineEnd(t, pos)); S.dot = null; setMode(INSERT, true); break; }
      case "o": case "O": {
        const open = k;
        const run = () => {
          const m = scan(S.el), c = here();
          if (!c) return;
          const p = c.pos;
          if (open === "o") { caretTo(m, lineEnd(m.text, p)); hardBreak(); }
          else {
            caretTo(m, lineStart(m.text, p));
            hardBreak();
            const m2 = scan(S.el), c2 = here();
            if (c2) caretTo(m2, Math.max(0, lineStart(m2.text, c2.pos) - 1));
          }
        };
        run();
        S.dot = { run, insert: null };
        setMode(INSERT, true);
        break;
      }
      case "x": {
        const n = takeCount();
        const run = () => {
          const m = scan(S.el), c = here();
          if (!c) return;
          const p = clampNormal(m, c.pos);
          const b = Math.min(lineEnd(m.text, p), p + n);
          setReg(m.text.slice(p, b), false);
          cut(m, p, b);
          const m2 = scan(S.el);
          caretTo(m2, clampNormal(m2, p));
        };
        recordDot(run); run(); break;
      }
      case "X": {
        const n = takeCount();
        const run = () => {
          const m = scan(S.el), c = here();
          if (!c) return;
          const p = c.pos, a = Math.max(lineStart(m.text, p), p - n);
          setReg(m.text.slice(a, p), false);
          cut(m, a, p);
        };
        recordDot(run); run(); break;
      }
      case "D": { const b = lineEnd(t, pos); recordDot(() => runOperator("d", pos, b, false)); runOperator("d", pos, b, false); break; }
      case "C": { const b = lineEnd(t, pos); recordDot(() => runOperator("c", pos, b, false)); runOperator("c", pos, b, false); break; }
      case "Y": { const n = takeCount(); runOperator("y", lineStart(t, pos), lineEnd(t, downLine(t, pos, n - 1)), true); break; }
      case "s": { const n = takeCount(); const b = Math.min(lineEnd(t, pos), pos + n); recordDot(() => runOperator("c", pos, b, false)); runOperator("c", pos, b, false); break; }
      case "S": { runOperator("c", lineStart(t, pos), lineEnd(t, pos), true); break; }
      case "p": void doPaste(false, takeCount()); return;
      case "P": void doPaste(true, takeCount()); return;
      case "r": S.pending = "r"; refresh(); return;
      case "~": {
        const n = takeCount();
        const run = () => {
          const m = scan(S.el), c = here();
          if (!c) return;
          const p = clampNormal(m, c.pos);
          const b = Math.min(lineEnd(m.text, p), p + n);
          const body = m.text.slice(p, b).replace(/[A-Za-z]/g, (ch) => (ch === ch.toLowerCase() ? ch.toUpperCase() : ch.toLowerCase()));
          if (cut(m, p, b)) insRaw(body);
          const m2 = scan(S.el);
          caretTo(m2, clampNormal(m2, b));
        };
        recordDot(run); run(); break;
      }
      case "J": {
        const n = Math.max(2, takeCount());
        const run = () => {
          const c0 = here();
          if (!c0) return;
          const p = c0.pos;
          for (let i = 0; i < n - 1; i++) {
            const m = scan(S.el);
            const le = lineEnd(m.text, p);
            if (le >= m.text.length) break;
            let e = le + 1;
            while (e < m.text.length && /[ \t]/.test(m.text[e])) e++;
            if (cut(m, le, e)) insRaw(" ");
          }
          const m2 = scan(S.el);
          caretTo(m2, clampNormal(m2, p));
        };
        recordDot(run); run(); break;
      }
      case "u": { const n = takeCount(); for (let i = 0; i < n; i++) undo(); setMode(NORMAL); break; }
      case "v": { S.anchor = pos; S.vpos = pos; S.mode = VISUAL; paintVisual(); break; }
      case "V": { S.anchor = pos; S.vpos = pos; S.mode = VLINE; paintVisual(); break; }
      case ".": {
        if (S.dot && S.dot.run) {
          S.dot.run();
          if (S.dot.insert) { insText(S.dot.insert); setMode(NORMAL); }
        }
        break;
      }
      case "G": {
        const n = parseInt(S.count || "0", 10) || 0;
        S.count = "";
        applyMotion({ to: firstNonBlank(t, n ? lineAt(t, n) : lineStart(t, t.length)), linewise: true }, pos);
        return;
      }
      default: {
        const n = takeCount();
        let m;
        if (S.operator === "c" && (k === "w" || k === "W") && !WS.test(t[pos] || "")) {
          /* vim's own special case: cw behaves like ce, so the space after
             the word survives the change. */
          let q = pos;
          for (let i = 0; i < n; i++) q = wordEnd(t, q, k === "W");
          m = { to: q, inclusive: true };
        } else {
          m = motionFor(k, t, pos, n);
        }
        if (m) { applyMotion(m, pos); return; }
      }
    }
    S.count = "";
    refresh();
  }

  /* ------------------------------------------------------------ sequences -- */

  /* Graphide's key trees (gred-rs presets/gred.toml, the `gred` preset with
     editing = "vim", leader <Space>), owned here in Normal and Visual mode
     and, with nothing editable focused, everywhere in the app.

     T3's keybinding layer takes one chord per binding and no sequences, so a
     completed sequence is turned into one synthetic Ctrl+Alt+Shift chord
     dispatched at `window`, which ~/.t3/userdata/keybindings.json binds to the
     T3 command. Dispatched at window, T3's `editableFocus` context is false,
     and the event never reaches this file's own listener on `document` (and
     is untrusted besides), so it cannot feed back.

     Each row: the sequence in gred.toml notation, the chord key to dispatch
     (null where T3 has no counterpart: the sequence is still consumed, and a
     message says so), and gred.toml's which-key description. Rows are in
     gred.toml's order, which is the order the hint panel lists them in. */
  const SEQ_ROWS = [
    /* Graphide opens a fuzzy agent picker here. T3 has none: its command
       palette holds commands only, no threads, so pointing this at the
       palette put a wrong action under the key. <leader>1 to <leader>9 below
       are the switch that T3 can actually do. */
    ["<leader><leader>", null, "switch agent"],
    /* T3's thread.jump.1 to 9, which Graphide has no key for: the fast agent
       switch, under the leader so it is found beside the rest. */
    ["<leader>1", "1", "agent 1"],
    ["<leader>2", "2", "agent 2"],
    ["<leader>3", "3", "agent 3"],
    ["<leader>4", "4", "agent 4"],
    ["<leader>5", "5", "agent 5"],
    ["<leader>6", "6", "agent 6"],
    ["<leader>7", "7", "agent 7"],
    ["<leader>8", "8", "agent 8"],
    ["<leader>9", "9", "agent 9"],
    ["<leader>/", "/", "fuzzy find here"],
    ["<leader>sf", "f", "files"],
    ["<leader>sg", "g", "grep"],
    ["<leader>sw", null, "the word here"],
    ["<leader>sa", null, "agents' transcripts"],
    ["<leader>sh", null, "help"],
    ["<leader>sk", null, "keymaps"],
    ["<leader>sc", "c", "commands"],
    ["<leader>sm", null, "marks"],
    ["<leader>s.", null, "recent"],
    ["<leader>sp", ";", "recent projects"],
    ["<leader>sr", null, "resume the last search"],
    ["<leader>ss", null, "every search"],
    ["<leader>so", null, "settings"],
    ["<leader>an", "n", "new agent"],
    ["<leader>aN", "o", "new agent, the other of Claude Code and Codex"],
    ["<leader>ah", "m", "the new agent: Claude Code, Codex or a plugin's"],
    /* gred.toml binds agent.place to <C-,> as well, which keybindings.json
       sends to composer.workspace, so this is the same action by its tree key. */
    ["<leader>ai", ";", "where the new agent starts"],
    ["<leader>ad", null, "the agent definition the new agent starts as"],
    ["<leader>aL", null, "the launch script the new agent runs through"],
    ["<leader>ay", "y", "Skip permissions on or off for the new agent"],
    ["<leader>ar", null, "restart"],
    ["<leader>af", null, "fork the conversation"],
    ["<leader>aw", "w", "its worktree"],
    ["<leader>al", "l", "land its work"],
    ["<leader>am", "m", "its model and effort"],
    ["<leader>ae", "e", "step its effort"],
    ["<leader>aF", null, "fast mode on or off"],
    ["<leader>ak", "k", "stop"],
    ["<leader>ap", "p", "pause or resume"],
    ["<leader>aR", null, "resume agents stopped by a usage limit"],
    ["<leader>ab", null, "bump agents stopped by an API error"],
    ["<leader>ac", "h", "your other computers"],
    ["<leader>aT", "i", "pin to the top of the list, or unpin"],
    ["<leader>a!", null, "mark important, or not"],
    ["<leader>at", "t", "its terminal, or back to its page"],
    ["<leader>av", "v", "the list over the agent, or alone"],
    ["<leader>q", null, "requests for you"],
    ["<leader>m", null, "Graph"],
    ["<leader>T", null, "tests"],
    ["<leader>hs", null, "accept the hunk"],
    ["<leader>hr", null, "reject the hunk"],
    ["<leader>hS", null, "accept the file"],
    ["<leader>hR", null, "reject the file"],
    ["<leader>hu", null, "undo the last accept"],
    ["<leader>hp", "d", "preview the hunk"],
    ["<leader>hb", null, "which agent wrote this"],
    ["<leader>tt", "a", "dark or light theme"],
    ["<leader>tc", null, "buttons and keys in words, or neither"],
    ["<leader>tn", null, "Vim engine or Neovim"],
    ["<leader>tp", null, "frame times"],
    ["<leader>tm", null, "reduced motion"],
    ["<leader>tb", null, "agent blame"],
    ["<leader>tw", "r", "the next layout"],
    ["<leader>rn", null, "rename"],
    ["<leader>ds", null, "symbols here"],
    ["<leader>ws", null, "symbols everywhere"],
    ["<leader>D", null, "type definition"],
    ["<leader>cd", null, "the line's diagnostics"],
    ["<leader>ca", null, "code actions"],
    ["<leader>cf", null, "format the file"],

    /* T3's panes are a linear list, so left and up are the previous pane and
       right and down the next, the same approximation <C-h> and <C-l> make. */
    ["<C-w>h", "q", "focus left"],
    ["<C-w>j", "z", "focus down"],
    ["<C-w>k", "q", "focus up"],
    ["<C-w>l", "z", "focus right"],
    ["<C-w>s", "s", "split"],
    ["<C-w>v", "b", "split vertically"],
    ["<C-w>q", "x", "quit the pane"],
    ["<C-w>c", "x", "close the pane"],
    ["<C-w>o", null, "close every other pane"],
    ["<C-w>=", null, "equal sizes"],
    ["<C-w>x", null, "exchange with the next pane"],
    ["<C-w>H", null, "move to the far left"],
    ["<C-w>J", null, "move to the bottom"],
    ["<C-w>K", null, "move to the top"],
    ["<C-w>L", null, "move to the far right"],
    ["<C-w>>", null, "wider"],
    ["<C-w><lt>", null, "narrower"],
    ["<C-w>+", null, "taller"],
    ["<C-w>-", null, "shorter"],
    ["<C-w>T", "u", "into a new tab"],

    /* g is shared with the vim layer: only these second keys are the app's.
       Any other key after g (g u U ~ e E _) is replayed into vim's own g. */
    ["gt", ".", "next tab"],
    ["gT", ",", "previous tab"],
    ["ga", "j", "add to the composer's context"],
    ["gd", null, "definition"],
    ["gD", null, "declaration"],
    ["grr", null, "references"],
    ["gri", null, "implementations"],
    ["grt", null, "type definition"],
    ["grn", null, "rename"],
    ["gra", null, "code actions"],

    ["]q", null, "next request for you"],
    ["[q", null, "previous request for you"],
    ["]a", ".", "next running agent"],
    ["[a", ",", "previous running agent"],
    ["]d", null, "next diagnostic"],
    ["[d", null, "previous diagnostic"],
  ];

  /* gred.toml [groups], the which-key names of the prefixes. */
  const SEQ_GROUPS = {
    "<leader>": "Leader",
    "<leader>s": "[S]earch",
    "<leader>a": "[A]gents",
    "<leader>h": "Git [H]unk",
    "<leader>t": "[T]oggle",
    "<leader>r": "[R]ename",
    "<leader>d": "[D]ocument",
    "<leader>w": "[W]orkspace",
    "<leader>c": "[C]ode",
    "<C-w>": "Windows",
    "]": "Next",
    "[": "Previous",
    "g": "Go to",
    "gr": "Code",
  };

  /* gred notation -> the e.key values pressed. <C-w> stays one token. */
  function seqTokens(str) {
    const out = [];
    let s = String(str);
    while (s.length) {
      const m = /^<(leader|Space|C-w|lt|Esc)>/i.exec(s);
      if (m) {
        const w = m[1].toLowerCase();
        out.push(w === "leader" || w === "space" ? " " : w === "c-w" ? "<C-w>" : w === "lt" ? "<" : "Escape");
        s = s.slice(m[0].length);
      } else { out.push(s[0]); s = s.slice(1); }
    }
    return out;
  }
  const seqName = (toks) => toks.map((k) => (k === " " ? "<leader>" : k === "<" ? "<lt>" : k)).join("");

  /* The trie. A node is { kids: Map(key -> node), leaf: {chord, desc}|null,
     name: the sequence so far, group: its which-key name }. */
  const SEQ_ROOT = { kids: new Map(), leaf: null, name: "", group: "" };
  for (const [seq, chord, desc] of SEQ_ROWS) {
    const toks = seqTokens(seq);
    let n = SEQ_ROOT;
    for (let i = 0; i < toks.length; i++) {
      let c = n.kids.get(toks[i]);
      if (!c) {
        const name = seqName(toks.slice(0, i + 1));
        c = { kids: new Map(), leaf: null, name, group: SEQ_GROUPS[name] || "" };
        n.kids.set(toks[i], c);
      }
      n = c;
    }
    n.leaf = { chord, desc };
  }
  /* Bare keys that start a tree. Nothing else bare is taken, so T3's own
     bare keys (the usage page's c, t, l) keep working. */
  const SEQ_STARTS = new Set([" ", "g", "]", "["]);

  const MOD_KEYS = /^(Shift|Control|Alt|AltGraph|Meta|OS|CapsLock|NumLock|ScrollLock|Fn|Hyper|Super)$/;

  const SEQ = {
    node: null,      // the pending trie node, null when nothing is pending
    local: false,    // started in the composer (so a bare g can go back to vim)
    timer: 0,
    flash: "",       // a short message for the hint panel
    flashTimer: 0,
    show: false,     // the hint panel has waited HINT_DELAY_MS and may paint
    showTimer: 0,
    sent: 0,         // chords dispatched, for the tests
  };

  function seqCancel() {
    SEQ.node = null; SEQ.local = false;
    if (SEQ.timer) { clearTimeout(SEQ.timer); SEQ.timer = 0; }
    SEQ.show = false;
    if (SEQ.showTimer) { clearTimeout(SEQ.showTimer); SEQ.showTimer = 0; }
  }

  /* The panel waits before it paints, as Graphide's which-key bar waits
     timeoutlen. <C-w>h and <leader>sf are typed faster than this, so they
     never flash a panel; a prefix you stop on still explains itself. The
     sequence itself is never delayed, only the drawing of it. */
  function seqArmHint() {
    if (SEQ.showTimer) clearTimeout(SEQ.showTimer);
    SEQ.showTimer = setTimeout(() => {
      SEQ.showTimer = 0;
      if (SEQ.node) { SEQ.show = true; refresh(); }
    }, HINT_DELAY_MS);
  }

  function seqFlash(msg) {
    SEQ.flash = msg;
    if (SEQ.flashTimer) clearTimeout(SEQ.flashTimer);
    SEQ.flashTimer = setTimeout(() => { SEQ.flash = ""; SEQ.flashTimer = 0; refresh(); }, FLASH_MS);
  }

  const composerVim = () => !!(S.el && S.el.isConnected && S.mode !== INSERT);

  function seqArm() {
    seqArmHint();
    if (SEQ.timer) clearTimeout(SEQ.timer);
    SEQ.timer = setTimeout(() => {
      SEQ.timer = 0;
      const n = SEQ.node, local = SEQ.local;
      seqCancel();
      /* A lone g that timed out is still vim's g: gg must not depend on
         typing speed. */
      if (n && n.name === "g" && local && composerVim()) S.pending = "g";
      refresh();
    }, SEQ_TIMEOUT_MS);
  }

  function seqStart(key, local) {
    SEQ.node = SEQ_ROOT.kids.get(key) || null;
    SEQ.local = !!local;
    SEQ.flash = "";
    if (SEQ.node) seqArm();
    refresh();
  }

  const CHORD_CODES = { "/": "Slash", ".": "Period", ",": "Comma" };
  const chordCode = (key) =>
    CHORD_CODES[key] ||
    (/^[a-z]$/.test(key) ? "Key" + key.toUpperCase() : /^[0-9]$/.test(key) ? "Digit" + key : "");

  /* The one way this file talks to T3's command layer: a synthetic chord at
     window, which keybindings.json maps to a T3 command. */
  function dispatchChord(key) {
    SEQ.sent++;
    window.dispatchEvent(new KeyboardEvent("keydown", {
      key,
      code: chordCode(key),
      bubbles: true,
      cancelable: true,
      ctrlKey: true,
      altKey: true,
      shiftKey: true,
    }));
  }

  /* One key into the pending sequence. */
  function seqStep(k) {
    const at = SEQ.node, local = SEQ.local;
    const next = at && at.kids.get(k);
    if (!next) {
      seqCancel();
      if (at && at.name === "g" && local && composerVim()) {
        /* gg gu gU g~ ge gE g_: vim's g, as if the app tree were not there. */
        S.pending = "g";
        handleKey(k);
        return;
      }
      S.count = "";
      seqFlash(seqName([...seqTokens(at ? at.name : ""), k]) + " is not mapped");
      refresh();
      return;
    }
    if (next.kids.size) { SEQ.node = next; seqArm(); refresh(); return; }
    seqCancel();
    S.count = "";
    if (next.leaf && next.leaf.chord) dispatchChord(next.leaf.chord);
    else seqFlash(next.name + " (" + (next.leaf ? next.leaf.desc : "") + "): no T3 equivalent");
    refresh();
  }

  /* A key while a sequence is pending. Returns "eat" when the key was taken,
     "skip" for a bare modifier (the sequence stays pending), or "pass" when
     the sequence was dropped and the key should be handled as usual. */
  function seqPendingKey(e) {
    let k = e.key;
    if (k === "Escape" || (e.ctrlKey && !e.altKey && !e.metaKey && k === "[")) {
      seqCancel(); refresh(); return "eat";
    }
    if (MOD_KEYS.test(k)) return "skip";
    /* A held key's auto-repeat must not walk the tree (a held Space would
       otherwise be <leader><leader>). */
    if (e.repeat) return "eat";
    if (e.ctrlKey || e.metaKey || e.altKey) {
      /* <C-w><C-s> is <C-w>s, as in vim. */
      const inWin = SEQ.node && SEQ.node.name.startsWith("<C-w>");
      if (!(inWin && e.ctrlKey && !e.altKey && !e.metaKey && k.length === 1)) {
        seqCancel(); refresh(); return "pass";
      }
    }
    if (k.length !== 1) { seqCancel(); refresh(); return "pass"; }
    seqStep(k);
    return "eat";
  }

  /* What the hint panel shows: the pending prefix's next keys, or a message. */
  function seqHint() {
    if (SEQ.node && SEQ.show) {
      const items = [];
      for (const [k, n] of SEQ.node.kids) {
        items.push({
          key: k === " " ? "SPC" : k,
          desc: n.kids.size ? "+" + (n.group || "more") : n.leaf ? n.leaf.desc : "",
          none: !n.kids.size && !(n.leaf && n.leaf.chord),
        });
      }
      return { title: SEQ.node.name + (SEQ.node.group ? "  " + SEQ.node.group : ""), items, message: "" };
    }
    if (SEQ.flash) return { title: "", items: [], message: SEQ.flash };
    return null;
  }

  /* Where every key belongs to the focused thing: anything that takes text,
     and widgets with their own key handling (menus with typeahead, listboxes,
     dialogs, the terminal). The composer is handled before this. A letter
     here is a letter, so the list keys below stand aside on it too: a thread
     being renamed is an input inside a list row. */
  const TEXT_KEYS = [
    "input", "textarea", "select", "[contenteditable]:not([contenteditable='false'])",
    "[role='textbox']", "[role='combobox']", "[role='searchbox']", "[role='spinbutton']",
    "[role='slider']", "[role='menu']", "[role='menubar']", "[role='listbox']",
    "[role='dialog']", "[role='alertdialog']", ".xterm",
  ].join(",");

  /* Space activates these, everywhere on the web. Taking the leader over them
     would break a focused button for the sake of a leader nobody presses with
     a button focused. Enter and PageDown are unaffected. */
  const ACTIVATE_KEYS = [
    "button", "summary", "[role='button']", "[role='checkbox']",
    "[role='radio']", "[role='switch']", "[role='tab']", "[role='option']",
    "[role='treeitem']", "[role='menuitem']", "[role='menuitemcheckbox']",
    "[role='menuitemradio']",
  ].join(",");

  const NATIVE_KEYS = TEXT_KEYS + "," + ACTIVATE_KEYS;

  /* ----------------------------------------------------------- lists ----- */

  /* T3's thread lists (the sidebar, and the thread panel, which is the same
     row component) are a roving-tabindex list: each row is a
     `div role="button" tabindex="0" data-sidebar-row="..."`, and T3 listens
     on the list's container, in the capture phase, for ArrowUp, ArrowDown,
     ArrowLeft, ArrowRight, Home and End. workspace.focusPrevious (<C-h>)
     lands on the current row, and from there Graphide moves with j and k.

     Every row is a button, so NATIVE_KEYS below stands the trees aside on it,
     which is right for Space: it activates the focused row. j and k are not
     Space. They are translated into the arrows T3 already handles rather than
     reimplemented here, so collapsing a group, loading more and the scroll
     into view stay T3's own behaviour, and a release that changes the list
     changes these keys with it.

     The settings page's navigation is the same pattern on
     `[data-settings-section]`, with no Left or Right, so h and l do nothing
     there. Those two are the only lists T3 drives this way; its pickers and
     menus are listboxes behind a text field, where a letter has to stay a
     letter. */
  const LIST_SEL = "[data-sidebar-row], [data-settings-section]";
  const LIST_ARROWS = {
    j: "ArrowDown", k: "ArrowUp",
    h: "ArrowLeft", l: "ArrowRight",   /* out of a group, into one */
    G: "End",                          /* gg is below: it needs a pending g */
  };
  const LIST = { g: 0, sent: 0 };

  /* The arrow T3's own list handler is waiting for. Dispatched at the row, so
     the container's capture listener sees it with the row as its target; it
     carries no modifier, which is what that handler requires. */
  function listMove(row, key) {
    LIST.sent++;
    row.dispatchEvent(new KeyboardEvent("keydown", {
      key, code: key, bubbles: true, cancelable: true,
    }));
  }

  /* One key with a list row focused. True when the key was taken. */
  function listKey(e, row) {
    if (e.ctrlKey || e.metaKey || e.altKey) return false;   /* T3's own chords */
    const k = e.key;
    if (k === "g" && !e.shiftKey) {
      if (e.repeat) return true;                            /* a held g is not gg */
      if (LIST.g && Date.now() - LIST.g < SEQ_TIMEOUT_MS) {
        LIST.g = 0; listMove(row, "Home"); return true;
      }
      LIST.g = Date.now();
      return true;
    }
    LIST.g = 0;
    const arrow = LIST_ARROWS[k];
    if (!arrow) return false;        /* Space, Enter, everything else: T3's */
    listMove(row, arrow);
    return true;
  }

  /* ------------------------------------------------------------------- ui -- */

  let badge = null, blockEl = null, keysEl = null, keysShown = "", styled = false;

  function ui() {
    if (styled) return;
    styled = true;
    const css = document.createElement("style");
    css.textContent = [
      ".t3vim-badge{position:fixed;z-index:2147483000;pointer-events:none;",
      "font:600 9.5px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.09em;",
      "padding:3px 6px;border-radius:4px;text-transform:uppercase;white-space:nowrap;",
      "background:var(--primary,#4fa396);color:var(--primary-foreground,#04120f);opacity:.95}",
      '.t3vim-badge[data-mode="INSERT"]{background:transparent;opacity:.5;',
      "color:var(--muted-foreground,#75838b);box-shadow:inset 0 0 0 1px currentColor}",
      ".t3vim-block{position:fixed;z-index:2147482999;pointer-events:none;border-radius:1px;",
      "background:var(--primary,#4fa396);opacity:.3}",
      ".t3vim-normal{caret-color:transparent !important}",
      /* The which-key panel: fixed, bottom-anchored, so it never needs its own
         height measured. */
      ".t3vim-keys{position:fixed;z-index:2147483001;pointer-events:none;display:none;",
      "max-width:min(620px,calc(100vw - 16px));box-sizing:border-box;padding:6px 8px;border-radius:6px;",
      "font:500 11px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;",
      "background:var(--popover,#10181c);color:var(--popover-foreground,#d5dde1);",
      "box-shadow:0 0 0 1px var(--border,#2a363c),0 6px 18px rgba(0,0,0,.35)}",
      ".t3vim-keys-title{font-weight:700;color:var(--primary,#4fa396);margin-bottom:3px}",
      ".t3vim-keys-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));column-gap:14px}",
      ".t3vim-keys-row{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
      ".t3vim-keys-row b{display:inline-block;min-width:3ch;color:var(--primary,#4fa396)}",
      ".t3vim-keys-row.none{opacity:.45}",
    ].join("");
    document.head.appendChild(css);
    badge = document.createElement("div");
    badge.className = "t3vim-badge";
    blockEl = document.createElement("div");
    blockEl.className = "t3vim-block";
    keysEl = document.createElement("div");
    keysEl.className = "t3vim-keys";
    document.body.appendChild(badge);
    document.body.appendChild(blockEl);
    document.body.appendChild(keysEl);
  }

  function hideUI() {
    if (badge) badge.style.display = "none";
    if (blockEl) blockEl.style.display = "none";
    document.querySelectorAll(".t3vim-normal").forEach((n) => n.classList.remove("t3vim-normal"));
  }

  let pending = false;
  function refresh() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      try { paintKeys(); } catch { /* never let the UI break editing */ }
      try { paint(); } catch { /* never let the UI break editing */ }
    });
  }

  /* The which-key panel. Its content is rebuilt only when what it shows
     changes; each paint just places it. Shown with or without a composer,
     since the trees work app-wide. */
  function paintKeys() {
    const h = S.on ? seqHint() : null;
    if (!h) { if (keysEl) keysEl.style.display = "none"; keysShown = ""; return; }
    ui();
    const sig = h.message || h.title;
    if (sig !== keysShown) {
      keysShown = sig;
      keysEl.textContent = "";
      if (h.message) {
        keysEl.textContent = h.message;
      } else {
        const title = document.createElement("div");
        title.className = "t3vim-keys-title";
        title.textContent = h.title;
        const grid = document.createElement("div");
        grid.className = "t3vim-keys-grid";
        for (const it of h.items) {
          const row = document.createElement("div");
          row.className = "t3vim-keys-row" + (it.none ? " none" : "");
          const b = document.createElement("b");
          b.textContent = it.key;
          row.appendChild(b);
          row.appendChild(document.createTextNode(" " + it.desc + (it.none ? " (no T3 equivalent)" : "")));
          grid.appendChild(row);
        }
        keysEl.appendChild(title);
        keysEl.appendChild(grid);
      }
    }
    const anchor = S.el && S.el.isConnected ? (S.el.closest(FORM_SEL) || S.el) : null;
    if (anchor) {
      const fr = anchor.getBoundingClientRect();
      keysEl.style.left = Math.max(8, fr.left + 8) + "px";
      keysEl.style.bottom = Math.max(8, window.innerHeight - fr.top + 14) + "px";
    } else {
      keysEl.style.left = "16px";
      keysEl.style.bottom = "16px";
    }
    keysEl.style.display = "block";
  }

  function paint() {
    if (!S.on || !S.el || !S.el.isConnected) { hideUI(); return; }
    ui();

    const form = S.el.closest(FORM_SEL) || S.el;
    const fr = form.getBoundingClientRect();
    const label = S.mode
      + (S.operator ? " " + S.operator : "")
      + (S.useClip ? ' "+' : "")
      + ((S.opCount + S.count) ? " " + (S.opCount + S.count) : "")
      + (SEQ.node ? " " + SEQ.node.name : "");
    badge.style.display = "block";
    badge.dataset.mode = S.mode;
    badge.textContent = label;
    badge.style.left = Math.max(4, fr.left + 8) + "px";
    badge.style.top = Math.max(4, fr.top - 9) + "px";

    if (S.mode === INSERT) {
      S.el.classList.remove("t3vim-normal");
      blockEl.style.display = "none";
      return;
    }
    S.el.classList.add("t3vim-normal");

    const ctx = here();
    if (!ctx) { blockEl.style.display = "none"; return; }
    const p = S.mode === NORMAL ? clampNormal(ctx.map, ctx.pos) : S.vpos;
    const t = ctx.map.text;
    let rect = null;
    try {
      const r = document.createRange();
      if (t[p] !== undefined && t[p] !== "\n") {
        const A = posToDom(ctx.map, p), B = posToDom(ctx.map, p + 1);
        r.setStart(A.node, A.offset); r.setEnd(B.node, B.offset);
        const rr = r.getBoundingClientRect();
        if (rr.width > 0 && rr.height > 0) rect = rr;
      }
      if (!rect) {
        const A = posToDom(ctx.map, p);
        r.setStart(A.node, A.offset); r.setEnd(A.node, A.offset);
        const rr = r.getBoundingClientRect();
        rect = { left: rr.left, top: rr.top, width: 7.5, height: rr.height || 16 };
      }
    } catch { blockEl.style.display = "none"; return; }

    const er = S.el.getBoundingClientRect();
    if (rect.top < er.top - 2 || rect.bottom > er.bottom + 2) { blockEl.style.display = "none"; return; }
    blockEl.style.display = "block";
    blockEl.style.left = rect.left + "px";
    blockEl.style.top = rect.top + "px";
    blockEl.style.width = Math.max(2, rect.width) + "px";
    blockEl.style.height = rect.height + "px";
  }

  /* -------------------------------------------------------------- wiring -- */

  const activeEditable = () => {
    const a = document.activeElement;
    if (!a) return null;
    if (a.classList && a.classList.contains("composer-tiptap")) return a;
    return a.closest ? a.closest(EDITABLE_SEL) : null;
  };

  const eat = (e) => { e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); };

  /* Keys with no composer focused: the sequence engine and the list keys run,
     and only where the focused thing does not want the keys itself. Space is
     taken as the leader even inside a scrollable area, so it no longer pages
     one; PageDown still does. */
  function onGlobalKey(e) {
    if (e.defaultPrevented) return;
    const t = e.target && e.target.nodeType === 1 ? e.target : document.activeElement;
    const f = document.activeElement;
    /* A focused list row, with no sequence pending: j k h l gg G move in it.
       A pending sequence keeps its keys and falls through to be cancelled, as
       any other focus that wants its own keys does. */
    const takesText = (t && t.closest && t.closest(TEXT_KEYS)) || (f && f.closest && f.closest(TEXT_KEYS));
    if (!SEQ.node && !takesText) {
      const row = (f && f.closest && f.closest(LIST_SEL)) || (t && t.closest && t.closest(LIST_SEL));
      if (row && listKey(e, row)) { eat(e); return; }
    }
    if ((t && t.closest && t.closest(NATIVE_KEYS)) || (f && f.closest && f.closest(NATIVE_KEYS))) {
      if (SEQ.node) { seqCancel(); refresh(); }
      return;
    }
    const k = e.key;
    if (SEQ.node) {
      const r = seqPendingKey(e);
      if (r === "eat") eat(e);
      return;
    }
    if (e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey && k === "w") { eat(e); seqStart("<C-w>", false); return; }
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (SEQ_STARTS.has(k)) { eat(e); seqStart(k, false); }
  }

  function onKeyDown(e) {
    if (!S.on || !e.isTrusted) return;
    const el = activeEditable();
    if (!el) {
      if (S.el) { S.el = null; hideUI(); }
      onGlobalKey(e);
      return;
    }
    if (S.el !== el) { S.el = el; S.mode = INSERT; seqCancel(); }

    const k = e.key;
    const ctrlOnly = e.ctrlKey && !e.altKey && !e.metaKey;

    /* A pending sequence sees the key before anything else, Escape included. */
    if (SEQ.node && S.mode !== INSERT) {
      const r = seqPendingKey(e);
      if (r === "eat") { eat(e); return; }
      if (r === "skip") return;
    }

    if (k === "Escape" || (ctrlOnly && k === "[")) {
      if (S.mode === INSERT) {
        if (S.rec && S.dot) S.dot.insert = S.rec.join("");
        const m = scan(S.el), c = here();
        S.mode = NORMAL; S.rec = null;
        if (c) caretTo(m, clampNormal(m, Math.max(lineStart(m.text, c.pos), c.pos - 1)));
        refresh(); eat(e); return;
      }
      if (S.mode === VISUAL || S.mode === VLINE) { setMode(NORMAL); collapse(); refresh(); eat(e); return; }
      if (S.count || S.opCount || S.operator || S.pending) { reset(); refresh(); eat(e); return; }
      return;                               /* NORMAL, nothing pending: T3 keeps Escape */
    }

    if (S.mode === INSERT) {
      if (S.rec && !e.ctrlKey && !e.metaKey && !e.altKey) {
        if (k.length === 1) S.rec.push(k);
        else if (k === "Backspace") S.rec.pop();
        else if (k === "Enter") S.rec = null;
      }
      return;                               /* insert mode behaves as T3 intends */
    }

    if (ctrlOnly && (k === "r" || k === "R")) {
      const n = takeCount();
      for (let i = 0; i < n; i++) redo();
      setMode(NORMAL); refresh(); eat(e); return;
    }
    const free = !S.operator && !S.pending;  /* not mid-command: f<Space>, r], di[ stay vim's */
    if (ctrlOnly && !e.shiftKey && k === "w" && free) { eat(e); seqStart("<C-w>", true); return; }
    if (e.ctrlKey || e.metaKey || e.altKey) return;   /* T3's own keybindings */
    if (k === "Enter") { setMode(INSERT); return; }   /* let T3 send */
    if (k === "Tab") return;

    if (k.length !== 1) {
      if (k === "Backspace") { eat(e); handleKey("h"); return; }
      return;                               /* arrows, Home/End, F-keys: native */
    }

    eat(e);
    if (free && SEQ_STARTS.has(k)) { seqStart(k, true); return; }
    /* Graphide's `:` command line. T3's own `:` binding is guarded
       !editableFocus, which the focused composer fails, so send the command
       palette's chord from here, where editableFocus reads false. */
    if (free && k === ":") { S.count = ""; dispatchChord("c"); refresh(); return; }
    try { handleKey(k); } catch { reset(); refresh(); }
  }

  /* On window, capture phase: this script runs before T3's module bundle, so
     it is registered ahead of T3's own window-capture key handlers and a key
     it eats mid-sequence (the t of <leader>tt) never reaches them. The
     synthetic chords it dispatches at window come back through here
     untrusted, and the isTrusted check drops them. */
  window.addEventListener("keydown", onKeyDown, true);
  document.addEventListener("focusin", () => {
    const el = activeEditable();
    if (el) { if (S.el !== el) { S.el = el; S.mode = INSERT; reset(); seqCancel(); } refresh(); }
    else { S.el = null; hideUI(); }
  }, true);
  document.addEventListener("selectionchange", () => { if (S.el && S.mode !== INSERT) refresh(); });
  window.addEventListener("resize", refresh, { passive: true });
  window.addEventListener("scroll", refresh, { passive: true, capture: true });

  window.__t3vim = {
    get state() { return { on: S.on, mode: S.mode, count: S.count, operator: S.operator, pending: S.pending, seq: SEQ.node ? SEQ.node.name : "" }; },

    /* Drive the handler without a real keypress. Used by the test page in
       this directory, and handy in devtools. */
    feed(key, mods) {
      const m = mods || {};
      onKeyDown({
        isTrusted: true,
        target: document.activeElement,
        defaultPrevented: false,
        key,
        ctrlKey: !!m.ctrl, shiftKey: !!m.shift, altKey: !!m.alt, metaKey: !!m.meta,
        repeat: !!m.repeat,
        preventDefault() {}, stopPropagation() {}, stopImmediatePropagation() {},
      });
      return this.debug();
    },
    feedKeys(str) {
      for (const ch of String(str)) this.feed(ch);
      return this.debug();
    },
    /* Feed a sequence in gred.toml notation: "<leader>sf", "<C-w>s", "gt". */
    feedSeq(str) {
      for (const k of seqTokens(str)) {
        if (k === "<C-w>") this.feed("w", { ctrl: true });
        else this.feed(k, k.length === 1 && k !== k.toLowerCase() ? { shift: true } : undefined);
      }
      return this.debug();
    },
    hint() { return seqHint(); },
    paintNow() { paintKeys(); paint(); },
    /* Fire the hint panel's HINT_DELAY_MS wait at once, so a test can check
       the panel without sleeping for it. */
    showHintNow() {
      if (SEQ.showTimer) { clearTimeout(SEQ.showTimer); SEQ.showTimer = 0; }
      if (SEQ.node) { SEQ.show = true; refresh(); }
      return seqHint();
    },
    get sent() { return SEQ.sent; },
    get listSent() { return LIST.sent; },
    seqTimeoutMs: SEQ_TIMEOUT_MS,
    debug() {
      const c = here();
      if (!c) return { mode: S.mode, seq: SEQ.node ? SEQ.node.name : "", count: S.count, pending: S.pending };
      return {
        text: c.map.text,
        pos: S.mode === NORMAL ? clampNormal(c.map, c.pos) : c.pos,
        mode: S.mode, vpos: S.vpos, anchor: S.anchor,
        reg: S.reg, count: S.count, operator: S.operator, pending: S.pending,
        seq: SEQ.node ? SEQ.node.name : "",
      };
    },
    setCaret(p) { const m = scan(S.el); caretTo(m, p); S.mode = NORMAL; refresh(); return this.debug(); },
    attach(el) { S.el = el; S.mode = NORMAL; reset(); seqCancel(); return this.debug(); },
    enable() { S.on = true; lsSet(SWITCH, "on"); refresh(); return "vim mode on"; },
    disable() { S.on = false; lsSet(SWITCH, "off"); S.mode = INSERT; hideUI(); return "vim mode off, composer is a plain text box again"; },
    version: 2,
  };
})();
