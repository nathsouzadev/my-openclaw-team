#!/usr/bin/env bash
set -euo pipefail

: "${GATEWAY_PORT:=5010}"
: "${OPENCLAW_HOME:=/data/.openclaw}"

: "${AGENT_PM_ID:=pm_nanisca}"
: "${AGENT_PM_NAME:=Nanisca}"
: "${AGENT_PM_ACCOUNT_ID:=nanisca}"

mkdir -p "${OPENCLAW_HOME}" "${OPENCLAW_HOME}/workspace"

CONFIG_PATH="${OPENCLAW_HOME}/config.json"

export GATEWAY_PORT OPENCLAW_HOME SLACK_CHANNEL_ID
export OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
export OPENCLAW_CONFIG_PATH="${CONFIG_PATH}"

while IFS='=' read -r name _; do
  case "$name" in
    AGENT_*) export "$name" ;;
  esac
done < <(env)

for var in $(compgen -v | grep -E '^AGENT_[A-Z0-9_]+_ID$'); do
  agent_id="${!var}"
  [ -n "$agent_id" ] && mkdir -p "${OPENCLAW_HOME}/workspaces/${agent_id}"
done

if [ -d /opt/superpowers/skills ]; then
  for var in $(compgen -v | grep -E '^AGENT_[A-Z0-9_]+_ID$'); do
    agent_id="${!var}"
    [ -z "$agent_id" ] && continue
    skills_dir="${OPENCLAW_HOME}/workspaces/${agent_id}/skills"
    mkdir -p "$skills_dir"
    ln -sfn /opt/superpowers/skills "${skills_dir}/superpowers"
  done
fi

if [ ! -f "${OPENCLAW_HOME}/.onboarded" ]; then
  if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    openclaw onboard \
      --non-interactive \
      --accept-risk \
      --auth-choice openrouter-api-key \
      --openrouter-api-key "${OPENROUTER_API_KEY}" \
      --skip-channels --skip-daemon --skip-ui --skip-search --skip-skills --skip-health \
      || true
  elif [ -n "${GEMINI_API_KEY:-}" ]; then
    openclaw onboard \
      --non-interactive \
      --accept-risk \
      --auth-choice gemini-api-key \
      --gemini-api-key "${GEMINI_API_KEY}" \
      --skip-channels --skip-daemon --skip-ui --skip-search --skip-skills --skip-health \
      || true
  else
    openclaw onboard \
      --non-interactive \
      --accept-risk \
      --auth-choice skip \
      --skip-channels --skip-daemon --skip-ui --skip-search --skip-skills --skip-health \
      || true
  fi
  touch "${OPENCLAW_HOME}/.onboarded"
fi

envsubst < /app/config/openclaw.json.tpl > "${CONFIG_PATH}"

if [ -n "${GH_TOKEN:-}" ]; then
  mkdir -p /data/.config/gh
  cat > /data/.config/gh/hosts.yml <<EOF
github.com:
    oauth_token: ${GH_TOKEN}
    git_protocol: https
    user: ${GH_USER:-nathsouzadev}
EOF
  chmod 600 /data/.config/gh/hosts.yml
fi

MAIN_AUTH="${OPENCLAW_HOME}/agents/main/agent/auth-profiles.json"
if [ -f "$MAIN_AUTH" ]; then
  for var in $(compgen -v | grep -E '^AGENT_[A-Z0-9_]+_ID$'); do
    agent_id="${!var}"
    [ -z "$agent_id" ] && continue
    target_dir="${OPENCLAW_HOME}/agents/${agent_id}/agent"
    target_file="${target_dir}/auth-profiles.json"
    if [ ! -s "$target_file" ] || [ "$(wc -c < "$target_file")" -lt 100 ]; then
      mkdir -p "$target_dir"
      cp "$MAIN_AUTH" "$target_file"
    fi
  done
fi

exec openclaw gateway run --port "${GATEWAY_PORT}" --verbose --allow-unconfigured
