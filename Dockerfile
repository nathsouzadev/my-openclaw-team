FROM node:24-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gettext-base \
      tini \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

ENV OPENCLAW_HOME=/data/.openclaw \
    HOME=/data \
    NODE_ENV=production \
    GATEWAY_PORT=5010

WORKDIR /app

COPY config/openclaw.json.tpl /app/config/openclaw.json.tpl
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 5010 5011 5012 5013 5014 5015 5016 5017 5018 5019 5020

VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
