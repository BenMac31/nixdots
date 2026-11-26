/* Exercises vim-composer.js in a real browser against a DOM shaped like the
   one Tiptap produces. Run: see run-tests.sh in this directory. */
(() => {
  const el = document.querySelector(".composer-tiptap");
  const out = document.getElementById("out");
  const lines = [];
  let pass = 0, fail = 0;

  /* Stand in for Tiptap's HardBreak extension, whose own keyboard shortcut is
     Shift-Enter -> setHardBreak(). The plugin drives newlines through that. */
  el.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.shiftKey) {
      e.preventDefault();
      const sel = window.getSelection();
      if (!sel.rangeCount) return;
      const r = sel.getRangeAt(0);
      r.deleteContents();
      const br = document.createElement("br");
      r.insertNode(br);
      /* ProseMirror always appends its own filler after a break that ends a
         block; without it Chromium puts later inserts before the <br>. */
      if (!br.nextSibling) {
        const f = document.createElement("br");
        f.className = "ProseMirror-trailingBreak";
        br.parentNode.appendChild(f);
      }
      r.setStartAfter(br);
      r.collapse(true);
      sel.removeAllRanges();
      sel.addRange(r);
    }
  });

  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  function setup(text, caret) {
    el.innerHTML = text.split("\n")
      .map((l) => "<p>" + (l === "" ? '<br class="ProseMirror-trailingBreak">' : esc(l)) + "</p>")
      .join("");
    el.focus();
    window.__t3vim.attach(el);
    window.__t3vim.setCaret(caret || 0);
  }

  function feed(keys) {
    for (const k of keys) {
      if (Array.isArray(k)) window.__t3vim.feed(k[0], k[1]);
      else window.__t3vim.feed(k);
    }
    return window.__t3vim.debug();
  }

  /* name, starting text, caret, keys, expectations {text,pos,mode,reg} */
  function t(name, text, caret, keys, want) {
    let got;
    try { setup(text, caret); got = feed(keys); }
    catch (err) { lines.push("FAIL " + name + "  threw: " + err.message); fail++; return; }
    if (!got) { lines.push("FAIL " + name + "  no state"); fail++; return; }
    const probs = [];
    if ("text" in want && got.text !== want.text) probs.push("text " + JSON.stringify(got.text) + " want " + JSON.stringify(want.text));
    if ("pos" in want && got.pos !== want.pos) probs.push("pos " + got.pos + " want " + want.pos);
    if ("mode" in want && got.mode !== want.mode) probs.push("mode " + got.mode + " want " + want.mode);
    if ("reg" in want && got.reg.text !== want.reg) probs.push("reg " + JSON.stringify(got.reg.text) + " want " + JSON.stringify(want.reg));
    if (probs.length) { lines.push("FAIL " + name + "  " + probs.join("; ")); fail++; }
    else { lines.push("ok   " + name); pass++; }
  }

  /* ---------------------------------------------------------- motions ---- */
  t("w word forward",        "hello world", 0, "w", { pos: 6 });
  t("2w counts",             "foo bar baz", 0, "2w", { pos: 8 });
  t("e word end",            "hello world", 0, "e", { pos: 4 });
  t("b word back",           "hello world", 6, "b", { pos: 0 });
  t("W big word",            "a.b c", 0, "W", { pos: 4 });
  t("$ end of line",         "hello world", 0, "$", { pos: 10 });
  t("0 line start",          "hello world", 10, "0", { pos: 0 });
  t("^ first non-blank",     "  indented", 9, "^", { pos: 2 });
  t("3l counts",             "hello world", 0, "3l", { pos: 3 });
  t("h stops at line start", "abc", 0, "h", { pos: 0 });
  t("l stops at line end",   "abc", 2, "l", { pos: 2 });
  t("j keeps column",        "abc\ndefgh", 1, "j", { pos: 5 });
  t("k keeps column",        "abcde\nfgh", 7, "k", { pos: 1 });
  t("f finds char",          "hello world", 0, "fo", { pos: 4 });
  t("t stops before",        "hello world", 0, "to", { pos: 3 });
  t("F backwards",           "hello world", 10, "Fo", { pos: 7 });
  t("; repeats find",        "a.b.c", 0, ["f", ".", ";"], { pos: 3 });
  t("% matches bracket",     "a(bc)d", 1, "%", { pos: 4 });
  t("gg first line",         "abc\ndef", 5, "gg", { pos: 0 });
  t("G last line",           "abc\ndef", 0, "G", { pos: 4 });
  t("2G line two",           "abc\ndef", 0, "2G", { pos: 4 });
  t("} paragraph forward",   "a\n\nb", 0, "}", { pos: 2 });

  /* -------------------------------------------------------- operators ---- */
  t("dw",                    "hello world", 0, "dw", { text: "world" });
  t("d$",                    "hello world", 0, "d$", { text: "" });
  t("dd one line",           "hello", 2, "dd", { text: "" });
  t("dd of two",             "one\ntwo", 0, "dd", { text: "two" });
  t("d2w",                   "abc def ghi", 0, "d2w", { text: "ghi" });
  t("2dw",                   "abc def ghi", 0, "2dw", { text: "ghi" });
  t("db",                    "hello world", 6, "db", { text: "world" });
  t("x deletes char",        "foo bar", 0, "x", { text: "oo bar" });
  t("3x counts",             "foo bar", 0, "3x", { text: " bar" });
  t("x stops at line end",   "ab\ncd", 1, "3x", { text: "a\ncd" });
  t("X deletes before",      "foo", 2, "X", { text: "fo" });
  t("D to end of line",      "hello", 1, "D", { text: "h" });
  t("Y then register",       "one\ntwo", 0, "Y", { reg: "one" });
  t("yw register",           "one two", 0, "yw", { reg: "one " });
  t("diw inside word",       "hello world", 7, "diw", { text: "hello " });
  t("daw around word",       "hello world", 1, "daw", { text: "world" });
  t("di quote",              'say "hi" ok', 6, ["d", "i", '"'], { text: 'say "" ok' });
  t("da quote",              'say "hi" ok', 6, ["d", "a", '"'], { text: "say  ok" });
  t("di paren",              "f(a,b)g", 3, ["d", "i", "("], { text: "f()g" });
  t("da paren",              "f(a,b)g", 3, ["d", "a", "("], { text: "fg" });
  t("di brace",              "x{y}z", 2, ["d", "i", "{"], { text: "x{}z" });
  t("r replaces",            "foo", 0, "rx", { text: "xoo" });
  t("3r replaces three",     "foobar", 0, "3rx", { text: "xxxbar" });
  t("~ toggles case",        "abc", 0, "~", { text: "Abc" });
  t("3~ toggles three",      "abc", 0, "3~", { text: "ABC" });
  t("gU word",               "abc def", 0, "gUw", { text: "ABC def" });
  t("gu word",               "ABC def", 0, "guw", { text: "abc def" });
  t("J joins lines",         "one\ntwo", 0, "J", { text: "one two" });
  t("J eats indent",         "one\n   two", 0, "J", { text: "one two" });
  t(">> indents",            "abc", 0, ">>", { text: "\tabc" });
  t("<< outdents",           "\tabc", 1, "<<", { text: "abc" });
  t("cw is ce",              "hello world", 0, "cw", { text: " world", mode: "INSERT" });
  t("cc keeps the line",     "hello", 2, "cc", { text: "", mode: "INSERT" });
  t("C to end of line",      "hello", 1, "C", { text: "h", mode: "INSERT" });
  t("s substitutes",         "abc", 0, "s", { text: "bc", mode: "INSERT" });

  /* ----------------------------------------------------------- visual ---- */
  t("v l d",                 "abc", 0, "vld", { text: "c" });
  t("v $ d",                 "abc", 0, "v$d", { text: "" });
  t("v w y register",        "one two", 0, "vwy", { reg: "one t" });
  t("V d one of two",        "one\ntwo", 0, "Vd", { text: "two" });
  t("v o swaps ends",        "abcde", 2, ["v", "l", "o", "h", "d"], { text: "ae" });
  t("v iw d",                "hello world", 7, ["v", "i", "w", "d"], { text: "hello " });
  t("v escape to normal",    "abc", 0, ["v", "l", "Escape"], { mode: "NORMAL" });

  /* ------------------------------------------------------ modes, misc ---- */
  t("i enters insert",       "abc", 1, "i", { mode: "INSERT", pos: 1 });
  t("a appends",             "abc", 1, "a", { mode: "INSERT", pos: 2 });
  t("A end of line",         "abc", 0, "A", { mode: "INSERT", pos: 3 });
  t("I first non-blank",     "  abc", 4, "I", { mode: "INSERT", pos: 2 });
  t("o opens below",         "abc", 0, "o", { text: "abc\n", mode: "INSERT" });
  t("O opens above",         "abc", 0, "O", { text: "\nabc", mode: "INSERT" });
  t("escape leaves insert",  "abc", 0, ["i", "Escape"], { mode: "NORMAL" });
  t("normal clamps to last", "abc", 0, "$", { pos: 2 });
  t("yy then p",             "abc", 0, ["y", "y", "p"], { text: "abc\nabc" });
  t("yw then p charwise",    "ab ", 0, ["y", "w", "p"], { text: "aab b " });
  t("dw then P",             "one two", 0, ["d", "w", "P"], { text: "one two" });
  t("unknown key is inert",  "abc", 0, "Q", { text: "abc" });
  t("count then escape",     "abc", 0, ["3", "Escape", "l"], { pos: 1 });

  /* ------------------------------------------------------- multi-line ---- */
  t("2dd",                   "one\ntwo\nthree", 0, "2dd", { text: "three" });
  t("2yy then p",            "one\ntwo", 0, ["2", "y", "y", "p"], { text: "one\none\ntwo\ntwo" });
  t("dG to last line",       "one\ntwo\nthree", 4, "dG", { text: "one" });
  t("dgg to first line",     "one\ntwo\nthree", 4, "dgg", { text: "three" });
  t("Vjd two lines",         "one\ntwo\nthree", 0, ["V", "j", "d"], { text: "three" });
  t("Vj> indents both",      "one\ntwo", 0, ["V", "j", ">"], { text: "\tone\n\ttwo" });
  t("d} to blank line",      "one\n\ntwo", 0, "d}", { text: "\ntwo" });
  t("ci( then insert",       "f(abc)g", 3, ["c", "i", "("], { text: "f()g", mode: "INSERT" });
  t("dt comma",              "a,b", 0, ["d", "t", ","], { text: ",b" });
  t("df comma",              "a,b", 0, ["d", "f", ","], { text: "b" });
  t("3j clamps at last",     "a\nb", 0, "3j", { pos: 2 });
  t("yank then dd then P",   "one\ntwo", 0, ["y", "y", "j", "P"], { text: "one\none\ntwo" });
  t("cw mid-word",           "hello world", 2, "cw", { text: "he world", mode: "INSERT" });
  t("x on empty line",       "a\n\nb", 2, "x", { text: "a\n\nb" });
  t("$ on empty line",       "a\n\nb", 2, "$", { pos: 2 });

  /* ------------------------------------------------------ key sequences -- */
  /* Every chord the plugin sends lands on this spy: window, bubble phase. */
  const sent = [];
  window.addEventListener("keydown", (e) => {
    if (e.ctrlKey && e.altKey && e.shiftKey) {
      sent.push({ key: e.key, meta: e.metaKey, trusted: e.isTrusted, atWindow: e.target === window,
                  bubbles: e.bubbles, cancelable: e.cancelable });
    }
  });

  const V = window.__t3vim;
  const keysOf = (spec) => {
    /* a step is a gred-notation string fed whole, or [key, mods] */
    for (const k of spec) {
      if (Array.isArray(k)) V.feed(k[0], k[1]);
      else if (k.length > 1 && k !== "Escape" && k !== "Enter" && k !== "Shift") V.feedSeq(k);
      else V.feed(k);
    }
  };

  /* name, setup fn, steps, check(got, sent) -> problem string or "" */
  function ts(name, prep, steps, check) {
    let got, prob;
    sent.length = 0;
    try { prep(); keysOf(steps); got = V.debug(); prob = check(got, sent.slice()); }
    catch (err) { prob = "threw: " + err.message; }
    if (prob) { lines.push("FAIL " + name + "  " + prob); fail++; }
    else { lines.push("ok   " + name); pass++; }
  }
  const composer = (text, caret) => () => setup(text, caret);
  const global = () => () => { setup("abc", 0); el.blur(); document.body.focus(); };
  const oneChord = (key) => (got, s) => {
    if (s.length !== 1) return "sent " + JSON.stringify(s.map((x) => x.key)) + " want [" + key + "]";
    const c = s[0];
    if (c.key !== key) return "sent " + c.key + " want " + key;
    if (c.meta || c.trusted || !c.atWindow || !c.bubbles || !c.cancelable) return "chord shape " + JSON.stringify(c);
    if (got.seq) return "seq left pending: " + got.seq;
    return "";
  };
  const none = (extra) => (got, s) => {
    if (s.length) return "sent " + JSON.stringify(s.map((x) => x.key)) + " want nothing";
    if (got.seq) return "seq left pending: " + got.seq;
    return extra ? extra(got) : "";
  };
  const want = (field, v) => (got) => (got[field] === v ? "" : field + " " + JSON.stringify(got[field]) + " want " + JSON.stringify(v));

  /* The dispatch contract, written out independently of the plugin's table. */
  const CONTRACT = [
    ["<leader>sf", "f"], ["<leader>sg", "g"], ["<leader>sc", "c"], ["<leader><leader>", "c"],
    ["<leader>/", "/"], ["<leader>an", "n"], ["<leader>aN", "o"], ["<leader>ak", "k"],
    ["<leader>am", "m"], ["<leader>ah", "m"], ["<leader>ae", "e"], ["<leader>at", "t"],
    ["<leader>av", "v"], ["<leader>aw", "w"], ["<leader>al", "l"], ["<leader>ay", "y"],
    ["<leader>ap", "p"], ["<leader>aT", "i"], ["<leader>ac", "h"], ["<leader>tt", "a"],
    ["<leader>tw", "r"], ["<leader>hp", "d"], ["<C-w>s", "s"], ["<C-w>v", "b"],
    ["<C-w>c", "x"], ["<C-w>q", "x"], ["<C-w>T", "u"], ["gt", "."], ["]a", "."],
    ["gT", ","], ["[a", ","], ["ga", "j"],
  ];
  for (const [seq, key] of CONTRACT) {
    ts("normal " + seq + " sends " + key, composer("hello world", 3), [seq],
       (g, s) => oneChord(key)(g, s) || want("text", "hello world")(g) || want("mode", "NORMAL")(g) || want("pos", 3)(g));
  }
  for (const [seq, key] of CONTRACT) {
    ts("global " + seq + " sends " + key, global(), [seq], oneChord(key));
  }
  ts("visual <leader>an sends n, stays visual", composer("hello", 0), ["v", "l", "<leader>an"],
     (g, s) => oneChord("n")(g, s) || want("mode", "VISUAL")(g));
  ts("<C-w><C-s> is <C-w>s", composer("abc", 0), [["w", { ctrl: true }], ["s", { ctrl: true }]], oneChord("s"));
  ts("held Space does not walk the tree", composer("abc", 0), [],
     (g) => { V.feed(" "); V.feed(" ", { repeat: true }); return want("seq", "<leader>")(V.debug()); });
  ts("shift keydown keeps <leader>a pending", composer("abc", 0), ["<leader>a", "Shift", ["N", { shift: true }]], oneChord("o"));
  ts(": sends the palette chord in normal", composer("abc", 1), [":"],
     (g, s) => oneChord("c")(g, s) || want("text", "abc")(g));
  ts(": sends the palette chord in visual", composer("abc", 1), ["v", ":"], oneChord("c"));
  ts(": is left to T3 with nothing focused", global(), [":"], none());

  /* g is shared: vim keeps gg gu gU g~ ge, the app gets gt gT ga. */
  ts("g merge: guw is vim",  composer("ABC def", 0), ["g", "u", "w"], none(want("text", "abc def")));
  ts("g merge: gUw is vim",  composer("abc def", 0), ["g", "U", "w"], none(want("text", "ABC def")));
  ts("g merge: gg is vim",   composer("abc\ndef", 5), ["g", "g"], none(want("pos", 0)));
  ts("g merge: 2gg is vim",  composer("abc\ndef\nghi", 0), ["2", "g", "g"], none(want("pos", 4)));
  /* ge itself is approximate in the vim layer (it lands on the word start);
     this only checks that g e reaches vim and nothing is sent. */
  ts("g merge: ge is vim",   composer("abc def", 5), ["g", "e"], none((g) => (g.pos < 5 ? "" : "pos " + g.pos)));
  ts("g merge: dgg is vim",  composer("one\ntwo\nthree", 4), ["d", "g", "g"], none(want("text", "three")));
  ts("g merge: v l gU",      composer("abc", 0), ["v", "l", "g", "U"], none(want("text", "ABc")));
  ts("g merge: gt is the app", composer("abc", 0), ["g", "t"], (g, s) => oneChord(".")(g, s) || want("text", "abc")(g));

  /* No T3 counterpart: consumed, nothing sent, a message says so. */
  for (const seq of ["<leader>q", "<leader>m", "<leader>T", "<leader>so", "<leader>ds", "<leader>rn",
                     "<leader>hs", "<leader>aF", "]q", "[q", "]d", "[d", "gd", "gD", "grr", "gra",
                     "<C-w>o", "<C-w>=", "<C-w>H", "<C-w><lt>"]) {
    ts("no counterpart " + seq, composer("hello world", 3), [seq],
       none((g) => want("text", "hello world")(g) || want("pos", 3)(g) || want("mode", "NORMAL")(g)
         || (/no T3 equivalent/.test((V.hint() || {}).message || "") ? "" : "message " + JSON.stringify(V.hint()))));
  }
  ts("unmapped key after prefix is eaten", composer("hello", 0), ["<leader>", "x"],
     none((g) => want("text", "hello")(g) || (/not mapped/.test((V.hint() || {}).message || "") ? "" : "message " + JSON.stringify(V.hint()))));

  /* Escape */
  ts("Escape cancels <leader>", composer("hello", 0), ["<leader>", "Escape", "l"],
     none((g) => want("pos", 1)(g) || want("mode", "NORMAL")(g)));
  ts("Escape cancels <leader>s", composer("hello", 0), ["<leader>s", "Escape", "f", "l"],
     none((g) => want("pos", 2)(g)));
  ts("Escape cancels <C-w>", composer("hello", 0), ["<C-w>", "Escape", "s"],
     none((g) => want("text", "ello")(g) || want("mode", "INSERT")(g)));
  ts("Escape cancels globally", global(), ["<leader>a", "Escape", "n"], none());
  ts("Enter drops a pending sequence and sends", composer("abc", 0), ["<leader>", "Enter"],
     none(want("mode", "INSERT")));

  /* Counts and vim's own pending keys are untouched. */
  ts("3dd after a sequence", composer("a\nb\nc\nd", 0), ["<leader>sf", "3", "d", "d"],
     (g, s) => (s.length === 1 ? "" : "sent " + s.length) || want("text", "d")(g));
  ts("3l after a sequence", composer("hello world", 0), ["]a", "3", "l"], (g, s) => want("pos", 3)(g));
  ts("count cleared by a sequence", composer("hello world", 0), ["3", "<leader>sf", "l"], (g) => want("pos", 1)(g));
  ts("digit is not a tree key", composer("hello", 0), ["<leader>", "3", "l"], none(want("pos", 1)));
  ts("f<Space> is vim's find",   composer("ab cd", 0), ["f", " "], none(want("pos", 2)));
  ts("r] is vim's replace",      composer("abc", 0), ["r", "]"], none(want("text", "]bc")));
  ts("di[ is vim's text object", composer("x[ab]y", 2), ["d", "i", "["], none(want("text", "x[]y")));
  ts("d<Space> is vim's motion", composer("abc", 0), ["d", " "], none(want("text", "bc")));
  ts("fg is vim's find",         composer("abg", 0), ["f", "g"], none(want("pos", 2)));

  /* Insert mode: every key is the composer's. */
  ts("insert: Space g ] : not taken", composer("abc", 0), ["i", " ", "g", "]", "[", ":", ["w", { ctrl: true }]],
     none(want("mode", "INSERT")));

  /* Focus that wants its own keys. */
  ts("global: input keeps its keys", () => {
       setup("abc", 0);
       const i = document.createElement("input"); i.id = "tmp-input"; document.body.appendChild(i); i.focus();
     }, [" ", "s", "f"], (g, s) => { document.getElementById("tmp-input").remove(); return none()(g, s); });
  ts("global: menu keeps its keys", () => {
       setup("abc", 0);
       const m = document.createElement("div"); m.id = "tmp-menu"; m.setAttribute("role", "menu"); m.tabIndex = 0;
       document.body.appendChild(m); m.focus();
     }, ["g", "t"], (g, s) => { document.getElementById("tmp-menu").remove(); return none()(g, s); });
  ts("global: a focused button keeps Space", () => {
       setup("abc", 0);
       const b = document.createElement("button"); b.id = "tmp-btn"; b.textContent = "go";
       document.body.appendChild(b); b.focus();
     }, [" "], (g, s) => { document.getElementById("tmp-btn").remove(); return none()(g, s); });
  ts("global: a focused checkbox role keeps Space", () => {
       setup("abc", 0);
       const c = document.createElement("div"); c.id = "tmp-cb"; c.setAttribute("role", "checkbox");
       c.tabIndex = 0; document.body.appendChild(c); c.focus();
     }, [" "], (g, s) => { document.getElementById("tmp-cb").remove(); return none()(g, s); });
  ts("global: plain keys pass", global(), ["x", "c", "l"], none());

  /* Hint panel content */
  ts("hint after <leader>", composer("abc", 0), ["<leader>"], (g) => {
    const h = V.hint();
    if (!h || g.seq !== "<leader>") return "no hint, seq " + g.seq;
    const s = h.items.find((x) => x.key === "s"), sp = h.items.find((x) => x.key === "SPC");
    if (!s || s.desc !== "+[S]earch") return "s item " + JSON.stringify(s);
    if (!sp || sp.desc !== "switch agent") return "SPC item " + JSON.stringify(sp);
    return "";
  });
  ts("hint after <leader>a", composer("abc", 0), ["<leader>a"], (g) => {
    const h = V.hint();
    const n = h && h.items.find((x) => x.key === "n"), r = h && h.items.find((x) => x.key === "r");
    if (!n || n.desc !== "new agent" || n.none) return "n item " + JSON.stringify(n);
    if (!r || !r.none) return "r item " + JSON.stringify(r);
    return /\[A\]gents/.test(h.title) ? "" : "title " + h.title;
  });

  /* The synthetic chord never re-enters the plugin. */
  ts("no recursion: one chord per sequence", composer("abc", 0), ["<leader>sf"],
     (g, s) => (s.length === 1 && V.sent >= 1 ? "" : "sent " + s.length) || want("seq", "")(g) || want("mode", "NORMAL")(g));
  ts("no recursion: untrusted Space at the composer is ignored", composer("abc", 0), [],
     (g) => {
       el.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true, cancelable: true }));
       el.dispatchEvent(new KeyboardEvent("keydown", { key: "w", ctrlKey: true, bubbles: true, cancelable: true }));
       return want("seq", "")(V.debug()) || want("text", "abc")(V.debug());
     });
  ts("no recursion: untrusted g with nothing focused is ignored", global(), [],
     () => {
       document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "g", bubbles: true, cancelable: true }));
       return want("seq", "")(V.debug());
     });
  ts("no recursion: a chord at window does not reach the plugin", composer("abc", 0), ["<leader>"],
     (g) => {
       /* if the plugin saw this it would complete <leader>/ */
       window.dispatchEvent(new KeyboardEvent("keydown", { key: "/", bubbles: true, cancelable: true }));
       return want("seq", "<leader>")(V.debug());
     });

  /* ---------------------------------------------------- timed (async) ---- */
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  /* Headless Chromium stops serving requestAnimationFrame after the first
     frame, so paint synchronously rather than waiting on one. */
  const frames = async () => { V.paintNow(); };
  async function ta(name, fn) {
    sent.length = 0;
    let prob;
    try { prob = await fn(); } catch (err) { prob = "threw: " + err.message; }
    if (prob) { lines.push("FAIL " + name + "  " + prob); fail++; }
    else { lines.push("ok   " + name); pass++; }
    out.textContent = lines.join("\n") + "\n\n(still running)\n";
  }

  (async () => {
    const T = V.seqTimeoutMs;
    await ta("timeout is 1000 ms", async () => (T === 1000 ? "" : "seqTimeoutMs " + T));
    await ta("timeout resets <leader>", async () => {
      setup("hello", 0); V.feedSeq("<leader>s");
      await wait(T + 150);
      if (V.debug().seq) return "seq still " + V.debug().seq;
      V.feed("f"); V.feed("l");
      return none(want("pos", 2))(V.debug(), sent);
    });
    await ta("each key re-arms the timeout", async () => {
      setup("hello", 0); V.feedSeq("<leader>");
      await wait(T * 0.6); V.feed("s");
      await wait(T * 0.6); V.feed("f");
      return oneChord("f")(V.debug(), sent);
    });
    await ta("a timed-out g is still vim's g (gg)", async () => {
      setup("abc\ndef", 5); V.feed("g");
      await wait(T + 150);
      V.feed("g");
      return none(want("pos", 0))(V.debug(), sent);
    });
    await ta("hint panel shows the leader tree", async () => {
      setup("abc", 0); V.feedSeq("<leader>");
      await frames();
      const p = document.querySelector(".t3vim-keys");
      if (!p || p.style.display !== "block") return "panel hidden";
      if (!/\[S\]earch/.test(p.textContent) || !/switch agent/.test(p.textContent)) return "panel text " + p.textContent.slice(0, 120);
      V.feed("Escape");
      await frames();
      return p.style.display === "none" ? "" : "panel still shown after Escape";
    });
    await ta("hint panel works with nothing focused", async () => {
      setup("abc", 0); el.blur(); document.body.focus(); V.feed("w", { ctrl: true });
      await frames();
      const p = document.querySelector(".t3vim-keys");
      const ok = p && p.style.display === "block" && /Windows/.test(p.textContent);
      V.feed("Escape");
      return ok ? "" : "panel " + (p ? p.style.display + " " + p.textContent.slice(0, 80) : "missing");
    });

    out.textContent = lines.join("\n") + "\n\nPASS " + pass + "  FAIL " + fail + "\n";
    document.title = fail === 0 ? "ALLPASS" : "FAILURES:" + fail;
  })();
})();
