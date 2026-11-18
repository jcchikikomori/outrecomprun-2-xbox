#!/usr/bin/env bash
# Register this machine as the self-hosted GitHub Actions runner that builds the game.
#
# The game build needs assets/default.xbe, so it can only run on a machine that has the user's
# own copy of it. This script registers the current machine with the repository, installs it as
# a user service and starts it. See docs/ci.md section 6.
#
#   scripts/ci/setup-runner.sh                     register, install the service, start it
#   scripts/ci/setup-runner.sh --no-service        register and start it in the foreground only
#   scripts/ci/setup-runner.sh --remove            unregister the runner from the repository
#
# Requirements:
#   * gh, authenticated for the repository (gh auth status)
#   * a repository with Actions enabled
#   * permission to write ~/.config/systemd/user (a user service, no root needed)
#
# Environment:
#   REPO=owner/name         repository that owns the runner (default: jcchikikomori/outrecomprun-2-xbox)
#   RUNNER_DIR=path         where the runner lives (default: ~/.actions-runner)
#   RUNNER_NAME=name        the name shown in the repository (default: steamdeck-outrun2)
#   RUNNER_LABELS=labels    extra labels (default: outrun2-recomp)
set -euo pipefail

REPO=${REPO:-jcchikikomori/outrecomprun-2-xbox}
RUNNER_DIR=${RUNNER_DIR:-$HOME/.actions-runner}
RUNNER_NAME=${RUNNER_NAME:-steamdeck-outrun2}
RUNNER_LABELS=${RUNNER_LABELS:-outrun2-recomp}
UNIT=actions-runner.service

log() { printf '[setup-runner] %s\n' "$*"; }
die() { printf '[setup-runner] %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated: run 'gh auth login'"

if [ "${1:-}" = "--remove" ]; then
    [ -x "$RUNNER_DIR/config.sh" ] || die "no runner at $RUNNER_DIR"
    log "unregistering the runner"
    ( cd "$RUNNER_DIR" && ./config.sh remove --unattended ) || true
    systemctl --user disable --now "$UNIT" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$UNIT"
    log "removed; the runner directory $RUNNER_DIR is kept"
    exit 0
fi

if [ ! -x "$RUNNER_DIR/run.sh" ]; then
    log "downloading the runner package"
    mkdir -p "$RUNNER_DIR"
    asset=$(gh api repos/actions/runner/releases/latest \
        --jq '.assets[] | select(.name | test("^actions-runner-linux-x64-[0-9.]+\\.tar\\.gz$")) | .name' | head -1)
    [ -n "$asset" ] || die "no linux runner asset found"
    log "asset: $asset"
    curl -fsSL -o "$RUNNER_DIR/runner.tar.gz" "https://github.com/actions/runner/releases/latest/download/$asset"
    tar -xzf "$RUNNER_DIR/runner.tar.gz" -C "$RUNNER_DIR"
    rm -f "$RUNNER_DIR/runner.tar.gz"
    chmod +x "$RUNNER_DIR"/*.sh "$RUNNER_DIR/bin/Runner.Listener" 2>/dev/null || true
fi

if [ ! -f "$RUNNER_DIR/.runner" ]; then
    log "requesting a registration token for $REPO"
    token=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)
    [ -n "$token" ] || die "the registration token request failed"
    log "configuring the runner as '$RUNNER_NAME' (labels: $RUNNER_LABELS)"
    ( cd "$RUNNER_DIR" && ./config.sh --unattended --disableupdate \
        --url "https://github.com/$REPO" \
        --token "$token" \
        --name "$RUNNER_NAME" \
        --labels "$RUNNER_LABELS" \
        --work "_work" \
        --replace ) || die "config.sh failed"
fi

if [ "${1:-}" = "--no-service" ]; then
    log "starting the runner in the foreground (Ctrl-C to stop)"
    exec "$RUNNER_DIR/run.sh"
fi

log "installing the user service $UNIT"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/$UNIT" <<UNIT
[Unit]
Description=GitHub Actions self-hosted runner (OutRun 2 build)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Restart=on-failure
RestartSec=30
Environment=HOME=$HOME

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT"
sleep 3
systemctl --user --no-pager --lines=0 status "$UNIT" | head -6 || true

log "done. Check the runner in the repository: Settings -> Actions -> Runners"
