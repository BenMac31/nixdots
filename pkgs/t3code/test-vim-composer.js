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
  /* Vim's three erasers while typing. T3 had all three: mod+w closed the
     right panel, mod+u opened the usage page, mod+h stepped the pane ring. */
  t("<C-w> erases a word",   "hello world", 10, ["A", ["w", { ctrl: true }]],
    { text: "hello ", pos: 6, mode: "INSERT" });
  t("<C-w> twice",           "hello world", 10, ["A", ["w", { ctrl: true }], ["w", { ctrl: true }]],
    { text: "", pos: 0, mode: "INSERT" });
  t("<C-h> erases a char",   "abc", 2, ["A", ["h", { ctrl: true }]],
    { text: "ab", pos: 2, mode: "INSERT" });
  t("<C-u> erases the line", "one\ntwo", 4, ["A", ["u", { ctrl: true }]],
    { text: "one\n", pos: 4, mode: "INSERT" });
  t("<C-h> at the start does nothing", "abc", 0, ["i", ["h", { ctrl: true }]],
    { text: "abc", pos: 0, mode: "INSERT" });
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
      sent.push({ key: e.key, code: e.code, meta: e.metaKey, trusted: e.isTrusted,
                  atWindow: e.target === window, bubbles: e.bubbles, cancelable: e.cancelable });
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
    ["<leader>sf", "f"], ["<leader>sg", "g"], ["<leader>sc", "c"],
    ["<leader>/", "/"], ["<leader>an", "n"], ["<leader>aN", "o"], ["<leader>ak", "k"],
    ["<leader>am", "m"], ["<leader>ah", "m"], ["<leader>ae", "e"], ["<leader>at", "t"],
    ["<leader>av", "v"], ["<leader>aw", "w"], ["<leader>al", "l"], ["<leader>ay", "y"],
    ["<leader>ap", "p"], ["<leader>aT", "i"], ["<leader>ac", "h"], ["<leader>tt", "a"],
    ["<leader>tw", "r"], ["<leader>hp", "d"], ["<C-w>s", "s"], ["<C-w>v", "b"],
    ["<C-w>T", "u"], ["gt", "."], ["]a", "."],
    ["gT", ","], ["[a", ","], ["ga", "j"],
    ["<leader>ai", ";"], ["<leader>sp", ";"],
    /* <C-w>h j k l, and <C-w>c and q, are no longer one chord each: the
       direction comes from where the panes are and the close from which pane
       it is. The panes section below has them. */
    ["<leader>1", "1"], ["<leader>2", "2"], ["<leader>3", "3"], ["<leader>4", "4"],
    ["<leader>5", "5"], ["<leader>6", "6"], ["<leader>7", "7"], ["<leader>8", "8"],
    ["<leader>9", "9"],
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
  /* T3's thread.jump.N under the leader, and a digit chord carries a Digit
     code rather than an empty one. */
  ts("<leader>1 jumps to agent 1", composer("abc", 0), ["<leader>1"],
     (g, s) => oneChord("1")(g, s) || (s[0].code === "Digit1" ? "" : "code " + s[0].code));
  /* Graphide's agent picker has no T3 equivalent: consumed, nothing sent. */
  ts("<leader><leader> sends nothing", composer("abc", 0), ["<leader>", "<leader>"],
     (g, s) => (s.length === 0 ? "" : "sent " + JSON.stringify(s.map((x) => x.key)))
               || want("text", "abc")(g) || want("seq", "")(g));
  /* The panel waits HINT_DELAY_MS, so a fast two-key sequence never flashes it. */
  ts("the hint panel is not up before its delay", composer("abc", 0), ["<leader>"],
     (g) => (V.hint() === null && g.seq === "<leader>" ? "" : "hint up at once: " + JSON.stringify(V.hint())));
  ts("held Space does not walk the tree", composer("abc", 0), [],
     (g) => { V.feed(" "); V.feed(" ", { repeat: true }); return want("seq", "<leader>")(V.debug()); });
  ts("shift keydown keeps <leader>a pending", composer("abc", 0), ["<leader>a", "Shift", ["N", { shift: true }]], oneChord("o"));
  /* dd with nothing to delete settles the thread, as Graphide's own composer
     does with it (fleet/src/composer.rs). Whitespace is something, so it is
     only the empty one. */
  ts("dd in an empty composer settles the thread", composer("", 0), ["d", "d"],
     (g, s) => oneChord("p")(g, s));
  ts("dd on a blank line still deletes it", composer("   ", 0), ["d", "d"],
     (g, s) => none()(g, s) || want("text", "")(g));
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
                     "<C-w>=", "<C-w>H", "<C-w><lt>"]) {
    ts("no counterpart " + seq, composer("hello world", 3), [seq],
       none((g) => want("text", "hello world")(g) || want("pos", 3)(g) || want("mode", "NORMAL")(g)
         || (/no T3 equivalent/.test(V.said()) ? "" : "said " + JSON.stringify(V.said()))));
  }
  ts("unmapped key after prefix is eaten", composer("hello", 0), ["<leader>", "x"],
     none((g) => want("text", "hello")(g) || (/not mapped/.test(V.said()) ? "" : "said " + JSON.stringify(V.said()))));

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
  /* A digit after the leader is an agent jump; a digit with nothing pending
     is still a count, which the four tests above cover. */
  ts("<leader>3 jumps, then l is vim's", composer("hello", 0), ["<leader>", "3", "l"],
     (g, s) => oneChord("3")(g, s) || want("pos", 1)(g));
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

  /* ------------------------------------------------------------- panes --- */

  /* The window the fixture lays out: sidebar on the left, the conversation
     with the composer under it, details on the right, the terminal at the
     foot. Graphide's <C-w>h and friends pick the pane the eye picks
     (panes.rs::nearest), so what is tested is the direction, not a ring
     step. */
  const area = (name) => document.querySelector('[data-workspace-area="' + name + '"]');
  const focusArea = (name) => { const a = area(name); a.focus(); return a; };
  const areaNow = () => {
    const a = document.activeElement;
    const box = a && a.closest ? a.closest("[data-workspace-area]") : null;
    return box ? box.dataset.workspaceArea : undefined;
  };

  /* T3's own ring, as its focus module walks it: the visible areas by order,
     wrapping, moved by the two chords the plugin sends. Installed only for
     the tests that need the focus to actually travel. */
  function ring() {
    const onKey = (e) => {
      if (!(e.ctrlKey && e.altKey && e.shiftKey)) return;
      if (e.key !== "z" && e.key !== "q") return;
      const all = Array.from(document.querySelectorAll("[data-workspace-area]"))
        .sort((a, b) => Number(a.dataset.workspaceOrder) - Number(b.dataset.workspaceOrder));
      const at = document.activeElement;
      const box = at && at.closest ? at.closest("[data-workspace-area]") : null;
      const i = all.indexOf(box);
      const d = e.key === "z" ? 1 : -1;
      const to = all[i < 0 ? (d === 1 ? 0 : all.length - 1) : (i + d + all.length) % all.length];
      if (to) to.focus();
    };
    window.addEventListener("keydown", onKey, false);
    return () => window.removeEventListener("keydown", onKey, false);
  }

  /* name, the pane to start in, steps, check() */
  function tw(name, from, steps, check) {
    ts("panes: " + name, () => { setup("abc", 0); el.blur(); focusArea(from); }, steps, (g, s) => {
      let prob;
      try { prob = check(g, s); } finally { el.focus(); }
      return prob;
    });
  }
  const inArea = (name) => () => (areaNow() === name ? "" : "in " + JSON.stringify(areaNow()) + " want " + name);

  /* The geometry on its own, with nothing focused to move. */
  ts("panes: the fixture is the window T3 lays out", global(), [], () => {
    const names = V.panes().map((p) => p.name).join(",");
    return names === "sidebar,conversation,composer,details,terminal" ? "" : "panes " + names;
  });
  tw("h from the conversation is the sidebar", "conversation", [], () =>
    (V.paneToward("h") === "sidebar" ? "" : "h -> " + V.paneToward("h")));
  tw("l from the conversation is the details", "conversation", [], () =>
    (V.paneToward("l") === "details" ? "" : "l -> " + V.paneToward("l")));
  tw("j from the conversation is the composer", "conversation", [], () =>
    (V.paneToward("j") === "composer" ? "" : "j -> " + V.paneToward("j")));
  tw("k from the composer is the conversation", "composer", [], () =>
    (V.paneToward("k") === "conversation" ? "" : "k -> " + V.paneToward("k")));
  tw("j from the composer is the terminal", "composer", [], () =>
    (V.paneToward("j") === "terminal" ? "" : "j -> " + V.paneToward("j")));
  /* The bug this replaced: from the sidebar the ring's next pane is the
     conversation, so <C-w>j walked sideways. Nothing is below the sidebar. */
  tw("nothing is below the sidebar", "sidebar", [], () =>
    (V.paneToward("j") === null ? "" : "j -> " + V.paneToward("j")));
  tw("nothing is above the sidebar", "sidebar", [], () =>
    (V.paneToward("k") === null ? "" : "k -> " + V.paneToward("k")));
  tw("h and k from the conversation are not the same pane", "conversation", [], () =>
    (V.paneToward("h") !== V.paneToward("k") ? "" : "both " + V.paneToward("h")));

  /* End to end: the direction is decided here and T3's ring carries it. */
  tw("<C-w>l steps the ring until it arrives", "conversation", [], () => {
    const off = ring();
    try { V.feedSeq("<C-w>l"); return inArea("details")(); } finally { off(); }
  });
  tw("<C-w>h steps the ring backwards", "conversation", [], () => {
    const off = ring();
    try { V.feedSeq("<C-w>h"); return inArea("sidebar")(); } finally { off(); }
  });
  tw("bare <C-l> is the pane to the right", "conversation", [], () => {
    const off = ring();
    try { V.feed("l", { ctrl: true }); return inArea("details")(); } finally { off(); }
  });
  tw("bare <C-j> is the pane below", "conversation", [], () => {
    const off = ring();
    try { V.feed("j", { ctrl: true }); return inArea("composer")(); } finally { off(); }
  });
  tw("a direction with no pane steps nothing and says so", "sidebar", [], () => {
    const off = ring();
    const before = V.paneSent;
    try {
      V.feedSeq("<C-w>j");                 /* nothing below the sidebar */
      if (V.paneSent !== before) return "it stepped the ring with nowhere to go";
      if (areaNow() !== "sidebar") return "the focus left for " + areaNow();
      return /no pane below/.test(V.said()) ? "" : "said " + JSON.stringify(V.said());
    } finally { off(); }
  });
  /* An area T3 has put away is not a pane. */
  tw("a hidden pane is skipped", "conversation", [], () => {
    const d = area("details");
    d.setAttribute("aria-hidden", "true");
    try {
      const to = V.paneToward("l");
      return to === null ? "" : "l -> " + to + " with the details hidden";
    } finally { d.removeAttribute("aria-hidden"); }
  });
  /* <C-w>c closes the pane it is in, which is a different command per pane. */
  tw("<C-w>c in the details closes the details", "details", ["<C-w>c"], oneChord("v"));
  tw("<C-w>c in the terminal closes the terminal", "terminal", ["<C-w>c"], oneChord("]"));
  tw("<C-w>c in the sidebar puts the sidebar away", "sidebar", ["<C-w>c"], oneChord("["));
  tw("<C-w>c in the chat says it cannot be closed", "conversation", ["<C-w>c"], (g, s) =>
    (s.length ? "sent " + s[0].key : "") || (/cannot be closed/.test(V.said()) ? "" : "said " + JSON.stringify(V.said())));
  tw("<C-w>o leaves the chat alone and shuts the rest", "conversation", ["<C-w>o"], (g, s) => {
    const keys = s.map((x) => x.key).sort().join(",");
    return keys === "[,],v" ? "" : "sent " + keys + " want [,],v";
  });
  tw("<C-w>w is the ring's next", "conversation", ["<C-w>w"], oneChord("z"));
  tw("<C-w>p is the ring's previous", "conversation", ["<C-w>p"], oneChord("q"));
  /* In the composer, in normal mode, the four directions are still the app's. */
  ts("panes: <C-l> in the composer leaves it", composer("abc", 0), [], () => {
    const off = ring();
    try { V.feed("l", { ctrl: true }); return inArea("details")(); }
    finally { off(); el.focus(); }
  });

  /* ------------------------------------------------------------- lists --- */

  /* T3's own thread list, built as its bundle builds it: rows are
     `div role="button" tabindex="0" data-sidebar-row`, and the container
     listens in the capture phase for the arrows, Home and End, ignoring any
     event that carries a modifier or is already handled. Copied from T3
     rather than invented, so these fail if the keys the plugin sends stop
     being the keys T3 waits for. */
  function sidebar(rows) {
    const box = document.createElement("div");
    box.id = "tmp-sidebar";
    for (let i = 0; i < rows; i++) {
      const r = document.createElement("div");
      r.setAttribute("role", "button");
      r.tabIndex = 0;
      r.dataset.sidebarRow = "row" + i;
      r.textContent = "thread " + i;
      box.appendChild(r);
    }
    box.addEventListener("keydown", (e) => {
      const t = e.target;
      if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      if (!(t instanceof HTMLElement) || !t.matches("[data-sidebar-row]")) return;
      const all = Array.from(box.querySelectorAll("[data-sidebar-row]"));
      const at = all.indexOf(t);
      if (at < 0) return;
      let to = null;
      switch (e.key) {
        case "ArrowDown": to = all[Math.min(at + 1, all.length - 1)]; break;
        case "ArrowUp": to = all[Math.max(at - 1, 0)]; break;
        case "Home": to = all[0]; break;
        case "End": to = all[all.length - 1]; break;
        case "ArrowRight": box.dataset.expanded = "yes"; break;
        case "ArrowLeft": box.dataset.expanded = "no"; break;
        default: return;
      }
      e.preventDefault();
      e.stopPropagation();
      if (to) to.focus({ preventScroll: true });
    }, true);
    document.body.appendChild(box);
    return box;
  }
  /* name, rows, the row to start on, steps, check(box) */
  function tl(name, rows, start, steps, check) {
    const prep = () => {
      setup("abc", 0);
      el.blur();
      const box = sidebar(rows);
      box.querySelector('[data-sidebar-row="row' + start + '"]').focus();
    };
    ts("list: " + name, prep, steps, (g, s) => {
      const box = document.getElementById("tmp-sidebar");
      let prob;
      try { prob = check(box, g, s); } finally { box.remove(); el.focus(); }
      return prob;
    });
  }
  const at = (row) => {
    const a = document.activeElement;
    const got = a && a.dataset ? a.dataset.sidebarRow : undefined;
    return got === row ? "" : "focus " + JSON.stringify(got) + " want " + JSON.stringify(row);
  };

  tl("j moves down", 3, 0, ["j"], (b, g, s) => none(() => at("row1"))(g, s));
  tl("k moves up", 3, 2, ["k"], (b, g, s) => none(() => at("row1"))(g, s));
  tl("jj moves twice", 3, 0, ["jj"], () => at("row2"));
  tl("j stops at the last row", 3, 2, ["jj"], () => at("row2"));
  tl("k stops at the first row", 3, 0, ["k"], () => at("row0"));
  tl("gg goes to the first row", 4, 3, ["gg"], () => at("row0"));
  tl("G goes to the last row", 4, 0, ["G"], () => at("row3"));
  tl("l opens a group, h closes it", 3, 0, ["l"], (b) => {
    if (b.dataset.expanded !== "yes") return "l did not open: " + b.dataset.expanded;
    V.feed("h");
    return b.dataset.expanded === "no" ? "" : "h did not close: " + b.dataset.expanded;
  });
  /* Space still activates the focused row, and the leader is not taken. */
  tl("Space is the row's", 3, 1, [" "], (b, g, s) => none(() => at("row1"))(g, s));
  tl("Enter is the row's", 3, 1, ["Enter"], (b, g, s) => none(() => at("row1"))(g, s));
  /* <C-j> is the pane below, not a move in the list: the list's own chords
     are the four below, and gred's list table has no <C-j>. */
  tl("<C-j> is the pane below, not a row", 3, 0, [["j", { ctrl: true }]], (b) => at("row0"));
  /* A thread being renamed is an input inside a row: every key is its own. */
  tl("a rename input keeps its keys", 3, 0, [], (b) => {
    const row = b.querySelector('[data-sidebar-row="row0"]');
    const i = document.createElement("input");
    row.appendChild(i);
    i.focus();
    const before = V.listSent;
    V.feed("j"); V.feed("k"); V.feed("g"); V.feed("g");
    if (V.listSent !== before) return "sent " + (V.listSent - before) + " arrows into a rename";
    return document.activeElement === i ? "" : "focus left the input";
  });
  /* g on a row is the app's prefix, and a prefix that only leads on waits as
     long as it takes (modal::Resolver), so it is still pending. Escape lets
     it go, and nothing was sent meanwhile. */
  tl("g waits on a row, and Escape lets it go", 3, 1, ["g"], (b, g, s) => {
    if (s.length) return "sent " + s[0].key;
    if (V.state.seq !== "g") return "seq " + JSON.stringify(V.state.seq);
    V.feed("Escape");
    return V.state.seq === "" ? at("row1") : "Escape left " + JSON.stringify(V.state.seq);
  });

  /* The acts: every key of Graphide's list table is answered, by a T3
     command, by something done here, or by saying there is none. The six
     movements above were all that worked before. */
  tl("dd settles the agent", 3, 1, ["d", "d"], (b, g, s) => oneChord("p")(g, s) || at("row1"));
  tl("gp pins it", 3, 1, ["g", "p"], (b, g, s) => oneChord("i")(g, s));
  tl("o starts a new agent", 3, 1, ["o"], (b, g, s) => oneChord("n")(g, s));
  tl("K shows the details", 3, 1, ["K"], (b, g, s) => oneChord("v")(g, s));
  tl("]c is its change", 3, 1, ["]", "c"], (b, g, s) => oneChord("d")(g, s));
  tl("<C-c> stops its turn", 3, 1, [["c", { ctrl: true }]], (b, g, s) => oneChord("k")(g, s));
  /* The platform owes a copy before Graphide owes an interrupt. */
  tl("<C-c> with a selection is a copy", 3, 1, [], (b) => {
    const r = document.createRange();
    r.selectNodeContents(b.querySelector('[data-sidebar-row="row1"]'));
    const sel = window.getSelection();
    sel.removeAllRanges(); sel.addRange(r);
    const before = V.sent;
    V.feed("c", { ctrl: true });
    sel.removeAllRanges();
    return V.sent === before ? "" : "it sent a chord over a selection";
  });
  /* A key Graphide has and T3 has not: it says so rather than going dead. */
  tl("a key T3 has nothing for says so", 3, 1, ["!"], (b, g, s) =>
    (s.length ? "sent " + s[0].key : "") ||
    (/no T3 equivalent/.test(V.said()) ? "" : "said " + JSON.stringify(V.said())));
  tl("dd is not d alone", 3, 1, ["d"], (b, g, s) =>
    (s.length ? "sent " + s[0].key : "") || (V.state.seq === "d" ? "" : "seq " + JSON.stringify(V.state.seq)));
  /* <C-d> is half the list, which T3 handles no PageDown for: it is that
     many arrows, so the list's own scroll and lazy loading still run. */
  tl("<C-d> is half the list down", 8, 0, [["d", { ctrl: true }]], (b) => {
    const now = document.activeElement.dataset.sidebarRow;
    return now !== "row0" ? "" : "it did not move";
  });

  /* The groups: T3 puts aria-expanded on a group row and clicks it open, so
     za zo zc are that click and zR zM are every row's. */
  function groups() {
    const box = document.createElement("div");
    box.id = "tmp-sidebar";
    for (let i = 0; i < 3; i++) {
      const r = document.createElement("div");
      r.setAttribute("role", "button");
      r.tabIndex = 0;
      r.dataset.sidebarRow = "g" + i;
      r.setAttribute("aria-expanded", i === 0 ? "false" : "true");
      r.addEventListener("click", () => {
        r.setAttribute("aria-expanded", r.getAttribute("aria-expanded") === "true" ? "false" : "true");
      });
      box.appendChild(r);
    }
    document.body.appendChild(box);
    return box;
  }
  function tg(name, start, steps, check) {
    ts("list: " + name, () => {
      setup("abc", 0); el.blur();
      groups().querySelector('[data-sidebar-row="g' + start + '"]').focus();
    }, steps, (g, s) => {
      const box = document.getElementById("tmp-sidebar");
      const open = Array.from(box.querySelectorAll("[data-sidebar-row]"))
        .map((r) => r.getAttribute("aria-expanded")).join(",");
      let prob;
      try { prob = check(open, g, s); } finally { box.remove(); el.focus(); }
      return prob;
    });
  }
  const opens = (want) => (open) => (open === want ? "" : "expanded " + open + " want " + want);

  tg("za opens a closed group", 0, ["z", "a"], opens("true,true,true"));
  tg("za closes an open group", 1, ["z", "a"], opens("false,false,true"));
  tg("zo opens and leaves an open one alone", 1, ["z", "o"], opens("false,true,true"));
  tg("zc closes an open group", 1, ["z", "c"], opens("false,false,true"));
  tg("zc on a closed group leaves it", 0, ["z", "c"], opens("false,true,true"));
  tg("zR opens them all", 1, ["z", "R"], opens("true,true,true"));
  tg("zM closes them all", 0, ["z", "M"], opens("false,false,false"));
  tg("za on a row that is no group says so", 0, [], (open) => {
    const r = document.querySelector('[data-sidebar-row="g0"]');
    r.removeAttribute("aria-expanded");
    V.feed("z"); V.feed("a");
    return /not a group/.test(V.said()) ? "" : "said " + JSON.stringify(V.said());
  });
  /* Archive, delete and snooze are in the row's own menu, which T3 binds no
     key to; zz and dm open it where gred would act outright. */
  tg("zz opens the row's menu", 0, [], () => {
    let opened = 0;
    const r = document.querySelector('[data-sidebar-row="g0"]');
    r.addEventListener("contextmenu", () => { opened++; });
    V.feed("z"); V.feed("z");
    return opened === 1 ? "" : "the menu opened " + opened + " times";
  });

  /* -------------------------------------------------------------- page --- */

  /* gred's agent page: the conversation is a read-only Vim buffer and the
     composer a field in it, so an escape in normal mode at rest leaves and
     the conversation reads j k gg G <C-d> <C-u>, while i a I A o write to
     the agent again. */
  const chat = () => document.querySelector(".messages-timeline-scroll");
  function tp(name, prep, steps, check) {
    ts("page: " + name, () => { chat().scrollTop = 0; prep(); }, steps, check);
  }
  /* Starting in the composer, in normal mode, having left it with Escape. */
  const left = () => () => { setup("hello", 0); V.feed("Escape"); };

  tp("Escape in normal mode leaves the composer", left(), [],
     (g, s) => (document.activeElement === el ? "still in the composer" : "")
       || (V.state.mode === "INSERT" ? "" : "mode " + V.state.mode));
  /* The view glides to where a key sends it (ui::motion GLIDE), so these
     land it at once rather than waiting for frames headless does not serve. */
  /* j and k take gred's page step, so the chat and the preview move the
     same distance; <C-e> and <C-y> are the view a line. */
  tp("j and k scroll the conversation by a step", left(), ["j"], () => {
    const at = V.scrollNow();
    if (Math.abs(at - V.step) > 1) return "j scrolled " + at + " want a step, " + V.step;
    V.feed("j"); V.feed("j");
    if (Math.abs(V.scrollNow() - 3 * V.step) > 1) return "three js left it at " + chat().scrollTop;
    V.feed("k");
    return Math.abs(V.scrollNow() - 2 * V.step) > 1 ? "k left it at " + chat().scrollTop : "";
  });
  tp("<C-e> is the view a line", left(), [["e", { ctrl: true }]], () => {
    const line = Math.round(parseFloat(getComputedStyle(chat().querySelector("[data-timeline-row-kind]")).lineHeight));
    const at = V.scrollNow();
    return Math.abs(at - line) > 1 ? "<C-e> scrolled " + at + " want a line, " + line : "";
  });
  /* A scroller set to scroll smoothly would animate even a scrollTop written
     straight to it, and the glide would give itself up on the next frame
     seeing the view somewhere else. It drives the scroll itself instead. */
  tp("a smooth scroller does not slow it down", left(), [], () => {
    const box = chat();
    box.style.scrollBehavior = "smooth";
    V.feed("j");
    const at = V.scrollNow();
    box.style.scrollBehavior = "";
    return Math.abs(at - V.step) > 1 ? "j scrolled " + at + " want " + V.step : "";
  });
  tp("a held j adds to where the view is going", left(), [], () => {
    for (let i = 0; i < 5; i++) V.feed("j", { repeat: i > 0 });
    return Math.abs(V.scrollNow() - 5 * V.step) > 1 ? "five js left it at " + chat().scrollTop : "";
  });
  tp("G goes to the end, gg to the start", left(), ["G"], () => {
    const chatEl = chat();
    if (V.scrollNow() < chatEl.scrollHeight - chatEl.clientHeight - 2) return "G stopped at " + chatEl.scrollTop;
    V.feedSeq("gg");
    return V.scrollNow() === 0 ? "" : "gg stopped at " + chatEl.scrollTop;
  });
  tp("<C-d> and <C-u> move half a screen", left(), [["d", { ctrl: true }]], () => {
    const half = Math.round(chat().clientHeight / 2);
    if (Math.abs(V.scrollNow() - half) > 2) return "scrolled " + chat().scrollTop + " want " + half;
    V.feed("u", { ctrl: true });
    return V.scrollNow() === 0 ? "" : "<C-u> left it at " + chat().scrollTop;
  });
  tp("]] walks the messages", left(), ["]]"], () => (V.scrollNow() > 0 ? "" : "did not move"));
  tp("i writes to the agent again", left(), ["i"],
     (g) => (document.activeElement === el ? "" : "not in the composer")
       || want("mode", "INSERT")(V.debug()));
  tp("A writes at the end", left(), ["A"],
     () => (V.debug().pos === 5 ? "" : "pos " + V.debug().pos)
       || (V.debug().mode === "INSERT" ? "" : "mode " + V.debug().mode));
  tp("/ searches the conversation", left(), ["/"], (g, s) => oneChord("/")(g, s));
  /* The trees still run with the conversation reading. */
  tp("<leader> still opens the tree", left(), ["<leader>sf"], (g, s) => oneChord("f")(g, s));
  /* A key the page has no use for is left alone. */
  tp("x is nobody's", left(), ["x"], none());

  /* The settings page's navigation, the other list T3 drives with the arrows:
     the same rows-plus-container shape on [data-settings-section], with no
     Left or Right and no shift check. */
  ts("list: j k move the settings navigation", () => {
       setup("abc", 0);
       el.blur();
       const box = document.createElement("div");
       box.id = "tmp-settings";
       for (const name of ["general", "models", "keys"]) {
         const r = document.createElement("button");
         r.type = "button";
         r.dataset.settingsSection = name;
         box.appendChild(r);
       }
       box.addEventListener("keydown", (e) => {
         const t = e.target;
         if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey) return;
         if (!(t instanceof HTMLElement) || !t.matches("[data-settings-section]")) return;
         const all = Array.from(box.querySelectorAll("[data-settings-section]"));
         const n = all.indexOf(t);
         const to = e.key === "ArrowDown" ? all[Math.min(n + 1, all.length - 1)]
           : e.key === "ArrowUp" ? all[Math.max(n - 1, 0)]
           : e.key === "Home" ? all[0]
           : e.key === "End" ? all[all.length - 1] : undefined;
         if (!to) return;
         e.preventDefault();
         to.focus({ preventScroll: true });
       }, true);
       document.body.appendChild(box);
       box.querySelector('[data-settings-section="general"]').focus();
     }, ["jj", "k"], (g, s) => {
       const a = document.activeElement;
       const got = a && a.dataset ? a.dataset.settingsSection : undefined;
       document.getElementById("tmp-settings").remove();
       el.focus();
       return none()(g, s) || (got === "models" ? "" : "focus " + JSON.stringify(got) + " want models");
     });

  /* Hint panel content */
  /* One line per key that continues the prefix, as gred's Hint is: the
     group's name where the keys lead to more keys, the binding's own words
     where they do not, and a key written as gred writes it. */
  ts("hint after <leader>", composer("abc", 0), ["<leader>"], (g) => {
    const h = V.showHintNow();
    if (!h || g.seq !== "<leader>") return "no hint, seq " + g.seq;
    const s = h.items.find((x) => x.key === "s"), sp = h.items.find((x) => x.key === "<Space>");
    if (!s || s.desc !== "[S]earch" || !s.group) return "s item " + JSON.stringify(s);
    if (!sp || sp.desc !== "switch agent" || sp.group) return "SPC item " + JSON.stringify(sp);
    return h.title === "<leader>" ? "" : "title " + h.title;
  });
  ts("hint after <leader>a", composer("abc", 0), ["<leader>a"], (g) => {
    const h = V.showHintNow();
    const n = h && h.items.find((x) => x.key === "n"), r = h && h.items.find((x) => x.key === "r");
    if (!n || n.desc !== "new agent" || n.none) return "n item " + JSON.stringify(n);
    if (!r || !r.none) return "r item " + JSON.stringify(r);
    return h.title === "<leader>a" ? "" : "title " + h.title;
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
    const T = V.timeoutlenMs;
    await ta("timeoutlen is 300 ms", async () => (T === 300 ? "" : "timeoutlenMs " + T));
    /* gred's resolver: a prefix that only leads on waits as long as it takes,
       with the which-key bar up. Only one that is a command of its own is on
       a clock, which here is g alone. */
    await ta("a prefix that only leads on waits", async () => {
      setup("hello", 0); V.feedSeq("<leader>s");
      await wait(T * 4);
      if (V.debug().seq !== "<leader>s") return "seq " + JSON.stringify(V.debug().seq);
      V.feed("f");
      return oneChord("f")(V.debug(), sent);
    });
    await ta("<C-w> waits too", async () => {
      setup("hello", 0); V.feed("w", { ctrl: true });
      await wait(T * 4);
      V.feed("s");
      return oneChord("s")(V.debug(), sent);
    });
    await ta("a timed-out g is still vim's g (gg)", async () => {
      setup("abc\ndef", 5); V.feed("g");
      await wait(T + 150);
      V.feed("g");
      return none(want("pos", 0))(V.debug(), sent);
    });
    await ta("the which-key bar shows the leader tree", async () => {
      setup("abc", 0); V.feedSeq("<leader>"); V.showHintNow();
      await frames();
      const p = document.querySelector(".t3vim-keys");
      if (!p || !p.classList.contains("on")) return "bar hidden";
      if (!/\[S\]earch/.test(p.textContent) || !/switch agent/.test(p.textContent)) return "bar text " + p.textContent.slice(0, 120);
      V.feed("Escape");
      await frames();
      return p.classList.contains("on") ? "bar still shown after Escape" : "";
    });
    await ta("the which-key bar works with nothing focused", async () => {
      setup("abc", 0); el.blur(); document.body.focus(); V.feed("w", { ctrl: true });
      V.showHintNow();
      await frames();
      const p = document.querySelector(".t3vim-keys");
      const ok = p && p.classList.contains("on") && /focus left/.test(p.textContent);
      V.feed("Escape");
      return ok ? "" : "bar " + (p ? p.className + " " + p.textContent.slice(0, 80) : "missing");
    });
    /* gred lays the bar out in columns of 220 filled top to bottom, docked
       above the statusline, on the chrome with one hairline along its top. */
    await ta("the which-key bar is docked and in columns", async () => {
      setup("abc", 0); V.feedSeq("<leader>"); V.showHintNow();
      await frames();
      const p = document.querySelector(".t3vim-keys");
      const grid = p && p.firstChild;
      if (!grid) return "no grid";
      const style = getComputedStyle(grid);
      if (style.gridAutoFlow !== "column") return "flow " + style.gridAutoFlow;
      const rows = style.gridTemplateRows.split(" ").length;
      const columns = Math.max(1, Math.floor((window.innerWidth - 24) / 220));
      const want = Math.ceil(V.hint().items.length / columns);
      if (rows !== want) return "rows " + rows + " want " + want;
      const box = getComputedStyle(p);
      if (box.position !== "fixed" || p.style.bottom === "") return "not docked: " + box.position + " " + p.style.bottom;
      V.feed("Escape");
      return "";
    });
    /* The statusline carries the mode and the keys held, as gred's does. */
    await ta("the statusline says the mode and the keys held", async () => {
      setup("abc", 0); V.feed("Escape");
      await frames();
      const bar = document.querySelector(".t3vim-status");
      const mode = document.querySelector(".t3vim-mode");
      if (!bar || !bar.classList.contains("on")) return "statusline hidden";
      if (mode.textContent !== "Normal" || mode.dataset.mode !== "NORMAL") return "mode " + mode.textContent;
      V.feedSeq("<leader>s");
      await frames();
      const keys = document.querySelector(".t3vim-status-keys").textContent;
      if (!/<leader>s/.test(keys)) return "keys " + JSON.stringify(keys);
      V.feed("Escape");
      V.feed("i");
      await frames();
      return mode.textContent === "Insert" ? "" : "mode after i: " + mode.textContent;
    });
    /* A key with no counterpart says so on the message line, not in the bar. */
    await ta("the message line says what a key did", async () => {
      setup("abc", 0); V.feed("Escape"); V.feedSeq("<leader>q");
      await frames();
      const msg = document.querySelector(".t3vim-msg");
      if (!msg || !msg.classList.contains("on")) return "message line hidden";
      if (!/no T3 equivalent/.test(msg.textContent)) return "message " + msg.textContent;
      const bar = document.querySelector(".t3vim-keys");
      return bar && bar.classList.contains("on") ? "the bar is up for a finished sequence" : "";
    });

    out.textContent = lines.join("\n") + "\n\nPASS " + pass + "  FAIL " + fail + "\n";
    document.title = fail === 0 ? "ALLPASS" : "FAILURES:" + fail;
  })();
})();
