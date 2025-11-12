# AI Agent Instructions

## Design Principles

Future AI agents working on this NixOS/home-manager configuration should adhere to the following design principles:

### Modular Structure
- Use separate `.nix` files for different functionalities (e.g., `ssh.nix`, `firefox.nix`)
- Group related configurations together in dedicated modules
- Import modules in parent files (e.g., `term/default.nix` imports `./ssh.nix`)

### Options and Conditionals
- Define `options` for enable flags (e.g., `options.ssh.enable = lib.mkEnableOption "Enable SSH";`)
- Use `lib.mkIf config.<option>.enable` to conditionally apply configurations
- Set defaults with `lib.mkDefault true` in parent modules to enable by default

### Consistency with Existing Patterns
- Follow the pattern seen in `desktop/apps/` where individual apps have their own files with `lib.mkIf config.programs.<program>.enable`
- Use `programs.<program>.enable = lib.mkDefault true` in aggregating modules
- Maintain separation between program-specific configs and broader system settings

### Code Organization
- Keep configurations clean and readable
- Use comments to explain non-obvious configurations
- Avoid duplication by leveraging shared options and imports

### Security and Best Practices
- Never introduce code that exposes secrets or logs sensitive information
- Follow NixOS and home-manager best practices
- Ensure configurations are idempotent and reversible

### Commit Practices
- Make atomic commits with clear, concise messages
- Test configurations with `nixtest` before committing
- Keep the git history clean and meaningful

This ensures the configuration remains maintainable, modular, and follows established patterns.