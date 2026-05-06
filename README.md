# open-claw — dois agentes Slack via Docker

Roda um gateway [OpenClaw](https://github.com/openclaw/openclaw) em container, expondo
**dois agentes como usuários (bots) distintos** dentro de um mesmo workspace do Slack.
Cada agente tem seu próprio Slack App (par `botToken` + `appToken` em Socket Mode) e seu
próprio workspace de arquivos isolado dentro do volume persistente.

A arquitetura segue o padrão oficial recomendado: uma conta por agente em
`channels.slack.accounts`, e `bindings` roteando cada conta Slack para um `agentId`.

```
Slack workspace
 ├── App "Alice" (xoxb / xapp)  ──►  accountId: alice  ──►  agentId: main
 └── App "Bob"   (xoxb / xapp)  ──►  accountId: bob    ──►  agentId: agent-2
                                                  ▲
                                       OpenClaw gateway (container)
                                       portas 5010–5020 expostas
```

---

## Estrutura

```
.
├── Dockerfile               # node:24-slim + openclaw@latest global + gh CLI
├── docker-compose.yml       # serviço único, mapeia 5010-5020
├── entrypoint.sh            # renderiza config via envsubst e inicia o gateway
├── config/
│   └── openclaw.json.tpl    # template de config (multi-bot)
├── agents/                  # persona dos agentes (versionado no git)
│   └── <agent_id>/          # ex.: nanisca/, alice/, bob/
│       ├── AGENTS.md        # instruções gerais
│       ├── SOUL.md          # personalidade / voz
│       └── TOOLS.md         # tools customizadas (opcional)
├── skills/
│   └── superpowers/         # submodule git — skills compartilhadas entre todos os agentes
├── env.example              # placeholders — copie para .env
├── data/                    # volume persistente (HOME do container) — NÃO commitar
└── .dockerignore
```

`data/` guarda toda a estrutura `~/.openclaw` (sessões, workspaces por agente,
state, logs). Sobrevive a `docker compose down`. Apague-o para resetar tudo.

---

## Pré-requisitos

- Docker Engine 24+ e Docker Compose v2
- Permissão de admin no Slack workspace para criar Apps e instalar bots
- Um channel ID Slack onde os bots vão atuar (usar ID `C...`, **não** `#nome`)

---

## 1. Criar duas Slack Apps (uma por agente)

Repetir os passos abaixo **duas vezes** — uma para cada bot.

1. Em <https://api.slack.com/apps/new>, escolha **"From a manifest"** e selecione o workspace.
2. Cole o manifest base (ajuste `name` e `display_name` para cada bot, ex.: `Alice` e `Bob`):

   ```yaml
   display_information:
     name: Alice
   features:
     bot_user:
       display_name: Alice
       always_online: true
   oauth_config:
     scopes:
       bot:
         - app_mentions:read
         - channels:history
         - channels:read
         - chat:write
         - groups:history
         - groups:read
         - im:history
         - im:read
         - im:write
         - mpim:history
         - mpim:read
         - users:read
         - files:read
         - reactions:read
   settings:
     event_subscriptions:
       bot_events:
         - app_mention
         - message.channels
         - message.groups
         - message.im
         - message.mpim
     interactivity:
       is_enabled: true
     org_deploy_enabled: false
     socket_mode_enabled: true
     token_rotation_enabled: false
   ```

3. Em **Basic Information → App-Level Tokens**, gere um token com escopo
   `connections:write`. Copie o `xapp-...` → será `AGENT_X_SLACK_APP_TOKEN`.
4. Instale o app no workspace. Em **OAuth & Permissions**, copie o **Bot User OAuth Token**
   `xoxb-...` → será `AGENT_X_SLACK_BOT_TOKEN`.
5. Convide os dois bots no canal alvo: `/invite @Alice`, `/invite @Bob`.
6. Pegue o channel ID: clique no nome do canal → **About** → **Channel ID**
   (formato `C0XXXXXXXXX`).

> Socket Mode é tráfego **outbound** apenas — não precisa expor URLs públicas
> nem signing secret.

---

## 2. Configurar `.env`

```bash
cp env.example .env
```

Edite `.env` e preencha:

| variável                                    | o que é                                      |
| ------------------------------------------- | -------------------------------------------- |
| `GATEWAY_PORT`                              | porta HTTP do gateway (default `5010`)       |
| `AGENT_1_ID` / `AGENT_2_ID`                 | id interno do agente OpenClaw (`main`, etc.) |
| `AGENT_1_NAME` / `AGENT_2_NAME`             | nome amigável (deve casar com o bot Slack)   |
| `AGENT_1_ACCOUNT_ID` / `AGENT_2_ACCOUNT_ID` | chave em `channels.slack.accounts`           |
| `AGENT_X_SLACK_BOT_TOKEN`                   | `xoxb-...` daquele bot                       |
| `AGENT_X_SLACK_APP_TOKEN`                   | `xapp-...` daquele bot                       |
| `SLACK_CHANNEL_ID`                          | `C...` do canal compartilhado                |

> O primeiro agente **deve** ter `AGENT_1_ID=main` (default do OpenClaw, com permissões
> mais altas). Demais agentes podem usar qualquer id (`agent-2`, `analytics`, etc.).

---

## 3. Subir

```bash
docker compose up --build -d
docker compose logs -f
```

Esperado nos logs:

```
gateway listening on 0.0.0.0:5010
slack: account=alice connected (socket mode)
slack: account=bob   connected (socket mode)
bindings: slack/alice → main, slack/bob → agent-2
```

Health-check rápido:

```bash
docker exec openclaw-slack openclaw doctor --non-interactive
docker exec openclaw-slack openclaw status
```

No Slack, mencione cada bot no canal:

```
@Alice resuma a thread acima
@Bob   liste os PRs abertos
```

---

## 4. Operar

| ação                                  | comando                                                        |
| ------------------------------------- | -------------------------------------------------------------- |
| Ver logs                              | `docker compose logs -f`                                       |
| Reiniciar gateway (após mudar `.env`) | `docker compose restart`                                       |
| Recompilar imagem                     | `docker compose up --build -d`                                 |
| Status do gateway                     | `docker exec openclaw-slack openclaw status`                   |
| Diagnóstico                           | `docker exec openclaw-slack openclaw doctor --non-interactive` |
| Falar com um agente via CLI           | `docker exec -it openclaw-slack openclaw agent --message "oi"` |
| Resetar estado (perde sessões!)       | `docker compose down && rm -rf data && docker compose up -d`   |

Mudou config? Sempre `docker compose restart` — o `entrypoint.sh` re-renderiza
`config.json` a partir do template + envs a cada start.

---

## 5. Adicionar mais agentes

O padrão escala. Para um terceiro agente "Carla":

### 5.1. Criar a 3ª Slack App

Mesmo processo da seção 1, com `display_name: Carla`. Guarde os tokens.

### 5.2. Adicionar variáveis ao `.env`

```bash
AGENT_3_ID=agent-3
AGENT_3_NAME=Carla
AGENT_3_ACCOUNT_ID=carla
AGENT_3_SLACK_BOT_TOKEN=xoxb-...
AGENT_3_SLACK_APP_TOKEN=xapp-...
```

### 5.3. Estender o template `config/openclaw.json.tpl`

Adicione o bloco em `agents.registry`:

```json
"${AGENT_3_ID}": {
  "name": "${AGENT_3_NAME}",
  "workspace": "/data/.openclaw/workspaces/${AGENT_3_ID}"
}
```

Em `channels.slack.accounts`:

```json
"${AGENT_3_ACCOUNT_ID}": {
  "name": "${AGENT_3_NAME}",
  "botToken": "${AGENT_3_SLACK_BOT_TOKEN}",
  "appToken": "${AGENT_3_SLACK_APP_TOKEN}"
}
```

E em `bindings`:

```json
{
  "agentId": "${AGENT_3_ID}",
  "match": { "channel": "slack", "accountId": "${AGENT_3_ACCOUNT_ID}" }
}
```

### 5.4. Exportar a env no `entrypoint.sh`

Adicione `AGENT_3_*` ao `export`:

```sh
export ... \
       AGENT_3_ID AGENT_3_NAME AGENT_3_ACCOUNT_ID \
       AGENT_3_SLACK_BOT_TOKEN AGENT_3_SLACK_APP_TOKEN
```

(Sem isso, `envsubst` substitui por string vazia e a config sai inválida.)

### 5.5. Criar pasta de persona e bind-mount

```bash
mkdir -p agents/carla
# crie AGENTS.md / SOUL.md dentro (ver §6)
```

Em `docker-compose.yml`, adicione em `volumes:`:

```yaml
- ./agents/carla:/data/.openclaw/workspaces/agent-3/.persona:ro
```

(O caminho destino tem que usar o **`AGENT_3_ID`** definido no `.env` — aqui `agent-3`.)

### 5.6. Rebuild

```bash
docker compose up --build -d
```

Convide o novo bot no canal (`/invite @Carla`) e teste.

> Repita para 4, 5, N agentes. O OpenClaw documenta que o padrão "uma Slack App
> por identidade + binding por accountId" escala para 10+ agentes sem mudanças
> arquiteturais.

---

## 6. Personalização por agente (persona)

A persona de cada agente — `AGENTS.md`, `SOUL.md`, `TOOLS.md`, etc. — fica no
**host**, em `agents/<agent_id>/`, e é bind-mountada read-only dentro do
workspace do agente em `data/.openclaw/workspaces/<AGENT_ID>/.persona/`.

```
agents/                              ← edite aqui (versionado no git)
└── nanisca/
    ├── AGENTS.md     # instruções gerais do agente
    ├── SOUL.md       # personalidade / voz
    └── TOOLS.md      # tools customizadas (opcional)
```

> ⚠️ **Não confunda** com `data/.openclaw/workspaces/<AGENT_ID>/*.md`. Aqueles são
> arquivos **de runtime** que o OpenClaw escreve/sobrescreve sozinho. Edite
> persona apenas em `agents/<agent_id>/` no host.

### Bind-mount no `docker-compose.yml`

Para cada agente, adicione uma linha em `volumes:` mapeando a pasta da persona:

```yaml
volumes:
  - ./data:/data
  - ./agents/nanisca:/data/.openclaw/workspaces/pm_nanisca/.persona:ro
  # adicione mais um por agente:
  - ./agents/alice:/data/.openclaw/workspaces/agent-2/.persona:ro
  - ./agents/bob:/data/.openclaw/workspaces/agent-3/.persona:ro
```

Atenção: o caminho destino usa o **`AGENT_ID`** (não `ACCOUNT_ID` nem `NAME`) —
tem que casar com `${AGENT_X_ID}` do `.env`.

### Workflow de iteração

Mudanças nos `.md` em `agents/<id>/` **não** exigem rebuild nem restart — o
OpenClaw relê a persona em cada nova sessão/turno. Salvou no host → próxima
mensagem já vê.

### Skills customizadas

Skills vivem dentro do workspace persistente (não no `agents/`):

```
data/.openclaw/workspaces/<AGENT_ID>/skills/<skill>/SKILL.md
```

Como `data/` é gitignore'd, skills criadas em produção não são versionadas
automaticamente. Se quiser uma skill vir junto do template, adicione um segundo
bind-mount apontando para uma pasta versionada (ex.: `./skills/<id>/`).

### Skills compartilhadas (superpowers)

[obra/superpowers](https://github.com/obra/superpowers) está incluído como
submodule git em `skills/superpowers/` e disponibilizado para **todos** os
agentes automaticamente.

Como funciona:
- `docker-compose.yml` monta `./skills/superpowers/skills` em
  `/opt/superpowers/skills:ro` dentro do container.
- `entrypoint.sh` itera sobre todos os `AGENT_*_ID` e cria um symlink
  `data/.openclaw/workspaces/<AGENT_ID>/skills/superpowers → /opt/superpowers/skills`
  a cada boot.

Comandos úteis:

```bash
# clone inicial (já faz fetch dos submodules):
git clone --recurse-submodules <repo-url>

# se já clonou sem --recurse-submodules:
git submodule update --init --recursive

# atualizar superpowers para a última versão upstream:
git submodule update --remote skills/superpowers
git add skills/superpowers && git commit -m "bump superpowers"
```

Não precisa rebuild da imagem para atualizar — o bind-mount reflete o conteúdo
do host. Basta reiniciar o container (`docker compose restart`) se quiser
recriar os symlinks (não estritamente necessário, mas garante novos agentes).

---

## 7. Endurecimento (recomendado antes de produção)

Adicione ao topo de `agents` no template:

```json
"defaults": {
  "workspace": "/data/.openclaw/workspace",
  "sandbox": { "mode": "non-main" }
}
```

Isso roda agentes não-`main` em sandbox (default Docker), bloqueando acesso direto
ao host para `agent-2`, `agent-3`, etc. O agente `main` continua com acesso total —
trate o `AGENT_1_*` como o agente "operador", não o "público".

Considere também:

- `dmPolicy: "pairing"` (já no template) — exige `openclaw pairing approve slack <code>`
  antes de DMs externos
- `groupPolicy: "allowlist"` + `requireMention: true` — bots só respondem quando mencionados
- Não publique o `.env`. Use Docker secrets ou um secret manager em produção.

---

## 8. Troubleshooting

| sintoma                       | causa provável / fix                                    |
| ----------------------------- | ------------------------------------------------------- |
| `slack: missing_scope` no log | scope faltando no manifest — reinstale o app            |
| Bot não responde a menções    | bot não foi convidado no canal (`/invite @Bot`)         |
| `account=X status=missing`    | env do token vazia — confira `.env` e `entrypoint.sh`   |
| `bindings` não mapeia         | `accountId` no binding ≠ chave em `accounts`            |
| Channel não roteia            | usou `#nome` em vez do ID `C...`                        |
| Mudei `.env` e nada mudou     | esqueceu de `docker compose restart`                    |
| Porta já em uso               | mude `GATEWAY_PORT` no `.env` (deve ficar em 5010–5020) |

Logs verbosos: o gateway já roda com `--verbose`. Para detalhe extra:

```bash
docker exec openclaw-slack openclaw status --json
```

---

## Referências

- OpenClaw — README: <https://github.com/openclaw/openclaw>
- OpenClaw — canal Slack: <https://docs.openclaw.ai/channels/slack>
- Padrão multi-agente Slack: <https://gist.github.com/rafaelquintanilha/9ca5ae6173cd0682026754cfefe26d3f>
