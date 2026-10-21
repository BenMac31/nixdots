{ config, lib, inputs, ... }:
{
  imports = [ inputs.graphide-tools.homeManagerModules.browser ];

  config = lib.mkIf config.programs.librewolf.enable {
    programs.graphide-browser = {
      enable = true;
      browser = "librewolf";
      darkSites = false;
      tridactyl.extraConfig = /*vim*/ ''
        " Comment toggler for Reddit, Hacker News and Lobste.rs
        bind ;c hint -Jc [class*="expand"],[class*="togg"],[class="comment_folder"]

        bind x composite tabprev; tabclose #
        " Make gu take you back to subreddit from comments
        bindurl reddit.com gu urlparent 4

        " Only hint search results on Google and DDG
        bindurl www.google.com f hint -Jc #search a
        bindurl www.google.com F hint -Jbc #search a

        " Handy multiwindow/multitasking binds
        bind gd tabdetach
        bind gD composite tabduplicate; tabdetach

        " Binds for new reader mode
        bind gr reader
        bind gR reader --tab

        " set editorcmd to foot, or use the defaults on other platforms
        js tri.browserBg.runtime.getPlatformInfo().then(os=>{const editorcmd = os.os=="linux" ? "foot nvim" : "auto"; tri.config.set("editorcmd", editorcmd)})

        set hintdelay 100
        xamo_quiet

        jsb browser.webRequest.onHeadersReceived.addListener(tri.request.clobberCSP,{urls:["<all_urls>"],types:["main_frame"]},["blocking","responseHeaders"])

        command translate js let googleTranslateCallback = document.createElement('script'); googleTranslateCallback.innerHTML = "function googleTranslateElementInit(){ new google.translate.TranslateElement(); }"; document.body.insertBefore(googleTranslateCallback, document.body.firstChild); let googleTranslateScript = document.createElement('script'); googleTranslateScript.charset="UTF-8"; googleTranslateScript.src = "https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit&tl=&sl=&hl="; document.body.insertBefore(googleTranslateScript, document.body.firstChild);

        " quickly get ext
        command nixext composite get_current_url | ! nixffext

        " autocmd DocStart ^http(s?)://www.reddit.com js tri.excmds.urlmodify("-t", "www", "old")
        set smoothscroll true
        bind J tabnext
        bind K tabprev
        command toggleverttab jsb (async () => { let current = tri.config.get('sidebarToggleState') || false; let newval = !current; await tri.excmds.setpref('sidebar.verticalTabs', newval); tri.config.set('sidebarToggleState', newval); })()
        bind gb toggleverttab

        "Redirects
        " autocmd DocStart ^http(s?)://youtube.com js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
        " autocmd DocStart ^http(s?):// js tri.excmds.urlmodify("-t", "youtube.com", "inv.nadeko.net")
      '';
    };
  };
}
