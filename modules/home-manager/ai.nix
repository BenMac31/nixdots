{lib, config, inputs, pkgs, ...}:
let
aichat = "${pkgs.aichat}/bin/aichat";
notify-send = "${pkgs.libnotify}/bin/notify-send";
wl-paste = "${pkgs.wl-clipboard}/bin/wl-paste";
touch = "${pkgs.coreutils}/bin/touch";
sleep = "${pkgs.coreutils}/bin/sleep";
head = "${pkgs.coreutils}/bin/head";
tail = "${pkgs.coreutils}/bin/tail";
wc = "${pkgs.coreutils}/bin/wc";
cat = "${pkgs.coreutils}/bin/cat";
rm = "${pkgs.coreutils}/bin/rm";
in
{
  home.packages = [
    pkgs.aichat
    (pkgs.master.unfree.ollama.override {
     acceleration = "cuda";
     })
    (pkgs.writeShellScriptBin "aiclip" ''
     ${touch} /tmp/aiclip.lock
     (aichat --role test <<< "$(${wl-paste})" > /tmp/aiclip.out && ${sleep} 1 && ${rm} /tmp/aiclip.lock) &
     notifID=$(${notify-send} -p "ANSWER" "EXPLANATION" -t "10000")
     outOld="ANSWER\nEXPLANATION"
     while [ -e /tmp/aiclip.lock ]
     do
     out="""$(${cat} /tmp/aiclip.out)
     ..."""
     if [ "$out" != "$outOld" ]
     then
     ${notify-send} "--replace-id=$notifID" -t "10000" "$(echo "$out" | ${head} -n 1)" "$(echo "$out" | ${tail} -n +2)"
     outOld="$out"
     fi
     ${sleep} 0.2
     done
     ${cat} /tmp/aiclip.out
     ${notify-send} "--replace-id=$notifID" -t "$(($(${wc} -w < /tmp/aiclip.out)*300))" "$(${head} -n 1 /tmp/aiclip.out)" "$(${tail} -n +2 /tmp/aiclip.out)"
     ${rm} /tmp/aiclip.out
     '')
  ];
}
