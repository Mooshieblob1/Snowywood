/*

Here's how to use the TGS chat system with configs

send2adminchat is a simple function that broadcasts to all admin channels that are designated in TGS

send2chat is a bit verbose but can be very specific

In TGS3 it will always be sent to all connected designated game chats.

In TGS4+ they use the new tagging system

The second parameter is a string, this string should be read from a config.
What this does is dictate which TGS channels can be sent to.

For example if you have the following channels in tgs4 set up
- Channel 1, Tag: asdf
- Channel 2, Tag: bombay,asdf
- Channel 3, Tag: Hello my name is asdf
- Channel 4, No Tag
- Channel 5, Tag: butts

and you make the call:

send2chat(new /datum/tgs_message_content("I sniff butts"), CONFIG_GET(string/where_to_send_sniff_butts))

and the config option is set like:

WHERE_TO_SEND_SNIFF_BUTTS asdf

It will be sent to channels 1 and 2

Alternatively if you set the config option to just:

WHERE_TO_SEND_SNIFF_BUTTS

it will be sent to all connected chats.
*/

/**
 * Asynchronously sends a message to TGS chat channels.
 *
 * message - The [/datum/tgs_message_content] to send.
 * channel_tag - Required. If "", the message with be sent to all connected (Game-type for TGS3) channels. Otherwise, it will be sent to TGS4 channels with that tag (Delimited by ','s).
 * admin_only - Determines if this communication can only be sent to admin only channels.
 */
/proc/send2chat(datum/tgs_message_content/message, channel_tag, admin_only = FALSE)
	set waitfor = FALSE
	if(channel_tag == null || !world.TgsAvailable())
		return

	var/datum/tgs_version/version = world.TgsVersion()
	if(channel_tag == "" || version.suite == 3)
		world.TgsTargetedChatBroadcast(message, admin_only)
		return

	var/list/channels_to_use = list()
	for(var/I in world.TgsChatChannelInfo())
		var/datum/tgs_chat_channel/channel = I
		var/list/applicable_tags = splittext(channel.custom_tag, ",")
		if((!admin_only || channel.is_admin_channel) && (channel_tag in applicable_tags))
			channels_to_use += channel

	if(channels_to_use.len)
		world.TgsChatBroadcast(message, channels_to_use)

/**
 * Sends a message via a configured Discord webhook (DISCORD_WEBHOOK_URL in config).
 */
/proc/send_discord_webhook(message)
	set waitfor = FALSE
	var/webhook_url = CONFIG_GET(string/discord_webhook_url)
	if(!webhook_url)
		return
	
	var/list/payload = list("content" = message)
	var/json_body = json_encode(payload)
	var/datum/http_request/request = new()
	request.prepare(RUSTG_HTTP_METHOD_POST, webhook_url, json_body, list("Content-Type" = "application/json"))
	request.begin_async()

/**
 * Fire-and-forget event to the Discord bot sidecar (DISCORD_BOT_URL in config).
 *
 * event_type - short string the bot dispatches on ("round", "ooc", "ahelp").
 * data - assoc list of extra fields merged into the JSON payload.
 * Authenticated with the X-Bot-Secret header (DISCORD_BOT_SECRET). No-ops if the bot URL is unset.
 */
/proc/send_bot_event(event_type, list/data)
	set waitfor = FALSE
	var/bot_url = CONFIG_GET(string/discord_bot_url)
	if(!bot_url)
		return
	var/list/payload = list("type" = event_type)
	if(islist(data))
		for(var/k in data)
			payload[k] = data[k]
	var/json_body = json_encode(payload)
	var/list/headers = list("Content-Type" = "application/json")
	var/secret = CONFIG_GET(string/discord_bot_secret)
	if(secret)
		headers["X-Bot-Secret"] = secret
	var/datum/http_request/request = new()
	request.prepare(RUSTG_HTTP_METHOD_POST, bot_url, json_body, headers)
	request.begin_async()

/**
 * Asynchronously sends a message to TGS admin chat channels.
 *
 * category - The category of the mssage.
 * message - The message to send.
 */
/proc/send2adminchat(category, message, embed_links = FALSE)
	set waitfor = FALSE

	category = replacetext(replacetext(category, "\proper", ""), "\improper", "")
	message = replacetext(replacetext(message, "\proper", ""), "\improper", "")
	if(!embed_links)
		message = GLOB.has_discord_embeddable_links.Replace(replacetext(message, "`", ""), " ```$1``` ")
	world.TgsTargetedChatBroadcast(new /datum/tgs_message_content("[category] | [message]"), TRUE)

/// Handles text formatting for item use hints in examine text
#define EXAMINE_HINT(text) ("<b>" + text + "</b>")

