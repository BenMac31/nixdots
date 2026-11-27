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

  /* Graphide's `timeoutlen`, whose default is 300 ms (gred's config.rs). It
     is both how long a pending prefix waits before the which-key bar comes
     up, and the one wait modal::Resolver makes: "A sequence that is bound
     and also starts a longer one waits for the timeout, Vim's timeoutlen,
     then runs. One that only leads on waits as long as it takes where
     commands are typed, while the which-key bar shows what can follow."

     So <leader> and <C-w> wait for their next key as long as it takes, and
     only g, which is vim's own command as well as the app's prefix, is on a
     clock. */
  const TIMEOUTLEN_MS = 300;
  /* How long a "no T3 equivalent" or "not mapped" message stays up. */
  const FLASH_MS = 1600;

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

  /* Vim's three erasers while typing: <C-h> a character, <C-w> a word, <C-u>
     back to the start of the line. Graphide's own line editor has the same
     three (ui/src/line.rs: "Deletes the word before the cursor and the
     blanks after it (<C-w>)"), and T3 has none of them - it binds mod+w to
     closing a pane, mod+h to the pane ring and mod+u to the usage page, so
     all three fired the app instead of editing the text. */
  function eraseBack(what) {
    const c = here();
    if (!c) return false;
    const m = c.map, p = c.pos;
    if (p <= 0) return true;
    let to = what === "word" ? wordBack(m.text, p, false)
      : what === "line" ? lineStart(m.text, p)
      : p - 1;
    if (to >= p) to = p - 1;
    cut(m, to, p);
    const n = scan(S.el);
    caretTo(n, clamp(to, 0, n.text.length));
    return true;
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

    /* The direction is worked out from where the panes are, not from T3's
       ring: see the panes section below. */
    ["<C-w>h", "@pane.left", "focus left"],
    ["<C-w>j", "@pane.down", "focus down"],
    ["<C-w>k", "@pane.up", "focus up"],
    ["<C-w>l", "@pane.right", "focus right"],
    /* Vim's own next and previous window. gred leaves them out, but a dead
       <C-w>w is worse than the ring, which is the one movement T3 has. */
    ["<C-w>w", "@pane.next", "the next pane"],
    ["<C-w>p", "@pane.prev", "the previous pane"],
    ["<C-w>s", "s", "split"],
    ["<C-w>v", "b", "split vertically"],
    ["<C-w>q", "@pane.close", "quit the pane"],
    ["<C-w>c", "@pane.close", "close the pane"],
    ["<C-w>o", "@pane.only", "close every other pane"],
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
  for (const [seq, to, desc] of SEQ_ROWS) {
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
    /* A row points at a T3 command by its chord, or at one of this file's own
       acts by @name (the panes), or at nothing T3 has. */
    n.leaf = to && to[0] === "@" ? { chord: null, act: to.slice(1), desc } : { chord: to, act: null, desc };
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
    show: false,     // the hint panel has waited TIMEOUTLEN_MS and may paint
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
    }, TIMEOUTLEN_MS);
  }

  function seqFlash(msg) {
    SEQ.flash = msg;
    if (SEQ.flashTimer) clearTimeout(SEQ.flashTimer);
    SEQ.flashTimer = setTimeout(() => { SEQ.flash = ""; SEQ.flashTimer = 0; refresh(); }, FLASH_MS);
  }

  const composerVim = () => !!(S.el && S.el.isConnected && S.mode !== INSERT);

  /* Only a prefix that is also a command of its own is on a clock: g, which
     vim has as well. A prefix that only leads on waits for its next key as
     long as it takes, with the which-key bar up, as gred's resolver does. */
  function seqArm() {
    seqArmHint();
    if (SEQ.timer) { clearTimeout(SEQ.timer); SEQ.timer = 0; }
    if (!(SEQ.node && SEQ.node.name === "g" && SEQ.local && composerVim())) return;
    SEQ.timer = setTimeout(() => {
      SEQ.timer = 0;
      const n = SEQ.node, local = SEQ.local;
      seqCancel();
      /* A lone g that timed out is still vim's g: gg must not depend on
         typing speed. */
      if (n && n.name === "g" && local && composerVim()) S.pending = "g";
      refresh();
    }, TIMEOUTLEN_MS);
  }

  function seqStart(key, local) {
    SEQ.node = SEQ_ROOT.kids.get(key) || null;
    SEQ.local = !!local;
    SEQ.flash = "";
    if (SEQ.node) seqArm();
    refresh();
  }

  const CHORD_CODES = {
    "/": "Slash", ".": "Period", ",": "Comma", ";": "Semicolon",
    "-": "Minus", "=": "Equal", "[": "BracketLeft", "]": "BracketRight",
    "'": "Quote",
  };
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

  /* What a leaf of either tree does. */
  function seqFire(leaf, name) {
    if (leaf && leaf.row) return listRun1(listFocused(), leaf.row);
    if (leaf && leaf.act) { SEQ_ACTS[leaf.act](); return true; }
    if (leaf && leaf.chord) { dispatchChord(leaf.chord); return true; }
    seqFlash(name + " (" + (leaf ? leaf.desc : "") + "): no T3 equivalent");
    return true;
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
      /* Nothing of the app's: the focused surface's own keys after a prefix.
         Graphide resolves these the same way round, the keymap first and the
         surface's keys after it - the list's gg, gp, ]c, and the
         conversation's gg and its ] and [ walks. */
      if (at && !local) {
        const row = listFocused();
        if (row && listSeq(at.name, k, row)) { S.count = ""; refresh(); return; }
        if (!row && pageSeq(at.name, k)) { S.count = ""; refresh(); return; }
      }
      S.count = "";
      seqFlash(seqName([...seqTokens(at ? at.name : ""), k]) + " is not mapped");
      refresh();
      return;
    }
    if (next.kids.size) { SEQ.node = next; seqArm(); refresh(); return; }
    seqCancel();
    S.count = "";
    seqFire(next.leaf, next.name);
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

  /* What the which-key bar shows: a line per key that continues the pending
     prefix. gred's Hint is {keys, label, group}, the label being the group's
     name where the keys lead to more keys and the binding's description
     where they do not. What gred says in words it says on the message line,
     not here. */
  /* Whether a leaf reaches anything here, which is what the which-key bar
     greys a key out for. */
  const seqDoes = (leaf) =>
    !!leaf && !!(leaf.chord || leaf.act || (leaf.row && leaf.row[1] !== null));

  function seqHint() {
    if (!SEQ.node || !SEQ.show) return null;
    const items = [];
    for (const [k, n] of SEQ.node.kids) {
      items.push({
        key: k === " " ? "<Space>" : k,
        desc: n.kids.size ? (n.group || "more") : n.leaf ? n.leaf.desc : "",
        group: !!n.kids.size,
        none: !n.kids.size && !seqDoes(n.leaf),
      });
    }
    return { title: SEQ.node.name, items };
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

  /* ----------------------------------------------------------- panes ----- */

  /* Graphide's panes (gred/src/panes.rs), over T3's workspace areas.

     T3 marks each region of the window with `data-workspace-area` (its name)
     and `data-workspace-order` (its place in the ring workspace.focusNext
     walks): sidebar 0, conversation 1, composer 2, details 3, panel 4,
     terminal 5. That ring is a list. <C-w>h and friends are not a list: gred
     picks the pane the eye picks, and `panes.rs::nearest` says which that is
     - of the panes lying that way, the closest whose span crosses the
     focused pane's centre line, else the closest at all.

     Pointing all four at focusNext and focusPrevious, which is what this did,
     made <C-w>h and <C-w>k one key and <C-w>j and <C-w>l another: from the
     sidebar <C-w>j walked into the chat, and <C-w>k walked back out of it.
     So the direction is settled here, from the rectangles, and T3's ring is
     then stepped until the focus arrives - rather than focusing an element
     directly - so T3 keeps its own memory of where the focus stood in each
     area, and its focus-visible outline lands with it. */
  const PANE_SEL = "[data-workspace-area]";
  /* T3's own test for an area that is really there, copied from its focus
     module: each of these ancestors puts an area away, a collapsed sidebar
     among them. */
  const PANE_AWAY = [
    "[hidden]", "[inert]", "[data-closed]", '[aria-hidden="true"]',
    '[data-chat-column-maximized-away="true"]',
    '[data-slot="sidebar"][data-state="collapsed"]',
    '[data-workspace-unavailable="true"]',
  ].join(",");
  /* panes.rs: `const EPS: f32 = 0.5`, so a shared border counts as touching. */
  const PANE_EPS = 0.5;
  const PANE_WORD = { h: "to the left", j: "below", k: "above", l: "to the right" };

  function paneShows(el) {
    if (!el.isConnected || el.closest(PANE_AWAY)) return false;
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden") return false;
    return Array.from(el.getClientRects()).some((r) => r.width > 0 && r.height > 0);
  }

  /* The ring, as T3 walks it: the areas that show, in order. Sorted the same
     way, so an index here is an index there. */
  function panes() {
    const out = [];
    for (const el of document.querySelectorAll(PANE_SEL)) {
      if (!paneShows(el)) continue;
      out.push({
        el,
        name: el.dataset.workspaceArea || "",
        order: Number(el.dataset.workspaceOrder),
        r: el.getBoundingClientRect(),
      });
    }
    out.sort((a, b) => a.order - b.order);
    return out;
  }

  const paneOf = (el) => (el && el.closest ? el.closest(PANE_SEL) : null);
  const paneHere = (list) => {
    const el = paneOf(document.activeElement);
    return el ? list.find((p) => p.el === el) || null : null;
  };

  /* panes.rs::lies_toward. */
  function paneToward(at, r, dir) {
    if (dir === "h") return r.right <= at.left + PANE_EPS;
    if (dir === "l") return r.left >= at.right - PANE_EPS;
    if (dir === "k") return r.bottom <= at.top + PANE_EPS;
    return r.top >= at.bottom - PANE_EPS;
  }

  /* panes.rs::nearest, with its key of (does it cross the centre line, the
     gap, the distance off that line). */
  function paneNearest(list, from, dir) {
    const at = from.r;
    const cx = at.left + at.width / 2, cy = at.top + at.height / 2;
    const across = dir === "h" || dir === "l";
    const key = (r) => [
      (across ? r.top <= cy && cy <= r.bottom : r.left <= cx && cx <= r.right) ? 0 : 1,
      dir === "h" ? at.left - r.right : dir === "l" ? r.left - at.right
        : dir === "k" ? at.top - r.bottom : r.top - at.bottom,
      across ? Math.abs((r.top + r.bottom) / 2 - cy) : Math.abs((r.left + r.right) / 2 - cx),
    ];
    const under = (a, b) => a[0] < b[0] || (a[0] === b[0] && (a[1] < b[1] || (a[1] === b[1] && a[2] < b[2])));
    let best = null, mark = null;
    for (const p of list) {
      if (p === from || !paneToward(at, p.r, dir)) continue;
      const k = key(p.r);
      if (!mark || under(k, mark)) { best = p; mark = k; }
    }
    return best;
  }

  const PANE = { sent: 0 };

  /* Step T3's own ring until the focus is in `to`, the short way round. */
  function paneStepTo(list, from, to) {
    const i = list.indexOf(from), j = list.indexOf(to);
    if (i < 0 || j < 0 || i === j) return false;
    const n = list.length;
    const fwd = (j - i + n) % n;
    const next = fwd <= (i - j + n) % n;
    const steps = next ? fwd : (i - j + n) % n;
    for (let s = 0; s < steps; s++) {
      PANE.sent++;
      dispatchChord(next ? "z" : "q");
      if (paneOf(document.activeElement) === to.el) return true;
    }
    return paneOf(document.activeElement) === to.el;
  }

  function paneGo(dir) {
    const list = panes();
    const from = paneHere(list);
    /* Nothing focused in any area: the ring's own first step, which is what
       T3 does from the body. */
    if (!from) { PANE.sent++; dispatchChord(dir === "h" || dir === "k" ? "q" : "z"); return true; }
    const to = paneNearest(list, from, dir);
    if (!to) { seqFlash("no pane " + PANE_WORD[dir]); return true; }
    if (!paneStepTo(list, from, to)) {
      /* The ring would not take it there: focus the area itself, which is
         what T3 falls back to when it finds nothing better inside one. */
      try { to.el.focus({ preventScroll: true }); } catch { /* not focusable */ }
    }
    return true;
  }

  /* <C-w>w and <C-w>p: the ring itself. Vim's own keys for the next and
     previous window, and the only movement T3 has a command for. */
  const paneRing = (d) => { PANE.sent++; dispatchChord(d > 0 ? "z" : "q"); return true; };

  /* <C-w>c and <C-w>q close the focused pane. Each area is put away by its
     own T3 command, and the chat and its composer cannot be closed at all,
     so the key says so rather than closing something else. */
  const PANE_CLOSE = {
    sidebar: "[",         /* sidebar.toggle */
    terminal: "]",        /* terminal.close */
    panel: "x",           /* rightPanel.close */
    details: "v",         /* threadPanel.toggle */
  };

  function paneClose() {
    const here = paneHere(panes());
    const chord = here && PANE_CLOSE[here.name];
    if (!chord) { seqFlash("the chat cannot be closed"); return true; }
    dispatchChord(chord);
    return true;
  }

  /* <C-w>o: every pane but the focused one away. */
  function paneOnly() {
    const list = panes();
    const here = paneHere(list);
    const keep = here ? here.name : "conversation";
    let shut = 0;
    for (const p of list) {
      if (p.name === keep || !PANE_CLOSE[p.name]) continue;
      dispatchChord(PANE_CLOSE[p.name]);
      shut++;
    }
    if (!shut) seqFlash("nothing else is open");
    return true;
  }

  /* The keys the app tree calls by name. A row of SEQ_ROWS whose second
     field starts with @ runs one of these instead of dispatching a chord. */
  const SEQ_ACTS = {
    "pane.left": () => paneGo("h"),
    "pane.down": () => paneGo("j"),
    "pane.up": () => paneGo("k"),
    "pane.right": () => paneGo("l"),
    "pane.next": () => paneRing(1),
    "pane.prev": () => paneRing(-1),
    "pane.close": () => paneClose(),
    "pane.only": () => paneOnly(),
  };

  /* ----------------------------------------------------------- lists ----- */

  /* T3's thread lists (the sidebar, and the thread panel, which is the same
     row component) are a roving-tabindex list: each row is a
     `div role="button" tabindex="0" data-sidebar-row="..."`, and T3 listens
     on the list's container, in the capture phase, for ArrowUp, ArrowDown,
     ArrowLeft, ArrowRight, Home and End - and for ContextMenu and Shift+F10,
     which open the row's own menu. A group row carries aria-expanded, and
     ArrowRight on a closed one clicks it rather than moving.

     Every row is a button, so NATIVE_KEYS below stands the trees aside on it,
     which is right for Space: it activates the focused row. j and k are not
     Space. Where T3 already handles a key the act is translated into it
     rather than reimplemented, so collapsing a group, loading more and the
     scroll into view stay T3's own behaviour, and a release that changes the
     list changes these keys with it.

     The table below is `fleet/src/list/keys.rs`, Graphide's agents' list, in
     its own order. Every key of it is answered: the ones T3 can do, and the
     ones it cannot, which say so on the message line rather than going dead.
     That silence was most of what felt unfinished - six keys worked and
     thirty did nothing.

     The settings page's navigation is the same pattern on
     `[data-settings-section]`, with no Left or Right and no rows to act on,
     so only the movements do anything there. Those two are the only lists T3
     drives this way; its pickers and menus are listboxes behind a text
     field, where a letter has to stay a letter. */
  const LIST_SEL = "[data-sidebar-row], [data-settings-section]";
  const LIST = { sent: 0 };

  /* The key T3's own list handler is waiting for. Dispatched at the row, so
     the container's capture listener sees it with the row as its target; it
     carries no modifier, which is what that handler requires. */
  function listMove(row, key) {
    LIST.sent++;
    row.dispatchEvent(new KeyboardEvent("keydown", {
      key, code: key, bubbles: true, cancelable: true,
    }));
  }

  const listRows = (row) => {
    const box = row.closest("[data-slot='sidebar'], [data-workspace-area]") || document;
    return Array.from(box.querySelectorAll(LIST_SEL));
  };

  /* Half a list, and a list: how many rows fit, as gred's HalfDown and
     PageDown move. T3 handles no PageDown on a row, so it is that many
     arrows. */
  function listRun(row, key, n) {
    for (let i = 0; i < n; i++) {
      const at = document.activeElement;
      listMove(at && at.matches && at.matches(LIST_SEL) ? at : row, key);
    }
    return true;
  }
  function listFit(row, part) {
    const h = row.getBoundingClientRect().height || 28;
    const box = row.closest("[data-slot='sidebar-inner'], [data-slot='sidebar'], [data-workspace-area]");
    const tall = (box ? box.getBoundingClientRect().height : window.innerHeight) || 600;
    return Math.max(1, Math.round(tall / h / part));
  }

  /* A group row: aria-expanded says which way it is. gred's za zo zc zR zM. */
  const listOpen = (row) => row.getAttribute("aria-expanded");
  function listGroup(row, want) {
    const at = listOpen(row);
    if (at === null) { seqFlash("not a group"); return true; }
    if (want === "toggle" || (want === "open") === (at === "false")) row.click();
    return true;
  }
  function listGroupAll(row, open) {
    let n = 0;
    for (const r of listRows(row)) {
      if (listOpen(r) === (open ? "false" : "true")) { r.click(); n++; }
    }
    if (!n) seqFlash(open ? "every group is open" : "every group is closed");
    return true;
  }

  /* The row's own menu, which T3 opens for ContextMenu and Shift+F10: where
     archive, delete and snooze live, since T3 binds no key to any of them. */
  function listMenu(row) {
    const r = row.getBoundingClientRect();
    row.dispatchEvent(new PointerEvent("contextmenu", {
      bubbles: true, cancelable: true, button: -1, clientX: r.left, clientY: r.bottom,
    }));
    return true;
  }

  /* gred's i a r on a row write to that agent: the row is opened and the
     composer takes the keys. Opening is a navigation, so the composer may
     not be there for a frame or two. */
  function listCompose(row) {
    row.click();
    let tries = 0;
    const tryIt = () => {
      if (intoComposer("") || ++tries > 8) return;
      requestAnimationFrame(tryIt);
    };
    tryIt();
    return true;
  }

  /* `fleet/src/list/keys.rs`, in its order: the keys, what they do, and the
     word the which-key bar and the message line use. A chord string is a T3
     command through keybindings.json; @name is one of LIST_ACTS; null is a
     key Graphide has and T3 has nothing for, which answers rather than doing
     nothing at all. */
  const LIST_ROWS = [
    ["j", "@down", "the line below"],
    ["k", "@up", "the line above"],
    ["G", "@last", "the last line"],
    ["l", "@right", "into the line"],
    ["h", "@fold", "the group of the line folded"],
    ["i", "@compose", "write to the agent"],
    ["a", "@compose", "always allow what it asks, else write to it"],
    ["o", "n", "a new agent"],
    ["n", null, "no to what it asks, else the next agent that asks"],
    ["y", null, "yes to what it asks"],
    ["A", null, "always allow that, everywhere"],
    ["e", null, "edit what it asks to do"],
    ["r", "@compose", "answer it in words"],
    ["V", null, "start or end a selection of lines"],
    ["K", "v", "show or hide the details"],
    ["/", null, "filter the list"],
    ["f", null, "a label on each link of the preview"],
    ["N", null, "the agent before that asks"],
    [".", null, "do the last change again"],
    ["!", null, "mark important, or not"],
    ["L", null, "to the bottom of the queue"],
    ["x", null, "switch off the computer whose strip it is"],
    ["<C-d>", "@halfdown", "half the list down"],
    ["<C-u>", "@halfup", "half the list up"],
    ["<C-c>", "k", "stop the agent's turn"],
    ["<C-x>", null, "its page in a pane below"],
    ["<C-v>", null, "its page in a pane beside"],
    ["<C-t>", null, "its page in a new tab"],
    ["gg", "@first", "first line"],
    ["gd", null, "the file its page is at"],
    ["gp", "i", "pin to the top of the list, or unpin"],
    ["gb", null, "bring the agent on another computer back"],
    ["za", "@group", "toggle the group"],
    ["zo", "@open", "open"],
    ["zc", "@close", "close"],
    ["zR", "@openall", "open all"],
    ["zM", "@closeall", "close all"],
    ["zz", "@menu", "archive it for a while, then be reminded of it"],
    ["dd", "p", "stop and settle"],
    ["dm", "@menu", "the row's menu: archive, delete, snooze"],
    ["]c", "d", "its change"],
    ["[c", "d", "its change"],
  ];

  const LIST_ACTS = {
    down: (row) => listMove(row, "ArrowDown") || true,
    up: (row) => listMove(row, "ArrowUp") || true,
    first: (row) => listMove(row, "Home") || true,
    last: (row) => listMove(row, "End") || true,
    right: (row) => listMove(row, "ArrowRight") || true,
    fold: (row) => listMove(row, "ArrowLeft") || true,
    halfdown: (row) => listRun(row, "ArrowDown", listFit(row, 2)),
    halfup: (row) => listRun(row, "ArrowUp", listFit(row, 2)),
    group: (row) => listGroup(row, "toggle"),
    open: (row) => listGroup(row, "open"),
    close: (row) => listGroup(row, "close"),
    openall: (row) => listGroupAll(row, true),
    closeall: (row) => listGroupAll(row, false),
    menu: (row) => listMenu(row),
    compose: (row) => listCompose(row),
  };

  /* The table, split the way the keys arrive: one key, a chord, or a key
     after a prefix. A prefix the app's own tree owns (g, ] and [) reaches
     the list through seqStep's fall-through; one it does not (d and z) is
     started here. */
  const LIST_ONE = new Map();          /* "j" -> row */
  const LIST_CHORD = new Map();        /* "<C-d>" -> row */
  const LIST_TREE = new Map();         /* "d" -> Map("d" -> row) */
  for (const row of LIST_ROWS) {
    const keys = row[0];
    if (keys.length > 1 && keys[0] === "<") { LIST_CHORD.set(keys, row); continue; }
    if (keys.length === 1) { LIST_ONE.set(keys, row); continue; }
    if (!LIST_TREE.has(keys[0])) LIST_TREE.set(keys[0], new Map());
    LIST_TREE.get(keys[0]).set(keys[1], row);
  }
  /* The prefixes the list owns outright, which nothing in the app's tree
     starts: everything but g, ] and [. */
  const LIST_STARTS = new Set([...LIST_TREE.keys()].filter((k) => !SEQ_STARTS.has(k) && k !== "g" && k !== "]" && k !== "["));

  /* The list's own prefixes as trie nodes, so the pending key, the wait and
     the which-key bar are the app tree's and this adds no second machinery.
     The group names are gred's: `dd` lives under Vim's delete, `z` under its
     folds. */
  const LIST_GROUPS = { d: "Delete", z: "Fold" };
  const LIST_NODES = new Map();
  for (const [pre, kids] of LIST_TREE) {
    const node = { kids: new Map(), leaf: null, name: pre, group: LIST_GROUPS[pre] || "" };
    for (const [k, def] of kids) {
      node.kids.set(k, { kids: new Map(), leaf: { row: def, desc: def[2] }, name: pre + k, group: "" });
    }
    LIST_NODES.set(pre, node);
  }

  /* The list row the keys are for: the focused one, or the one the event came
     from. */
  function listFocused(target) {
    const f = document.activeElement;
    const a = f && f.closest ? f.closest(LIST_SEL) : null;
    if (a) return a;
    return target && target.closest ? target.closest(LIST_SEL) : null;
  }

  function listStart(k) {
    SEQ.node = LIST_NODES.get(k) || null;
    SEQ.local = false;
    SEQ.flash = "";
    if (SEQ.node) seqArm();
    refresh();
  }

  function listRun1(row, def) {
    if (!row) return false;
    const [keys, act, desc] = def;
    if (act === null) { seqFlash(keys + " (" + desc + "): no T3 equivalent"); refresh(); return true; }
    if (act[0] === "@") return LIST_ACTS[act.slice(1)](row);
    dispatchChord(act);
    return true;
  }

  /* A key after a list prefix, from seqStep's fall-through or from the list's
     own pending prefix. */
  function listSeq(prefix, k, row) {
    const kids = LIST_TREE.get(prefix);
    const def = kids && kids.get(k);
    if (!def) return false;
    return listRun1(row, def);
  }

  /* One key with a list row focused. True when the key was taken. */
  function listKey(e, row) {
    const k = e.key;
    if (e.ctrlKey && !e.altKey && !e.metaKey) {
      const def = LIST_CHORD.get("<C-" + k + ">");
      /* <C-c> with something selected is a copy, which the platform owes the
         user before Graphide owes them an interrupt. */
      if (!def) return false;
      if (k === "c" && String(window.getSelection() || "")) return false;
      return listRun1(row, def);
    }
    if (e.metaKey || e.altKey) return false;              /* T3's own chords */
    if (e.repeat && LIST_STARTS.has(k)) return true;      /* a held d is not dd */
    if (LIST_STARTS.has(k)) { listStart(k); return true; }
    const def = LIST_ONE.get(k);
    if (!def) return false;        /* Space, Enter, Tab, everything else: T3's */
    return listRun1(row, def);
  }

  /* ------------------------------------------------------------------- ui -- */

  /* ------------------------------------------------------------- page --- */

  /* gred's agent page: the conversation is a read-only Vim buffer and the
     composer is a field inside it (fleet/src/page/keys.rs). An Escape in the
     composer's normal mode, with nothing typed of a command, gives the keys
     back to the page (`Composer::rests`, "where an escape would leave it",
     and page.rs's `Typed::Leave`). The page then reads:

       j k            a line down, up          (agent.down, agent.up)
       gg G           the first line, the last (agent.first, agent.last)
       <C-d> <C-u>    half a screen            (agent.half_down, half_up)
       <C-f> <C-b>    a screen                 (agent.page_down, page_up)
       <C-e> <C-y>    the view a line          (agent.line_down, line_up)
       ]] [[          message, as gred's do    (agent.next_message, previous)
       ][ []          turn                     (agent.next_turn, previous)
       ]t [t          tool call                (agent.next_tool, previous)
       i a I A o      write to the agent       (agent.insert .. open_line)
       /              search the conversation  (agent.search)

     gred has a cursor line to move; T3's conversation has none, so j and k
     move the view by a line, which is what <C-e> and <C-y> do. The rest of
     the conversation's keys (folds, yank, K, the labels f puts on links) are
     surfaces T3 does not have. <C-c> is left to the platform: gred's Vim keys
     interrupt the turn with it, but here it would take copying a selection
     out of the chat, and <leader>ak stops the agent. */
  const SCROLL_SEL = ".messages-timeline-scroll";
  const CONVERSATION_SEL = '[data-workspace-area="conversation"]';
  /* What j and k move. gred's agent page walks a cursor line and lets the
     view follow, which T3's conversation has nothing to carry; read as a
     page instead, it takes the step gred's own page keys take, STEP = 60
     (page/src/keys.rs), so j in the chat and j in the preview move the same
     distance. <C-e> and <C-y> stay a line, measured from the conversation's
     own text, with this as the fallback where it cannot be. */
  const STEP = 60;
  const PAGE_LINE = 20;
  /* gred glides its view rather than jumping it: ui::motion's GLIDE, a spring
     of response 90 ms and damping 1. Written here as the exponential that
     settles in that time, so a held j reads as one movement rather than a
     stutter of jumps, and the view lands softly. */
  const GLIDE_MS = 90;

  const scrolls = (n) => !!n && n.scrollHeight > n.clientHeight + 4;

  let scrollCache = null;
  function scroller() {
    if (scrolls(scrollCache) && scrollCache.isConnected) return scrollCache;
    scrollCache = null;
    const start = document.querySelector(SCROLL_SEL);
    if (scrolls(start)) { scrollCache = start; return start; }
    /* The class T3 documents names the timeline, which is not always the box
       that scrolls: the overflow can sit on a parent, and a release can move
       it. Walk out to the first ancestor that does scroll, then look inside
       the conversation. */
    for (let n = start && start.parentElement; n && n !== document.body; n = n.parentElement) {
      if (scrolls(n) && /auto|scroll/.test(getComputedStyle(n).overflowY)) { scrollCache = n; return n; }
    }
    const area = document.querySelector(CONVERSATION_SEL);
    if (!area) return null;
    for (const n of area.querySelectorAll("div")) {
      if (scrolls(n) && /auto|scroll/.test(getComputedStyle(n).overflowY)) { scrollCache = n; return n; }
    }
    return null;
  }

  /* A line of the conversation, measured: j and k move by what a line of it
     actually is, so the text lands where it stood a line ago. */
  function lineStep(sc) {
    const row = sc.querySelector(".chat-markdown, [data-timeline-row-kind]") || sc;
    const cs = getComputedStyle(row);
    const line = parseFloat(cs.lineHeight);
    if (line > 6 && line < 96) return Math.round(line);
    const size = parseFloat(cs.fontSize);
    return size > 6 ? Math.round(size * 1.45) : PAGE_LINE;
  }

  const SCROLL = { el: null, to: 0, at: 0, raf: 0, last: 0 };

  /* Writes scrollTop itself rather than asking for a scroll: the app's own
     smooth scrolling would start again on every key, which is what a held
     key fought with. */
  function glide(sc, top) {
    const most = Math.max(0, sc.scrollHeight - sc.clientHeight);
    const going = SCROLL.raf && SCROLL.el === sc;
    SCROLL.el = sc;
    SCROLL.to = clamp(top, 0, most);
    if (going) return true;
    SCROLL.at = sc.scrollTop;
    SCROLL.last = performance.now();
    /* A scroller with `scroll-behavior: smooth` animates even a scrollTop
       written straight to it, so the view would never be where this put it
       and the glide would give itself up every frame. It drives the scroll
       itself for as long as it runs, and hands the behaviour back after. */
    SCROLL.was = sc.style.scrollBehavior;
    sc.style.scrollBehavior = "auto";
    const done = () => {
      SCROLL.raf = 0;
      if (SCROLL.el) SCROLL.el.style.scrollBehavior = SCROLL.was || "";
    };
    const tick = (now) => {
      const el = SCROLL.el;
      if (!el || !el.isConnected) { done(); return; }
      /* The wheel, or T3 keeping the view at the end of a turn: whoever else
         moved it wins, and the glide gives up rather than fighting it. */
      if (Math.abs(el.scrollTop - SCROLL.at) > 3) { done(); return; }
      const dt = Math.min(64, Math.max(1, now - SCROLL.last));
      SCROLL.last = now;
      SCROLL.at += (SCROLL.to - SCROLL.at) * (1 - Math.exp(-dt / (GLIDE_MS / 3)));
      if (Math.abs(SCROLL.to - SCROLL.at) < 0.5) {
        el.scrollTop = SCROLL.to;
        done();
        return;
      }
      el.scrollTop = SCROLL.at;
      SCROLL.raf = requestAnimationFrame(tick);
    };
    SCROLL.raf = requestAnimationFrame(tick);
    return true;
  }

  /* Where the view is going: the glide's target while one runs, so a held
     key adds to it instead of starting again from where the view has got to. */
  const going = (sc) => (SCROLL.raf && SCROLL.el === sc ? SCROLL.to : sc.scrollTop);

  const pageBy = (by) => { const sc = scroller(); return !!sc && glide(sc, going(sc) + by); };
  const pageLines = (n) => { const sc = scroller(); return !!sc && glide(sc, going(sc) + n * lineStep(sc)); };
  const pageEnd = (last) => {
    const sc = scroller();
    return !!sc && glide(sc, last ? sc.scrollHeight : 0);
  };

  /* The next row of its kind past the top of the view, or the one before it. */
  function pageJump(sel, back) {
    const sc = scroller();
    if (!sc) return false;
    const rows = Array.from(sc.querySelectorAll(sel));
    if (!rows.length) return false;
    const top = sc.getBoundingClientRect().top;
    let to = null;
    if (back) {
      for (let i = rows.length - 1; i >= 0; i--) {
        if (rows[i].getBoundingClientRect().top - top < -2) { to = rows[i]; break; }
      }
    } else {
      for (const row of rows) {
        if (row.getBoundingClientRect().top - top > 2) { to = row; break; }
      }
    }
    if (!to) return pageEnd(!back);
    return glide(sc, sc.scrollTop + to.getBoundingClientRect().top - top - 8);
  }

  /* Back into the composer, as gred's i a I A o write to the agent. */
  function intoComposer(where) {
    const el = document.querySelector(EDITABLE_SEL);
    if (!el) return false;
    el.focus();
    S.el = el;
    S.mode = NORMAL;
    reset();
    seqCancel();
    const m = scan(el);
    if (where === "start") caretTo(m, 0);
    else if (where !== "") caretTo(m, m.text.length);
    if (where === "line") { handleKey("o"); return true; }   /* o opens a line and writes */
    S.mode = INSERT;
    refresh();
    return true;
  }

  /* Out of the composer, into the conversation. */
  function leaveComposer() {
    const el = S.el;
    S.el = null;
    S.mode = INSERT;      /* what the composer is in again when it is focused */
    reset();
    seqCancel();
    if (el) { el.classList.remove("t3vim-normal"); if (el.blur) el.blur(); }
    hideUI();
    refresh();
  }

  /* Bare <C-h> <C-j> <C-k> <C-l>: the pane that way. */
  function paneKey(e) {
    if (!e.ctrlKey || e.altKey || e.metaKey || e.shiftKey) return false;
    if (!PANE_WORD[e.key]) return false;
    return paneGo(e.key);
  }

  /* One key with the conversation reading. True when the key was taken. */
  function pageKey(e) {
    const k = e.key;
    if (e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey) {
      const sc = scroller();
      if (!sc) return false;
      const line = lineStep(sc);
      const half = Math.max(line, Math.round(sc.clientHeight / 2));
      /* Vim keeps two lines of what you were reading when it turns a page. */
      const screen = Math.max(line, sc.clientHeight - 2 * line);
      if (k === "d") return pageBy(half);
      if (k === "u") return pageBy(-half);
      if (k === "f") return pageBy(screen);
      if (k === "b") return pageBy(-screen);
      if (k === "e") return pageLines(1);
      if (k === "y") return pageLines(-1);
      return false;
    }
    if (e.ctrlKey || e.metaKey || e.altKey) return false;
    if (k === "j") return pageBy(STEP);
    if (k === "k") return pageBy(-STEP);
    if (k === "G") return pageEnd(true);
    if (k === "i" || k === "a") return intoComposer("");
    if (k === "I") return intoComposer("start");
    if (k === "A") return intoComposer("end");
    if (k === "o") return intoComposer("line");
    if (k === "/") { dispatchChord("/"); return true; }
    return false;
  }

  /* What the conversation makes of a key after one of the app's prefixes,
     where the app's own tree has nothing for it: gg, and the ] and [ walks.
     gred resolves these the same way round, the keymap first and the
     surface's own keys after it. */
  function pageSeq(prefix, k) {
    if (prefix === "g") return k === "g" ? pageEnd(false) : false;
    if (prefix !== "]" && prefix !== "[") return false;
    const back = prefix === "[";
    if (k === "]") return pageJump('[data-message-role="user"]', back);
    if (k === "[") return pageJump('[data-message-role="assistant"]', back);
    if (k === "t") return pageJump('[data-timeline-row-kind="work"]', back);
    return false;
  }

  /* ------------------------------------------------------------ chrome -- */

  /* gred's own measures, from gred-rs: chrome::LINE (the statusline and the
     message line), which_key's COLUMN, ROW and RISE, control.rs's key chip
     and tag, and typography.rs's steps. The colours are the theme's roles,
     which T3 publishes as --app-theme-*; the fallbacks are Theme::ink's. */
  const LINE = 24;          // chrome::LINE: the statusline, and the message line
  const KEY_COLUMN = 220;   // chrome::which_key COLUMN
  const KEY_ROW = 22;       // its ROW
  const KEY_RISE = 10;      // its RISE: how far below its place the bar starts
  const REVEAL_MS = 160;    // ui::motion REVEAL, the fade and rise it comes up on

  /* The mode pill is ui::control's tag in Tone::Mode: gred gives the modes
     their own grounds and inks (Theme::ink's `modes`), which are not T3 roles,
     so they are written out. Ink first, Marble under :root:not(.dark). */
  const MODE_INK = {
    NORMAL: ["#4fa396", "#0a1218"],
    INSERT: ["#152336", "#bcc6cd"],
    VISUAL: ["#14251e", "#bcc6cd"],
    "V-LINE": ["#14251e", "#bcc6cd"],
  };
  const MODE_MARBLE = {
    NORMAL: ["#2a7a6e", "#ffffff"],
    INSERT: ["#c8d8ef", "#24313a"],
    VISUAL: ["#c2e2cf", "#24313a"],
    "V-LINE": ["#c2e2cf", "#24313a"],
  };
  const modeRules = (table, prefix) =>
    Object.keys(table).map((m) =>
      prefix + '.t3vim-mode[data-mode="' + m + '"]{background:' + table[m][0] + ";color:" + table[m][1] + "}");

  let statusEl = null, modeEl = null, keysOfEl = null, titleEl = null;
  let blockEl = null, keysEl = null, keysShown = "", msgEl = null, styled = false;

  function ui() {
    if (styled) return;
    styled = true;
    const css = document.createElement("style");
    css.textContent = [
      /* Shared ground: gred paints its chrome flat, with one hairline along
         the top edge and no radius, no shadow. */
      ".t3vim-status,.t3vim-keys,.t3vim-msg{position:fixed;left:0;right:0;z-index:2147483000;",
      "box-sizing:border-box;pointer-events:none;",
      'font-family:"Inter Variable","Inter",ui-sans-serif,system-ui,sans-serif;}',
      ".t3vim-status,.t3vim-keys{background:var(--app-theme-chrome,#070d12);",
      "border-top:1px solid var(--app-theme-border,#ffffff14)}",

      /* The statusline: chrome::LINE tall, the mode pill at its left end, the
         keys held beside it, then what gred puts there, the buffer's name. */
      ".t3vim-status{display:none;bottom:0;height:" + LINE + "px;align-items:center;",
      "gap:8px;padding:0 8px;white-space:nowrap;overflow:hidden}",
      ".t3vim-status.on{display:flex}",
      /* ui::control tag: height 18, radius 4, pad 7, caption 11/1.3, weight 600. */
      ".t3vim-mode{flex:none;height:18px;border-radius:4px;padding:0 7px;",
      "display:inline-flex;align-items:center;font-size:11px;line-height:1.3;",
      "font-weight:600;letter-spacing:.01em}",
      /* The keys held, as gred writes them with chrome = minimal: Vim notation. */
      ".t3vim-status-keys{flex:none;font-family:var(--font-mono,ui-monospace),monospace;",
      "font-size:11px;line-height:1.35;color:var(--app-theme-accent,#4fa396)}",
      ".t3vim-status-title{min-width:0;overflow:hidden;text-overflow:ellipsis;",
      "font-size:12px;line-height:1.4;color:var(--app-theme-text-muted,#75838b)}",
      modeRules(MODE_INK, "").join(""),
      modeRules(MODE_MARBLE, ":root:not(.dark) ").join(""),

      /* The which-key bar, docked above the statusline: columns of 220, rows
         of 22, 12 either end and 8 over and under, filled down each column
         before the next, as chrome::which_key lays it out. */
      ".t3vim-keys{display:none;padding:8px 12px;overflow:hidden}",
      ".t3vim-keys.on{display:block}",
      ".t3vim-keys-grid{display:grid;grid-auto-flow:column;",
      "grid-auto-columns:" + KEY_COLUMN + "px;align-content:start}",
      ".t3vim-keys-row{display:flex;align-items:center;gap:8px;height:" + KEY_ROW + "px;",
      "padding-right:16px;min-width:0}",
      /* ui::control key chip: height 18, radius 4, pad 5, mono-small 11/1.35,
         the sunken ground and the hairline edge. */
      ".t3vim-keys-row b{flex:none;height:18px;box-sizing:border-box;padding:0 5px;",
      "display:inline-flex;align-items:center;border-radius:4px;font-weight:400;",
      "font-family:var(--font-mono,ui-monospace),monospace;font-size:11px;line-height:1.35;",
      "background:var(--app-theme-muted,#0d161c);color:var(--app-theme-text,#bcc6cd);",
      "border:1px solid var(--app-theme-border,#ffffff14)}",
      /* Type::Small for the label; a group, which leads to more keys, in the
         accent, as gred paints one. */
      ".t3vim-keys-row i{min-width:0;overflow:hidden;text-overflow:ellipsis;font-style:normal;",
      "font-size:12px;line-height:1.4;color:var(--app-theme-text,#bcc6cd)}",
      ".t3vim-keys-row.group i{color:var(--app-theme-accent,#4fa396)}",
      ".t3vim-keys-row.none{opacity:.45}",
      /* It comes up from below as it fades in: ui::motion REVEAL. */
      ".t3vim-rise{transform:translateY(" + KEY_RISE + "px);opacity:0;",
      "transition:transform " + REVEAL_MS + "ms ease-out," + "opacity " + REVEAL_MS + "ms ease-out}",
      ".t3vim-rise.up{transform:none;opacity:1}",
      "@media (prefers-reduced-motion:reduce){.t3vim-rise{transition:none}}",

      /* The message line: gred puts the last message under the statusline, on
         the page itself, in the colour of its level. */
      ".t3vim-msg{display:none;bottom:0;height:" + LINE + "px;align-items:center;",
      "padding:0 10px;font-size:12px;line-height:1.4;white-space:nowrap;overflow:hidden;",
      "text-overflow:ellipsis;background:var(--app-theme-canvas,#0a1218);",
      "color:var(--app-theme-text,#bcc6cd)}",
      ".t3vim-msg.on{display:flex}",

      /* The statusline stands where T3 put its own bottom gutter, so the
         composer is lifted clear of it for as long as the bar is up. The
         selector is one of T3's documented stable ones. */
      "html.t3vim-lined [data-chat-composer-form]{margin-bottom:" + LINE + "px}",
      "html.t3vim-lined.t3vim-said [data-chat-composer-form]{margin-bottom:" + 2 * LINE + "px}",

      /* The caret gred draws over the character in normal mode: the
         composer's `caret color` (the accent) filled, with the character it
         covers set in its `caret ink` (Role::OnAccent) over it. */
      ".t3vim-block{position:fixed;z-index:2147482999;pointer-events:none;border-radius:1px;",
      "overflow:hidden;white-space:pre;text-align:center;",
      "background:var(--app-theme-accent,#4fa396);",
      "color:var(--app-theme-accent-foreground,#04120f)}",
      ".t3vim-normal{caret-color:transparent !important}",
    ].join("");
    document.head.appendChild(css);

    statusEl = document.createElement("div");
    statusEl.className = "t3vim-status";
    modeEl = document.createElement("span");
    modeEl.className = "t3vim-mode";
    keysOfEl = document.createElement("span");
    keysOfEl.className = "t3vim-status-keys";
    titleEl = document.createElement("span");
    titleEl.className = "t3vim-status-title";
    statusEl.append(modeEl, keysOfEl, titleEl);

    blockEl = document.createElement("div");
    blockEl.className = "t3vim-block";
    keysEl = document.createElement("div");
    keysEl.className = "t3vim-keys";
    msgEl = document.createElement("div");
    msgEl.className = "t3vim-msg";
    document.body.append(statusEl, blockEl, keysEl, msgEl);
  }

  function hideUI() {
    if (blockEl) blockEl.style.display = "none";
    document.querySelectorAll(".t3vim-normal").forEach((n) => n.classList.remove("t3vim-normal"));
  }

  let pending = false;
  function refresh() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      try { paintStatus(); } catch { /* never let the UI break editing */ }
      try { paintMsg(); } catch { /* never let the UI break editing */ }
      try { paintKeys(); } catch { /* never let the UI break editing */ }
      try { paint(); } catch { /* never let the UI break editing */ }
    });
  }

  /* gred's words for a mode, from gred/src/segments.rs. */
  const MODE_WORD = { NORMAL: "Normal", INSERT: "Insert", VISUAL: "Visual", "V-LINE": "V-Line" };

  /* What the statusline says it is. A composer in normal or visual mode says
     so; with nothing editable focused the app's trees are live, which is
     Normal; inside anything that takes text it is Insert, as typing into a
     field is in gred. */
  function statusMode() {
    if (S.el && S.el.isConnected) return S.mode;
    const f = document.activeElement;
    return f && f.closest && f.closest(TEXT_KEYS) ? INSERT : NORMAL;
  }

  /* The title gred's statusline carries beside the pill is the buffer's. T3
     keeps the open thread's name in the window title. */
  function statusTitle() {
    const t = (document.title || "").replace(/\s*[-|]\s*T3 Code\s*$/i, "").trim();
    return t === "T3 Code" ? "" : t;
  }

  /* The statusline: gred's, as far as this can know it. It stands wherever
     the app has a composer, which is wherever these keys do anything. */
  function paintStatus() {
    const live = S.on && (SEQ.node || (S.el && S.el.isConnected) || document.querySelector(FORM_SEL));
    document.documentElement.classList.toggle("t3vim-lined", !!live);
    if (!live) { if (statusEl) statusEl.classList.remove("on"); return; }
    ui();
    const mode = statusMode();
    modeEl.dataset.mode = mode;
    modeEl.textContent = MODE_WORD[mode] || mode;
    keysOfEl.textContent = (SEQ.node ? SEQ.node.name : "")
      + (S.operator ? " " + S.operator : "")
      + (S.useClip ? ' "+' : "")
      + ((S.opCount + S.count) ? " " + (S.opCount + S.count) : "");
    titleEl.textContent = statusTitle();
    statusEl.classList.add("on");
  }

  /* The message line, under the statusline: the last thing said, on the page
     itself, in the colour of its level (gred's chrome::message_line). */
  function paintMsg() {
    const say = S.on && SEQ.flash ? SEQ.flash : "";
    document.documentElement.classList.toggle("t3vim-said", !!say);
    if (say) ui();
    /* The statusline stands on the message line while one is up, as gred
       keeps the message under it. */
    if (statusEl) statusEl.style.bottom = say ? LINE + "px" : "0px";
    if (!say) { if (msgEl) { msgEl.classList.remove("on"); msgEl.textContent = ""; } return; }
    msgEl.textContent = say;
    msgEl.classList.add("on");
  }

  /* How far the bars above the bottom edge start: the message line, then the
     statusline, as gred stacks them. */
  const chromeBelow = () =>
    (msgEl && msgEl.classList.contains("on") ? LINE : 0)
    + (statusEl && statusEl.classList.contains("on") ? LINE : 0);

  /* The which-key bar. gred docks it above the statusline, full width, and
     lays its hints in columns of 220 filled top to bottom, so the keys read
     down a column rather than across the window. */
  function paintKeys() {
    const h = S.on ? seqHint() : null;
    if (!h || !h.items.length) {
      if (keysEl) { keysEl.classList.remove("on", "up"); }
      keysShown = "";
      return;
    }
    ui();
    if (h.title !== keysShown) {
      keysShown = h.title;
      keysEl.textContent = "";
      const grid = document.createElement("div");
      grid.className = "t3vim-keys-grid";
      for (const it of h.items) {
        const row = document.createElement("div");
        row.className = "t3vim-keys-row" + (it.none ? " none" : "") + (it.group ? " group" : "");
        const b = document.createElement("b");
        b.textContent = it.key;
        const i = document.createElement("i");
        i.textContent = it.desc;
        row.append(b, i);
        grid.appendChild(row);
      }
      keysEl.appendChild(grid);
    }
    const grid = keysEl.firstChild;
    const columns = Math.max(1, Math.floor((window.innerWidth - 24) / KEY_COLUMN));
    const rows = Math.ceil(h.items.length / columns);
    grid.style.gridTemplateRows = "repeat(" + rows + "," + KEY_ROW + "px)";
    keysEl.style.bottom = chromeBelow() + "px";
    if (!keysEl.classList.contains("on")) {
      keysEl.classList.add("on", "t3vim-rise");
      /* One frame down, then up: the transition needs a start to run from. */
      requestAnimationFrame(() => keysEl.classList.add("up"));
    }
  }

  /* The caret. What mode it is and what is pending are the statusline's, as
     in gred; here only the block over the character is drawn. */
  function paint() {
    if (!S.on || !S.el || !S.el.isConnected) { hideUI(); return; }
    ui();

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
    /* The block caret carries the character it covers, in the colour the
       composer's `caret ink` slot gives it (Role::OnAccent), so the block is
       solid as gred's is rather than a wash over the text. */
    const under = t[p] !== undefined && t[p] !== "\n" && t[p] !== " " ? t[p] : "";
    if (blockEl.textContent !== under) blockEl.textContent = under;
    if (under) {
      const cs = getComputedStyle(S.el);
      blockEl.style.font = cs.fontStyle + " " + cs.fontWeight + " " + cs.fontSize + "/"
        + rect.height + "px " + cs.fontFamily;
      blockEl.style.letterSpacing = cs.letterSpacing;
    }
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
    /* Anything taking text keeps every key; a focused list row reads
       Graphide's list table. */
    const takesText = (t && t.closest && t.closest(TEXT_KEYS)) || (f && f.closest && f.closest(TEXT_KEYS));
    const row = takesText ? null : listFocused(t);
    /* A pending sequence sees the key before the focused control does, so
       long as nothing is taking text. The list's own keys are sequences -
       dd, za, gg - and every row is a button, which the NATIVE_KEYS bail
       below would otherwise cancel them for. */
    if (SEQ.node && row) {
      const r = seqPendingKey(e);
      if (r === "eat") { eat(e); return; }
      if (r === "skip") return;
    }
    if (!SEQ.node && row && listKey(e, row)) { eat(e); return; }
    /* A prefix the app's tree owns, pressed on a row: it starts there, and
       the list gets its second key through seqStep's fall-through, which is
       how gg, gp and ]c reach the list. Not the leader: Space activates a
       focused row, here as everywhere on the web, and taking it would break
       the row for the sake of a leader nobody presses with one focused. */
    if (!SEQ.node && row && !e.ctrlKey && !e.metaKey && !e.altKey &&
        e.key !== " " && SEQ_STARTS.has(e.key)) {
      eat(e); seqStart(e.key, false); return;
    }
    /* The panes, from anywhere but a text box and the terminal: gred binds
       bare <C-h> <C-j> <C-k> <C-l> to the four directions in Normal and
       Visual mode (presets/gred.toml), beside the <C-w> tree. Inside the
       terminal they stay the shell's, and <C-w> then a direction is the way
       out, as it is in tmux. */
    if (!SEQ.node && !takesText && paneKey(e)) { eat(e); return; }
    /* The conversation reads its keys wherever the composer does not have
       them, which is gred's rule: a control keeps Space and Enter, and the
       keys it has no use for are the page's. */
    if (!SEQ.node && !takesText && pageKey(e)) { eat(e); return; }
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
      /* Normal mode with nothing typed of a command: an escape leaves, and
         the conversation takes the keys. gred's `Composer::rests` is the
         same test, and its page answers with `Typed::Leave`. */
      leaveComposer(); eat(e); return;
    }

    if (S.mode === INSERT) {
      /* The three erasers are vim's while typing, and T3's keybindings had
         all three: <C-w> closed the right panel, <C-u> opened the usage page
         and <C-h> stepped the pane ring. */
      if (ctrlOnly && !e.shiftKey && (k === "w" || k === "h" || k === "u")) {
        eat(e);
        eraseBack(k === "w" ? "word" : k === "h" ? "char" : "line");
        S.rec = null;                       /* what was typed is no longer what . repeats */
        refresh();
        return;
      }
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
    /* The four directions from the composer too, as gred has them in Normal
       and Visual mode: the composer is a pane like any other. */
    if (ctrlOnly && !e.shiftKey && PANE_WORD[k] && free) { eat(e); paneGo(k); return; }
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
    /* dd with nothing to delete settles the thread, which is what Graphide's
       composer does with it: "gred's own composer sends dd as the agents'
       list does, and archives" (fleet/src/composer.rs). */
    if (k === "d" && S.operator === "d" && scan(S.el).text === "") {
      reset(); refresh(); dispatchChord("p"); return;
    }
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
  /* The statusline carries the thread's name, which T3 keeps in the window
     title: follow it, since switching thread presses no key here. */
  try {
    const title = document.querySelector("title");
    if (title) new MutationObserver(refresh).observe(title, { childList: true, characterData: true, subtree: true });
  } catch { /* a title that cannot be watched simply goes stale */ }
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
    /* The last thing said on the message line, as gred's `:messages` holds
       it: what a key with no T3 counterpart answered with. */
    said() { return SEQ.flash; },
    paintNow() { paintStatus(); paintMsg(); paintKeys(); paint(); },
    /* Fire the hint panel's TIMEOUTLEN_MS wait at once, so a test can check
       the panel without sleeping for it. */
    showHintNow() {
      if (SEQ.showTimer) { clearTimeout(SEQ.showTimer); SEQ.showTimer = 0; }
      if (SEQ.node) { SEQ.show = true; refresh(); }
      return seqHint();
    },
    get sent() { return SEQ.sent; },
    get listSent() { return LIST.sent; },
    /* The panes as this file sees them, and where a direction would go, so a
       test can check the walk without a focus to move. */
    panes() { return panes().map((p) => ({ name: p.name, order: p.order })); },
    paneToward(dir) {
      const list = panes();
      const from = paneHere(list);
      if (!from) return null;
      const to = paneNearest(list, from, dir);
      return to ? to.name : null;
    },
    get paneSent() { return PANE.sent; },
    /* Graphide's list keys and what each reaches here, for the table in
       GRAPHIDE-PARITY.md and the test that keeps it honest. */
    listKeys() { return LIST_ROWS.map(([keys, act, desc]) => ({ keys, act, desc })); },
    /* Land the view where the glide is taking it, at once: a test should not
       have to wait for frames, and headless Chromium serves few of them. */
    scrollNow() {
      if (SCROLL.raf) { cancelAnimationFrame(SCROLL.raf); SCROLL.raf = 0; }
      if (SCROLL.el) {
        SCROLL.el.scrollTop = SCROLL.to;
        SCROLL.el.style.scrollBehavior = SCROLL.was || "";
      }
      return SCROLL.el ? SCROLL.el.scrollTop : 0;
    },
    timeoutlenMs: TIMEOUTLEN_MS,
    step: STEP,
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
    disable() { S.on = false; lsSet(SWITCH, "off"); S.mode = INSERT; hideUI(); refresh(); return "vim mode off, composer is a plain text box again"; },
    version: 2,
  };
})();
