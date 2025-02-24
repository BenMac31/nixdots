{ lib, config, inputs, pkgs, ... }:
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
  options = {
    ai = {
      enable = lib.mkEnableOption "Enable AI";
      localrun.enable = lib.mkEnableOption "Enable local AI";
    };
  };
  config = lib.mkIf config.ai.enable {
    home.packages = [
      pkgs.aichat
      (pkgs.writeShellScriptBin "aiclip" ''
        lockfile="/tmp/aiclip.lock.$$"
        outfile="/tmp/aiclip.out.$$"
        ${touch} $lockfile
        (echo "$(${wl-paste})" | aichat --role test > $outfile && ${sleep} 1 && ${rm} $lockfile) &
        notifID=$(${notify-send} -p "ANSWER" "EXPLANATION" -t "10000") outOld="ANSWER\nEXPLANATION"
        while [ -e $lockfile ]
        do
        out="""$(${cat} $outfile)..."""
        if [ "$out" != "$outOld" ]
        then
          ${notify-send} "--replace-id=$notifID" -t "10000" "$(echo "$out" | sed -n 's/ANSWER://gp')" "$(echo "$out" | sed -n 's/EXPLANATION://gp')" 2> /dev/null
        outOld="$out"
        fi
        ${sleep} 0.2
        done
        ${cat} $outfile
        ${notify-send} "--replace-id=$notifID" -t "$(($(grep -e 'ANSWER:' -e 'EXPLANATION:' "$outfile" | ${wc} -w) * 300))" "$(sed -n 's/ANSWER://gp' $outfile)" "$(sed -n 's/EXPLANATION://gp' $outfile)" || notify-send "ERR" "$(${cat} $outfile)"
        ${rm} $outfile
      '')
      (lib.mkIf config.ai.localrun.enable pkgs.unfree.openai-whisper)
      (lib.mkIf config.ai.localrun.enable pkgs.ollama)
    ];
    xdg.configFile."aichat/config.yaml".text = /*yaml */ ''
      function_calling: true
      model: g4f
      clients:
      - type: openai-compatible
        name: g4f
        api_base: http://localhost:1337/v1
        api_key: xxx
        models:
        - name: gpt-4o
          max_input_tokens: null
          supports_function_calling: true
        - name: gpt-4o-mini
          max_input_tokens: null
          supports_function_calling: true
          supports_reasoning: true
    '';
    xdg.configFile."aichat/roles/test.md".text = /*md*/ ''
      ---
      model: g4f:gpt-4o-mini
      temperature: 0
      top_p: 0

      ---
      Your job is to answer the question in the following prompt. First write out your in depth thought process. Once you come up with an answer format it as follows:
      ANSWER: <answer>
      EXPLANATION: <explanation>
      Your answer should be a single word or phrase. If there are multiple answers, separate them with commas.
      Your explanation should be as brief as possible (ideally less than 2 sentences.)
      The answer and explanation should be on two separate lines. The entirety of the answer is specified should be on the first line. The entire explanation should be on the second.
    '';
  };
}
