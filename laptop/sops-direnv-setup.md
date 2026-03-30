# Setting Up sops-nix + direnv on NixOS (dndtop)

## Overview

This wires up encrypted secrets management so that `ANTHROPIC_API_KEY` (and any
future secrets) are automatically available when you `cd` into the pirogue project
directory. No manual `export`, no plaintext keys on disk.

```
sops-nix (NixOS module)
  → decrypts secrets at system activation
  → writes plaintext to /run/secrets/ (tmpfs, RAM only)

direnv + nix-direnv
  → detects .envrc when you cd into the project
  → sources the decrypted secret
  → loads the nix shell automatically
```

---

## Step 1: Generate an age key for dndtop

age is the encryption backend for sops. Each machine gets its own key.

```bash
# Create the age key directory
mkdir -p ~/.config/sops/age

# Generate a key
nix-shell -p age --run "age-keygen -o ~/.config/sops/age/keys.txt"

# Note your PUBLIC key (you'll need it for .sops.yaml)
grep "public key:" ~/.config/sops/age/keys.txt
```

Save that public key — it looks like `age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`.

---

## Step 2: Add sops-nix to your flake (or configuration)

### If you use flakes (most likely on NixOS):

In your `flake.nix` inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Add sops-nix
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ... your other inputs
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations.dndtop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        sops-nix.nixosModules.sops    # <-- add this
      ];
    };
  };
}
```

### If you use channels (no flakes):

Add to your `configuration.nix` imports:

```nix
imports = [
  "${builtins.fetchTarball "https://github.com/Mic92/sops-nix/archive/master.tar.gz"}/modules/sops"
];
```

---

## Step 3: Create and encrypt the secrets file

```bash
# Install sops if not already available
nix-shell -p sops

# Create .sops.yaml in your NixOS config directory (e.g., /etc/nixos/ or your flake root)
cat > /etc/nixos/.sops.yaml << 'EOF'
keys:
  - &dndtop age1YOUR_PUBLIC_KEY_FROM_STEP_1

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *dndtop
EOF

# Create the secrets directory
mkdir -p /etc/nixos/secrets

# Create and encrypt the secrets file
# This opens your $EDITOR — add your key in YAML format
sops /etc/nixos/secrets/pirogue.yaml
```

When your editor opens, add:

```yaml
anthropic_api_key: "sk-ant-your-actual-key-here"
```

Save and close. sops encrypts it automatically. The file on disk is encrypted —
you can safely commit it to git.

---

## Step 4: Configure sops-nix in your NixOS config

Add to your `configuration.nix` (or a dedicated `secrets.nix` that you import):

```nix
{
  # Tell sops-nix where your age key is
  sops.defaultSopsFile = ./secrets/pirogue.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.age.keyFile = "/home/tom/.config/sops/age/keys.txt";

  # Declare the secret
  sops.secrets."anthropic_api_key" = {
    # Makes it readable by your user (not just root)
    owner = "tom";
    group = "users";
    mode = "0400";
  };

  # The decrypted secret will be available at:
  #   /run/secrets/anthropic_api_key
}
```

Rebuild:

```bash
sudo nixos-rebuild switch
```

Verify:

```bash
cat /run/secrets/anthropic_api_key
# Should print: sk-ant-your-actual-key-here
```

---

## Step 5: Set up direnv + nix-direnv

Add to your `configuration.nix`:

```nix
{
  # Enable direnv system-wide
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;   # cached nix-shell evaluations
  };

  # Make sure your shell integrates with direnv
  # If you use bash (default):
  programs.bash.interactiveShellInit = ''
    eval "$(direnv hook bash)"
  '';

  # If you use zsh instead:
  # programs.zsh.interactiveShellInit = ''
  #   eval "$(direnv hook zsh)"
  # '';
}
```

Rebuild:

```bash
sudo nixos-rebuild switch
```

---

## Step 6: Create .envrc in the pirogue project

In your pirogue project directory on the laptop:

```bash
cd ~/projects/pirogue-ai-triage   # or wherever you cloned it

cat > .envrc << 'EOF'
# Load the nix shell automatically
use nix

# Load the Anthropic API key from sops-nix decrypted secret
if [ -r /run/secrets/anthropic_api_key ]; then
  export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic_api_key)"
fi
EOF

# Allow direnv to use this .envrc
direnv allow
```

---

## Step 7: Verify

```bash
# Leave and re-enter the directory
cd ~
cd ~/projects/pirogue-ai-triage

# direnv should automatically:
#   1. Load the nix shell (with tmux, jq, curl, etc.)
#   2. Export ANTHROPIC_API_KEY from the sops secret

# You should see direnv output like:
#   direnv: loading ~/projects/pirogue-ai-triage/.envrc
#   direnv: using nix
#
#   ╔══════════════════════════════════════════════════╗
#   ║  PiRogue AI Triage — Demo Shell                  ║
#   ...
#   ✓  ANTHROPIC_API_KEY is set
#   ✓  SSH key found: ~/.ssh/id_pirogue

echo $ANTHROPIC_API_KEY
# Should print your key
```

---

## How It Works Day-to-Day

- **cd into project** → direnv auto-loads shell.nix + decrypted API key
- **cd out of project** → direnv unloads everything (key not in your env anymore)
- **nixos-rebuild** → sops-nix re-decrypts to /run/secrets/ (tmpfs, never on disk)
- **reboot** → /run/secrets/ is gone (tmpfs), sops-nix re-decrypts on next boot
- **git push** → .envrc is safe to commit (no secrets in it, just a path reference)
  - Add `secrets/pirogue.yaml` to your NixOS config repo (it's encrypted)
  - Do NOT commit `.direnv/` — add it to .gitignore

---

## Adding More Secrets Later

Edit the encrypted file:

```bash
sops /etc/nixos/secrets/pirogue.yaml
```

Add new keys in the YAML, then declare them in configuration.nix:

```nix
sops.secrets."new_secret_name" = {
  owner = "tom";
  mode = "0400";
};
```

Reference in .envrc:

```bash
export NEW_SECRET="$(cat /run/secrets/new_secret_name)"
```

---

## Troubleshooting

**"direnv: error .envrc is blocked"**
Run `direnv allow` in the project directory.

**API key is empty after nixos-rebuild**
Check `ls -la /run/secrets/` — if the file doesn't exist, sops-nix failed
to decrypt. Check `journalctl -u sops-nix` for errors. Most common cause:
the age key path in `sops.age.keyFile` doesn't match where you generated it.

**nix-shell is slow to load**
That's normal the first time. nix-direnv caches the evaluation, so subsequent
loads are instant. If it's slow every time, make sure `nix-direnv.enable = true`
is set.

**"use nix" not recognized in .envrc**
nix-direnv isn't installed. Verify `programs.direnv.nix-direnv.enable = true`
is in your NixOS config and you've rebuilt.
