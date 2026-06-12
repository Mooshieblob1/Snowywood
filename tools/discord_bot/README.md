# Snowywood Discord bot

A standalone sidecar that bridges the running game server and Discord. It replaces the
old one-way `DISCORD_WEBHOOK_URL` notification with a real bot.

## What it does

- **Round notifications** — round start / ending / ended posted as embeds in an announce channel.
- **Server status** — `/status` and `/players` slash commands, plus live bot presence ("N players | Mm").
- **OOC bridge** — messages in a chosen Discord channel appear in game OOC, and in-game OOC is mirrored back.
- **Ahelp relay** — each ticket opens a Discord thread in a staff channel; staff replies in the thread are PM'd to the player in game.

## How it talks to the game

```
game  --HTTP POST /ingest (X-Bot-Secret)-->  bot      (round events, OOC mirror, ahelp tickets)
bot   --BYOND world topic (comms key)----->  game     (status, OOC injection, admin replies)
```

The game side is already wired up:
- `send_bot_event()` in `code/__HELPERS/chat.dm` posts events to `DISCORD_BOT_URL`.
- The `discord_ooc` / `status` / `adminmsg` / `playing` handlers in `code/datums/world_topic.dm` serve the bot's requests.

## Setup

1. **Create the bot application**
   - Go to <https://discord.com/developers/applications> → New Application.
   - **Bot** tab → Reset Token → copy the token.
   - Under **Privileged Gateway Intents**, enable **Message Content Intent** (needed for the OOC/ahelp reply bridges).
   - **OAuth2 → URL Generator**: scopes `bot` + `applications.commands`; bot permissions: View Channels, Send Messages, Create Public Threads, Send Messages in Threads, Embed Links. Open the generated URL to invite the bot.

2. **Get channel IDs** — enable Developer Mode (User Settings → Advanced), right-click each channel → Copy ID, for the announce / OOC / ahelp channels.

3. **Configure the game** (already templated):
   - `config/config.txt`: `DISCORD_BOT_URL http://127.0.0.1:5000/ingest`
   - `config/secrets.txt` (gitignored): set `DISCORD_BOT_SECRET` to a random value (`openssl rand -hex 32`).
   - `config/comms.txt`: make sure `COMMS_KEY` is set (the bot needs the same value).

4. **Configure the bot**
   ```bash
   cd tools/discord_bot
   cp .env.example .env
   # fill in token, channel IDs, GAME_COMMS_KEY (= COMMS_KEY), BOT_INGEST_SECRET (= DISCORD_BOT_SECRET)
   ```

5. **Run it**
   ```bash
   ./run.sh
   ```
   This builds the image and runs it with `--network host --restart unless-stopped`, so it
   auto-starts on reboot like the game and database containers. Logs: `docker logs -f snowywood-discord-bot`.

6. **Apply the game side** — the new config/topic handlers take effect after the next compile + round restart.

## Notes

- `--network host` is used so `127.0.0.1` reaches both the game (1337) and the ingest port (5000).
  Keep `BOT_INGEST_HOST=127.0.0.1` so the ingest endpoint is not exposed off-box.
- Ahelp thread↔player mappings are in-memory; after a bot restart, replies work again once the
  player sends a new ahelp (which re-creates/links the thread).
- Leave `DISCORD_WEBHOOK_URL` blank once the bot is running, or round notifications post twice.
