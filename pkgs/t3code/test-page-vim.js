/* Exercises page-vim.js in a real browser against a page with something to
   scroll, label, walk and mark. Run: ./run-tests.sh, which drives both
   pages. */
(() => {
  const V = window.__t3pagevim;
  const out = document.getElementById("out");
  const lines = [];
  let pass = 0, fail = 0;

  const doc = () => document.scrollingElement || document.documentElement;
  const reset = () => {
    V.scrollNow();                 /* land what is in flight before zeroing */
    doc().scrollTop = 0;
    doc().scrollLeft = 0;
    document.getElementById("box").scrollTop = 0;
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    V.feed("Escape");
  };

  /* name, keys (a string fed one key at a time, or an array of [key, mods]),
     check() -> problem string or "" */
  function t(name, keys, check) {
    let prob;
    reset();
    try {
      for (const k of keys) {
        if (Array.isArray(k)) V.feed(k[0], k[1]);
        else V.feed(k);
      }
      prob = check();
    } catch (err) { prob = "threw: " + err.message; }
    if (prob) { lines.push("FAIL " + name + "  " + prob); fail++; }
    else { lines.push("ok   " + name); pass++; }
  }

  const near = (got, want, slack) =>
    Math.abs(got - want) <= (slack === undefined ? 1 : slack) ? "" : got + " want " + want;

  /* ----------------------------------------------------------- scroll -- */
  /* gred's page keys: STEP 60 for j k h l, LINE 40 for <C-e> <C-y>. */
  t("j scrolls a step", "j", () => near(V.scrollNow(), V.step));
  t("3j counts", "3j", () => near(V.scrollNow(), 3 * V.step));
  t("k comes back", "jjk", () => near(V.scrollNow(), V.step));
  t("<C-e> scrolls a line", [["e", { ctrl: true }]], () => near(V.scrollNow(), V.line));
  t("<C-d> is half a screen", [["d", { ctrl: true }]],
    () => near(V.scrollNow(), Math.round(window.innerHeight / 2), 2));
  t("d is half a screen too", "d", () => near(V.scrollNow(), Math.round(window.innerHeight / 2), 2));
  t("<C-f> is a screen", [["f", { ctrl: true }]],
    () => near(V.scrollNow(), window.innerHeight - 2 * V.line, 2));
  t("G goes to the bottom", "G",
    () => near(V.scrollNow(), doc().scrollHeight - doc().clientHeight, 2));
  t("gg comes back to the top", "Ggg", () => near(V.scrollNow(), 0));
  t("50% is the middle", "50%",
    () => near(V.scrollNow(), (doc().scrollHeight - doc().clientHeight) / 2, 2));
  t("0 is the far left", "0", () => (V.state.count === "" ? "" : "count " + V.state.count));

  /* An area that scrolls on its own, under the point gred scrolls at. */
  t("the area under the point scrolls", [], () => {
    const box = document.getElementById("box");
    box.scrollIntoView({ block: "center" });
    const was = doc().scrollTop;
    const r = box.getBoundingClientRect();
    /* Only a trusted press sets the point, so the rig says where it was. */
    V.pointAt(r.left + 10, r.top + 10);
    V.feed("j");
    const prob = near(V.scrollNow(), V.step);
    V.pointAt();
    /* and the page itself did not move */
    return prob || (doc().scrollTop === was ? "" : "the page moved too: " + doc().scrollTop);
  });

  /* ------------------------------------------------------------ walks -- */
  t("]] goes to the next heading", "]]", () => {
    V.scrollNow();
    V.pointAt();
    const h = document.getElementById("h-one").getBoundingClientRect().top;
    return Math.abs(h - 8) < 3 ? "" : "heading at " + h;
  });
  t("[[ comes back", [], () => {
    V.feedKeys("]]"); V.scrollNow();
    V.feedKeys("]]"); V.scrollNow();
    V.feedKeys("[["); V.scrollNow();
    const h = document.getElementById("h-one").getBoundingClientRect().top;
    return Math.abs(h - 8) < 3 ? "" : "heading at " + h;
  });
  t("]c goes to the code block", "]c", () => {
    V.scrollNow();
    const c = document.getElementById("code-one").getBoundingClientRect().top;
    return Math.abs(c - 8) < 3 ? "" : "code at " + c;
  });
  t("]t goes to the table", "]t", () => {
    V.scrollNow();
    const c = document.getElementById("table-one").getBoundingClientRect().top;
    return Math.abs(c - 8) < 3 ? "" : "table at " + c;
  });

  /* ------------------------------------------------------------ hints -- */
  t("f labels what is in view", "f", () => {
    if (!V.state.hints) return "no hints";
    const keys = V.hints();
    if (!keys.length) return "no labels";
    if (keys.some((k) => !/^[hjklasdfgyuiopqwertnmzxcvb]+$/.test(k))) return "labels " + keys.join(",");
    if (new Set(keys).size !== keys.length) return "a label twice";
    V.feed("Escape");
    return V.state.hints ? "Escape left them up" : "";
  });
  t("a label presses what it is on", "f", () => {
    let clicked = false;
    const btn = document.getElementById("btn");
    btn.addEventListener("click", () => { clicked = true; }, { once: true });
    const keys = V.hints();
    const at = V.hints().length;
    /* find the label on the button: it is the third thing in view */
    const items = keys.slice();
    let label = null;
    for (let i = 0; i < items.length; i++) {
      /* the hints are in document order, and the button is after two links */
      if (i === 2) { label = items[i]; break; }
    }
    if (!label) return "no label to press, " + at + " labels";
    for (const ch of label) V.feed(ch);
    return clicked ? "" : "the button was not pressed by " + label;
  });
  t("a label narrows on the first key", "f", () => {
    const two = V.hints().find((k) => k.length === 2);
    if (!two) return "";                     /* few enough things for one key each */
    V.feed(two[0]);
    return V.state.hints ? "" : "narrowing closed the labels";
  });

  /* ------------------------------------------------------------ modes -- */
  t("i gives every key to the page", "ij", () => {
    if (V.state.mode !== "PAGEKEYS") return "mode " + V.state.mode;
    return doc().scrollTop === 0 ? "" : "j still scrolled: " + doc().scrollTop;
  });
  t("<S-Esc> comes back", ["i", ["Escape", { shift: true }], "j"], () => {
    if (V.state.mode !== "NORMAL") return "mode " + V.state.mode;
    return near(V.scrollNow(), V.step);
  });
  t("a field keeps its keys", [], () => {
    document.getElementById("field").focus();
    V.feed("j");
    if (doc().scrollTop !== 0) return "j scrolled with a field focused";
    V.feed("Escape");
    return document.activeElement === document.getElementById("field") ? "Escape stayed in the field" : "";
  });
  t("<C-v> passes the next key", [["v", { ctrl: true }], "j"],
    () => (doc().scrollTop === 0 ? "" : "j was taken after <C-v>"));

  /* ------------------------------------------------------------ marks -- */
  t("m and ' go back to the place", "Gma", () => {
    V.scrollNow();
    V.feedKeys("gg");
    V.scrollNow();
    V.feedKeys("'a");
    const most = doc().scrollHeight - doc().clientHeight;
    return near(V.scrollNow(), most, 2);
  });

  /* ------------------------------------------------- what the app runs -- */
  /* The chords T3 already binds for its preview, sent back through the
     preload's own channel. Nothing here names a T3 command. */
  t("+ - = ask the app to zoom", "+-=", () => {
    const want = ["zoomIn", "zoomOut", "zoomReset"];
    const got = V.sent.slice(-3);
    return got.join(",") === want.join(",") ? "" : "sent " + got.join(",");
  });
  t("o asks for the address bar", "o",
    () => (V.sent[V.sent.length - 1] === "address" ? "" : "sent " + V.sent[V.sent.length - 1]));
  t("/ asks for the find bar", "/",
    () => (V.sent[V.sent.length - 1] === "find" ? "" : "sent " + V.sent[V.sent.length - 1]));

  /* ------------------------------------------------------------- yank -- */
  t("yy yanks the address", "yy", () => (V.state.pending === "" ? "" : "pending " + V.state.pending));

  /* --------------------------------------------------- what is nobody's -- */
  t("a key the table has no use for passes", "z",
    () => (doc().scrollTop === 0 && V.state.pending === "" ? "" : "z was taken"));

  out.textContent = lines.join("\n") + "\n\nPASS " + pass + "  FAIL " + fail + "\n";
  document.title = fail === 0 ? "ALLPASS" : "FAILURES:" + fail;
})();
