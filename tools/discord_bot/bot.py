"""Snowywood Discord bridge bot.

A standalone sidecar next to DreamDaemon. Two transport directions:

  game -> bot   HTTP POST to /ingest (round notifications, OOC mirror, ahelp tickets),
                authenticated with the X-Bot-Secret header.
  bot  -> game  BYOND world-topic calls (status queries, OOC injection, admin replies),
                authenticated with the comms key.

Features: round notification embeds, /status + /players slash commands, live presence,
a two-way OOC bridge, and ahelp tickets relayed to per-ticket Discord threads whose
replies are PM'd back to the player in game.
"""

from __future__ import annotations

import logging

import discord
from aiohttp import web
from discord import app_commands
from discord.ext import commands, tasks

import config
from byond import build_query, get_status, world_topic

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s"
)
log = logging.getLogger("snowybot")


class SnowyBot(commands.Bot):
    def __init__(self) -> None:
        intents = discord.Intents.default()
        intents.message_content = True  # required for the OOC + ahelp reply bridges
        super().__init__(command_prefix="!unused!", intents=intents)
        self._web_runner: web.AppRunner | None = None
        # ahelp ticket bridge state (in-memory; rebuilt as new tickets arrive after a restart)
        self.ticket_threads: dict[str, int] = {}   # initiator ckey -> thread id
        self.thread_ckeys: dict[int, str] = {}      # thread id -> initiator ckey

    async def setup_hook(self) -> None:
        await self._start_ingest_server()
        if config.GUILD_ID:
            guild = discord.Object(id=config.GUILD_ID)
            self.tree.copy_global_to(guild=guild)
            await self.tree.sync(guild=guild)
        else:
            await self.tree.sync()

    async def on_ready(self) -> None:
        log.info("Logged in as %s (%s)", self.user, getattr(self.user, "id", "?"))
        if not self.presence_loop.is_running():
            self.presence_loop.start()

    # --- bot -> game helpers -------------------------------------------------

    async def game_query(self, keyword: str, value: str | None = None, **params: str):
        return await world_topic(
            config.GAME_HOST,
            config.GAME_PORT,
            build_query(keyword, value, key=config.GAME_COMMS_KEY, **params),
        )

    # --- presence ------------------------------------------------------------

    @tasks.loop(seconds=config.PRESENCE_INTERVAL)
    async def presence_loop(self) -> None:
        status = await get_status(config.GAME_HOST, config.GAME_PORT, config.GAME_COMMS_KEY)
        if not status:
            activity = discord.Activity(type=discord.ActivityType.watching, name="server offline")
        else:
            players = status.get("players", "?")
            secs = int(float(status.get("round_duration", 0) or 0))
            label = f"{players} players | {secs // 60}m" if secs else f"{players} players"
            activity = discord.Activity(type=discord.ActivityType.watching, name=label)
        await self.change_presence(activity=activity)

    @presence_loop.before_loop
    async def _before_presence(self) -> None:
        await self.wait_until_ready()

    # --- game -> bot ingest server ------------------------------------------

    async def _start_ingest_server(self) -> None:
        app = web.Application()
        app.router.add_post("/ingest", self._handle_ingest)
        app.router.add_get("/health", lambda _r: web.Response(text="ok"))
        self._web_runner = web.AppRunner(app)
        await self._web_runner.setup()
        site = web.TCPSite(self._web_runner, config.INGEST_HOST, config.INGEST_PORT)
        await site.start()
        log.info("Ingest server listening on %s:%s", config.INGEST_HOST, config.INGEST_PORT)

    async def _handle_ingest(self, request: web.Request) -> web.Response:
        if request.headers.get("X-Bot-Secret") != config.INGEST_SECRET:
            return web.Response(status=401, text="bad secret")
        try:
            payload = await request.json()
        except Exception:
            return web.Response(status=400, text="bad json")

        etype = payload.get("type")
        try:
            if etype == "round":
                await self._on_round(payload)
            elif etype == "ooc":
                await self._on_ooc(payload)
            elif etype == "ahelp":
                await self._on_ahelp(payload)
            else:
                return web.Response(status=400, text="unknown type")
        except Exception:
            log.exception("Failed handling ingest event %s", etype)
            return web.Response(status=500, text="error")
        return web.Response(text="ok")

    async def _on_round(self, payload: dict) -> None:
        channel = self.get_channel(config.ANNOUNCE_CHANNEL_ID)
        if not isinstance(channel, discord.abc.Messageable):
            return
        event = payload.get("event", "")
        title, color = {
            "start": ("Round starting", discord.Color.green()),
            "ending": ("Round ending", discord.Color.orange()),
            "end": ("Round ended", discord.Color.red()),
        }.get(event, (f"Round: {event}", discord.Color.blurple()))
        embed = discord.Embed(title=title, color=color)
        if payload.get("map"):
            embed.add_field(name="Map", value=str(payload["map"]))
        await channel.send(embed=embed)

    async def _on_ooc(self, payload: dict) -> None:
        channel = self.get_channel(config.OOC_CHANNEL_ID)
        if not isinstance(channel, discord.abc.Messageable):
            return
        sender = discord.utils.escape_markdown(str(payload.get("sender", "?")))
        message = str(payload.get("message", ""))
        await channel.send(f"**{sender}:** {message}", allowed_mentions=discord.AllowedMentions.none())

    async def _on_ahelp(self, payload: dict) -> None:
        channel = self.get_channel(config.AHELP_CHANNEL_ID)
        if channel is None:
            try:
                channel = await self.fetch_channel(config.AHELP_CHANNEL_ID)
            except discord.HTTPException as e:
                log.warning("Cannot access ahelp channel %s: %s", config.AHELP_CHANNEL_ID, e)
                return
        if not isinstance(channel, discord.TextChannel):
            log.warning("Ahelp channel %s is not a TextChannel (got %s)", config.AHELP_CHANNEL_ID, type(channel))
            return
        ckey = str(payload.get("sender", "unknown"))
        ticket_id = str(payload.get("id", "?"))
        message = str(payload.get("message", ""))

        thread = None
        existing = self.ticket_threads.get(ckey)
        if existing:
            thread = channel.get_thread(existing) or self.get_channel(existing)
        if thread is None:
            thread = await channel.create_thread(
                name=f"Ticket #{ticket_id} - {ckey}"[:100],
                type=discord.ChannelType.public_thread,
            )
            self.ticket_threads[ckey] = thread.id
            self.thread_ckeys[thread.id] = ckey
            log.info("Opened ahelp thread %s for ckey %s", thread.id, ckey)
        await thread.send(
            f"**{discord.utils.escape_markdown(ckey)}:** {message}",
            allowed_mentions=discord.AllowedMentions.none(),
        )

    # --- Discord -> game bridge (messages) ----------------------------------

    async def on_message(self, message: discord.Message) -> None:
        if message.author.bot or not message.content:
            return

        # OOC channel -> in-game OOC
        if message.channel.id == config.OOC_CHANNEL_ID:
            await self.game_query(
                "discord_ooc",
                sender=message.author.display_name,
                message=message.content,
            )
            return

        # Reply inside an ahelp ticket thread -> PM the player in game
        ckey = self.thread_ckeys.get(message.channel.id)
        if ckey:
            await self.game_query(
                "adminmsg",
                value=ckey,
                msg=message.content,
                sender=message.author.display_name,
            )


