{pkgs, inputs, config, ...}:
{
   home.file.wallpapers = {
     source = inputs.gruvbox-wallpapers;
     target = ".local/share/wallpapers";
   };
   home.file.".config/goodwps".text = ''
anime/anime_skull.png
anime/classroom.jpg
anime/5m5kLI9.png
irl/aaron-burden-X3Um-nwpuWs.jpg
irl/anna-scarfiello-Pxf5syDVuxQ.jpg
irl/berries.jpg
irl/board.jpg
irl/bulbs.jpg
irl/camera.jpg
irl/clay-banks-Jya99orvzSE.jpg
irl/coffee-cup.jpg
irl/coffee-green.jpg
irl/comfy-room.jpg
irl/davide-ragusa-4jcFu1byopQ.jpg
irl/Excl_Autumn_Leaf.jpg
irl/felix-bacher--jEEnRx38wo.jpg
irl/ganapathy-kumar-JxBcs2O6-C0.jpg
irl/house.jpg
irl/houseonthesideofalake.jpg
irl/jake-weirick-EsvpmQ4zp5Y.jpg
irl/johannes-plenio-RwHv7LgeC7s.jpg
irl/joshua-sortino-Rnqa6jOpnHw.jpg
irl/hannu-keski-hakuni-vgxIfXwsUAE.jpg
irl/kristian-seedorff-BvUicqkaZZ0.jpg
irl/lantern.jpg
irl/lukasz-szmigiel-ps2daRcXYes.jpg
irl/traf-ukTd6UiQbLQ.jpg
minimalistic/finalizer.png
minimalistic/firefox.png
minimalistic/gnu.jpg
minimalistic/gruvbox_astro.jpg
minimalistic/gruvbox_minimal_space.png
minimalistic/gruvbox-nix.png
minimalistic/gruvbox-rainbow-nix.png
minimalistic/gruvbox_spac.jpg
minimalistic/gruv-commit.png
minimalistic/gruv.jpg
minimalistic/gruv-portal-cake.png
minimalistic/gruv-samurai-cyberpunk2077.png
minimalistic/gruv-understand.png
minimalistic/haz-mat.png
minimalistic/PJbX0MG.png
minimalistic/solar-system-minimal.png
minimalistic/sve.png
minimalistic/tux.png
mix/gruv-kanji.png
mix/abstract-darkhole.png
mix/among-us.jpg
mix/free.jpg
mix/greek.jpg
mix/gruvb99810.png
mix/gruvy.jpg
mix/gruvy-night.jpg
mix/night_moon.png
mix/satellite.jpg
mix/skull.jpg
mix/titlwinzbst81.jpg
mix/xavier-cuenca-w4-3.jpg
pixelart/gruvbox_image40.png
pixelart/gruvbox-pacman-full.png
'';
   services.hyprpaper = {
     enable = true;
     settings = {
       # ipc = "off";
       preload = [ "~/.local/share/wallpapers/wallpapers/irl/houseonthesideofalake.jpg" ];
       wallpaper = [
         "eDP-1,~/.local/share/wallpapers/wallpapers/irl/houseonthesideofalake.jpg"
	 ];
     };
   };
   home.packages = [
    (pkgs.writeShellScriptBin "swapwallpaper" ''
     hyprctl hyprpaper unload all
     paper="~/.local/share/wallpapers/wallpapers/$(shuf -n 1 ~/.config/goodwps)"
     hyprctl hyprpaper preload "$paper"
     hyprctl monitors -j | jq -r '.[].name' | xargs -I '{}' hyprctl hyprpaper wallpaper "{},$paper"
     '')
     ];

}
