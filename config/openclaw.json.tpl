{
  "gateway": {
    "port": ${GATEWAY_PORT},
    "mode": "local",
    "bind": "custom",
    "customBindHost": "0.0.0.0"
  },
  "agents": {
    "defaults": {
      "workspace": "/data/.openclaw/workspace",
      "model": "${GEMINI_MODEL}"
    },
    "list": [
      {
        "id": "${AGENT_PM_ID}",
        "name": "${AGENT_PM_NAME}",
        "workspace": "/data/.openclaw/workspaces/${AGENT_PM_ID}"
      }
    ]
  },
  "channels": {
    "slack": {
      "enabled": true,
      "mode": "socket",
      "dmPolicy": "open",
      "dm": { "allowFrom": ["${SLACK_OPERATOR_USER_ID}"] },
      "groupPolicy": "allowlist",
      "replyToMode": "all",
      "replyToModeByChatType": {
        "direct": "off"
      },
      "streaming": {
        "preview": {
          "toolProgress": false
        }
      },
      "channels": {
        "${SLACK_PRODUCT_CHANNEL_ID}": {
          "enabled": true,
          "requireMention": true,
          "users": ["${SLACK_OPERATOR_USER_ID}"]
        }
      },
      "accounts": {
        "${AGENT_PM_ACCOUNT_ID}": {
          "name": "${AGENT_PM_NAME}",
          "botToken": "${AGENT_PM_SLACK_BOT_TOKEN}",
          "appToken": "${AGENT_PM_SLACK_APP_TOKEN}"
        }
      }
    }
  },
  "bindings": [
    {
      "agentId": "${AGENT_PM_ID}",
      "match": { "channel": "slack", "accountId": "${AGENT_PM_ACCOUNT_ID}" }
    }
  ],
  "messages": {
    "visibleReplies": "automatic",
    "groupChat": {
      "visibleReplies": "automatic"
    }
  }
}