bot = SnowyBot()


@bot.tree.command(name="players", description="Show the current player count.")
async def players_cmd(interaction: discord.Interaction) -> None:
    count = await bot.game_query("playing")
    if count is None:
        await interaction.response.send_message("Server is not responding.", ephemeral=True)
    else:
        await interaction.response.send_message(f"Players online: **{int(count)}**")


@bot.tree.command(name="status", description="Show live server status.")
async def status_cmd(interaction: discord.Interaction) -> None:
    status = await get_status(config.GAME_HOST, config.GAME_PORT, config.GAME_COMMS_KEY)
    if not status:
        await interaction.response.send_message("Server is not responding.", ephemeral=True)
        return
    secs = int(float(status.get("round_duration", 0) or 0))
    embed = discord.Embed(title="Server status", color=discord.Color.green())
    embed.add_field(name="Players", value=status.get("players", "?"))
    embed.add_field(name="Map", value=status.get("map_name", "?"))
    embed.add_field(name="Round", value=status.get("round_id", "?"))
    embed.add_field(name="Round time", value=f"{secs // 60}m {secs % 60}s")
    embed.add_field(name="Admins", value=status.get("admins", "?"))
    embed.add_field(name="Gamestate", value=status.get("gamestate", "?"))
    await interaction.response.send_message(embed=embed)


if __name__ == "__main__":
    bot.run(config.TOKEN, log_handler=None)
