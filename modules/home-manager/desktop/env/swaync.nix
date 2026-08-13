{ config, ... }:

{
  services.swaync = {
    enable = true;

    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      "control-center-layer" = "top";
      "layer-shell" = true;
      cssPriority = "user";
      "control-center-margin-top" = 16;
      "control-center-margin-bottom" = 16;
      "control-center-margin-right" = 16;
      "control-center-margin-left" = 0;
      "notification-icon-size" = 20;
      "notification-body-image-height" = 100;
      "notification-body-image-width" = 200;
      timeout = 5;
      "timeout-low" = 5;
      "timeout-critical" = 0;
      "fit-to-screen" = false;
      "control-center-width" = 480;
      "notification-window-width" = 400;
      "keyboard-shortcuts" = true;
      "image-visibility" = "when-available";
      "transition-time" = 200;
      "hide-on-clear" = false;
      "hide-on-action" = true;
      "action-icons" = false;
      scripts = {};
    };

    style = with config.colorScheme.palette; ''
      * {
        font-family: "JetBrainsMono Nerd Font Mono";
        font-size: 12pt;
        transition: 200ms ease;
      }

      /* ── Notification Popups ─────────────────────────────────── */

      .notification-row {
        outline: none;
        margin: 8px 8px 0;
      }

      .notification-row:last-child {
        margin-bottom: 8px;
      }

      .notification {
        border-radius: 20px;
        border: 2px solid #${base0F};
        background: alpha(#${base00}, 0.92);
        padding: 0;
      }

      .notification-default-action {
        margin: 0;
        padding: 12px;
        border-radius: 20px;
        color: #${base05};
        background: transparent;
      }

      .notification-default-action:hover {
        background: alpha(#${base02}, 0.6);
      }

      .notification-default-action:not(:only-child) {
        border-radius: 20px 20px 0 0;
      }

      .notification-content image {
        border-radius: 12px;
        margin-right: 8px;
      }

      .summary {
        font-weight: bold;
        color: #${base06};
      }

      .body {
        color: #${base05};
      }

      .app-name,
      .time {
        color: #${base03};
      }

      .close-button {
        border-radius: 50%;
        background: transparent;
        color: #${base04};
        border: none;
        padding: 4px;
        min-width: 24px;
        min-height: 24px;
      }

      .close-button:hover {
        background: #${base08};
        color: #${base00};
      }

      /* Urgency accents */
      .urgency-low    .notification { border-color: #${base0C}; }
      .urgency-normal .notification { border-color: #${base0D}; }
      .urgency-critical .notification {
        border-color: #${base08};
        background: alpha(#${base00}, 0.97);
      }

      .notification-action {
        border: none;
        border-top: 1px solid alpha(#${base03}, 0.4);
        border-radius: 0;
        background: transparent;
        color: #${base0D};
        padding: 8px 12px;
      }

      .notification-action:last-child {
        border-radius: 0 0 18px 18px;
      }

      .notification-action:hover {
        background: alpha(#${base02}, 0.6);
        color: #${base06};
      }

      /* ── Control Centre (panel) ──────────────────────────────── */

      notificationwindow,
      blankwindow,
      .blank-window {
        background: transparent;
        box-shadow: none;
      }

      .control-center {
        background: alpha(#${base00}, 0.92);
        border: 2px solid #${base0F};
        border-radius: 20px;
        padding: 15px;
        min-width: 480px;
      }

      .control-center-list {
        background: transparent;
      }

      .control-center-dnd {
        background: #${base01};
        border-radius: 12px;
        padding: 4px;
        margin-bottom: 10px;
      }

      .control-center-dnd slider {
        background: #${base0B};
        border-radius: 12px;
        min-width: 40px;
      }

      .control-center-dnd:checked {
        background: alpha(#${base08}, 0.15);
      }

      .control-center-dnd:checked slider {
        background: #${base08};
      }

      .control-center-clear-all {
        background: #${base01};
        border: 2px solid #${base0F};
        border-radius: 12px;
        color: #${base05};
        padding: 8px 16px;
        margin-top: 10px;
      }

      .control-center-clear-all:hover {
        background: #${base02};
        color: #${base06};
      }

      .control-center .notification-row {
        margin: 0 0 8px;
      }

      .control-center .notification-row:last-child {
        margin-bottom: 0;
      }
    '';
  };
}
