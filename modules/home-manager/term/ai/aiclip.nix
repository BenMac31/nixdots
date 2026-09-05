{ lib, config, pkgs, ... }:
{
  options = {
    ai.aiclip = {
      enable = lib.mkEnableOption "Enable aiclip, the clipboard-to-aichat notification popup";
    };
  };
  config = lib.mkIf config.ai.aiclip.enable {
    home.packages = [
      (pkgs.writeShellApplication
        {
          name = "aiclip";
          runtimeInputs = [ pkgs.aichat pkgs.libnotify pkgs.wl-clipboard pkgs.coreutils pkgs.expect ];
          text = ''
                    lockfile="/tmp/aiclip.lock.$$"
                    outfile="/tmp/aiclip.out.$$"
                    sessionfile="$XDG_CONFIG_HOME/aichat/sessions/test-$$"
                    touch $lockfile
                    (wl-paste | aichat --role test -s "test-$$" --save-session --empty-session > $outfile && rm $lockfile) || notify-send "ERR, aichat failed." || rm $outfile $lockfile "$sessionfile" || exit &
                    notifID=$(notify-send -p "ANSWER" "EXPLANATION" -t "10000")
                    outOld="""$(cat $outfile)"""
                    while [ -e $lockfile ]
                    do
                    out="""$(cat $outfile)"""
                    if [ "$out" != "$outOld" ]
                    then
                      notify-send "--replace-id=$notifID" \
                      -t "10000" \
                      "$(echo "$out" | sed -n 's/ANSWER://gp')..." "$(echo "$out" | sed -n 's/EXPLANATION://gp')..." 2> /dev/null
                    outOld="$out"
                    fi
                    sleep 0.2
                    done
                    cat $outfile
                    t="$(printf "%05d" $(($(grep -e 'ANSWER:' -e 'EXPLANATION:' "$outfile" | wc -w) * 300 + 1011)))"
                    grep -e 'ANSWER:' "$outfile" || notify-send "ERR" "$(cat $outfile)" &&\
                    [ "$(timeout "''${t:0:2}.''${t:2}" notify-send  \
                      --action="default=openChatWindow" \
                      --replace-id="$notifID" \
                      -t "''${t##+(0)}" \
                      "$(sed -n 's/ANSWER://gp' $outfile)" \
                      "$(sed -n 's/EXPLANATION://gp' $outfile)")" = "default" \
                    ] &&\
                    $TERMINAL expect -c "
            spawn aichat -s test-$$"'
            expect "Welcome to aichat"
            send ".info session\r"
            interact
            '
                  rm $outfile # "$sessionfile"
                    echo "$sessionfile"
          '';
        })
    ];
  };
}
