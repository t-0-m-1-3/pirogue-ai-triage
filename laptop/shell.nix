# shell.nix — NixOS development/demo shell for PiRogue AI Triage
#
# Usage (with direnv — preferred):
#   cd ~/projects/pirogue-ai-triage   # direnv auto-loads this + .envrc
#
# Usage (manual):
#   nix-shell                          # enter the shell
#   nix-shell --run ./demo-stage.sh    # launch demo directly
#
# API key is loaded via .envrc from sops-nix (/run/secrets/anthropic_api_key).
# If not using direnv, export ANTHROPIC_API_KEY before entering nix-shell.

{ pkgs ? import <nixpkgs> {} }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    httpx
  ]);
in
pkgs.mkShell {
  name = "pirogue-demo";

  buildInputs = with pkgs; [
    tmux
    openssh
    jq
    curl
    pythonEnv
    bat
    ripgrep
    wireguard-tools
  ];

  shellHook = ''
    # Load API key from sops-nix if not already set (direnv handles this normally)
    if [ -z "''${ANTHROPIC_API_KEY:-}" ] && [ -r /run/secrets/anthropic_api_key ]; then
      export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic_api_key)"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  PiRogue AI Triage — Demo Shell                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║                                                  ║"
    echo "║  Commands:                                       ║"
    echo "║    ./demo-stage.sh    Launch tmux demo layout    ║"
    echo "║    ./demo-trigger.sh  Fire demo alert triggers   ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    if [ -z "''${ANTHROPIC_API_KEY:-}" ]; then
      echo "⚠  ANTHROPIC_API_KEY not set"
      echo "   If sops-nix is configured: check /run/secrets/anthropic_api_key"
      echo "   Manual fallback: export ANTHROPIC_API_KEY=sk-ant-... before nix-shell"
    else
      echo "✓  ANTHROPIC_API_KEY is set"
    fi

    if [ -f "$HOME/.ssh/id_pirogue" ]; then
      echo "✓  SSH key found: ~/.ssh/id_pirogue"
    else
      echo "⚠  SSH key not found: ~/.ssh/id_pirogue"
      echo "   Create one: ssh-keygen -t ed25519 -f ~/.ssh/id_pirogue -C pirogue-demo"
    fi

    echo ""
  '';
}
