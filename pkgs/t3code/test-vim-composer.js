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

  out.textContent = lines.join("\n") + "\n\nPASS " + pass + "  FAIL " + fail + "\n";
  document.title = fail === 0 ? "ALLPASS" : "FAILURES:" + fail;
})();
