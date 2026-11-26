{ config, lib, pkgs, inputs, ... }:
let
  shellSource = "${inputs.graphide-tools}/nix/home-manager/quickshell/shell";
  sidebarQml = builtins.replaceStrings
      [
        ''readonly property bool left: style["side"] === "left"''
        ''readonly property int baseWidth: widthOf(style["width"], CustomerState.share)''
        "exclusiveZone: narrowWidth"
        "WlrLayershell.layer: WlrLayer.Top"
        "    Rectangle {\n        visible: panel.style[\"edge\"] === \"line\"\n        anchors { top: parent.top; bottom: parent.bottom }\n        x: panel.left ? parent.width - width : 0\n        width: 1\n        color: panel.style[\"color.edge\"]\n    }"
      ]
      [
        ''readonly property bool left: PlateState.layout.todo.edge === "left"''
        ''readonly property int baseWidth: PlateState.layout.todo.inset.w
    margins {
        top: PlateState.layout.gutter
        bottom: PlateState.layout.gutter
        left: panel.left ? PlateState.layout.todo.margin + PlateState.layout.gutter : 0
        right: panel.left ? 0 : PlateState.layout.todo.margin + PlateState.layout.gutter
    }''
        "exclusiveZone: 0"
        "WlrLayershell.layer: WlrLayer.Bottom"
        "    NeatLine {\n        anchors.fill: parent\n    }"
      ]
      (builtins.readFile "${shellSource}/Sidebar.qml");
  shellQml = builtins.replaceStrings
      [
        "Bar { screen: modelData }"
        "visible: monitor.showCompany\n                }\n                // The customer board"
      ]
      [
        "Bar { screen: modelData }\n                PomodoroOverlay { screen: modelData }"
        "visible: monitor.showCompany && !SidebarState.enabled\n                }\n                // The customer board"
      ]
      (builtins.readFile "${shellSource}/shell.qml");

in
{
  imports = [ inputs.graphide-tools.homeManagerModules.quickshell ];
  config = lib.mkIf config.programs.graphide-shell.enable {
    programs.graphide-shell = {
      # Detailed logs otherwise grow without bound in the shared runtime tmpfs.
      package = pkgs.quickshell.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./quickshell-log-limit.patch ];
      });
      widgetMonitor = "eDP-1";
      terminalPackage = pkgs.kitty;
      pomodoro = pkgs.waybar-pomodoro;
      rbwPinentry = true;
      todoCommand = [ "nvim" "${config.home.homeDirectory}/Projects/graphide/docs/TODO.md" ];
      commitsRepo = "${config.home.homeDirectory}/Projects/graphide/graphide";
      hyprland = { layerRules = true; decoration = true; };
      # No panel opens from pointer position, by choice. Keep it that way.
      hoverReveal = false;
      launcherSideCards = false;
      sidebar = {
        enable = true;
        dashboard.enable = true;
      };
      # The to-do column in the shell's dark palette, not on paper.
      todoColumn.theme = "dark";
      # The panel's mode, so the plates are drawn at its own resolution.
      layout = { width = 2880; height = 1800; scale = 1.6; };
      plates = {
        enable = true;
        place = { name = "San Francisco"; latitude = 37.7749; longitude = -122.4194; };
      };
      # Held on XiaServer, so Dan can add to the list too: `remind ben "..."`.
      serverReminders = {
        person = "ben";
        addTo = [ "ben" "dan" ];
      };
    };
    # Keep the dashboard in the desktop's old TODO slot, behind normal windows.
    xdg.configFile."quickshell/graphide".source = lib.mkForce
      (pkgs.runCommand "graphide-desktop-widgets" { nativeBuildInputs = [ pkgs.patch ]; } ''
        cp -R ${shellSource} $out
        chmod -R u+w $out
        patch -d $out -p1 < ${./quickshell-spaces-grid.patch}
        patch -d $out -p1 < ${./quickshell-pomodoro.patch}
        cp ${./pomodoro/PomodoroState.qml} $out/PomodoroState.qml
        cp ${./pomodoro/PomodoroPanel.qml} $out/PomodoroPanel.qml
        cp ${./pomodoro/pomodoro.py} $out/pomodoro.py
        cp ${./spacesheep-mark.svg} $out/spacesheep-mark.svg
        rm $out/Sidebar.qml $out/shell.qml
        cp ${pkgs.writeText "Sidebar.qml" sidebarQml} $out/Sidebar.qml
        cp ${pkgs.writeText "shell.qml" shellQml} $out/shell.qml
      '');
    # Bridge must keep running after `connect.py proton` pairs it, or IMAP sync
    # dies the moment that CLI session exits.
    services.protonmail-bridge.enable = true;
  };
}
