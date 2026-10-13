# Decisions, sources and open questions

The build was done autonomously in a cloud sandbox (Linux, no display, no Twitch or Streamer.bot). This file records every judgement call so you can review or reverse it.

## Versions

- **Godot 4.7.2-stable.** On 2026-10-13 I probed the official GitHub release downloads (`godotengine/godot/releases/download/<v>-stable/...`): 4.7.2 exists and 4.7.3 / 4.8 do not, so 4.7.2 was the latest stable. The pin is in `project.godot` (`config/features`) and in the README.
- The renderer is **Compatibility (OpenGL)**. It handles transparent windows most reliably, works on older GPUs, and is what the xvfb screenshots used.
- Everything uses GDScript only, with no addons and no GUT. The test runner is a small custom one (`tests/run_tests.gd`).

## Streamer.bot protocol: sources

- **docs.streamer.bot and streamer.bot are blocked by the sandbox's network policy.** I could not read the official docs directly, and I didn't try to route around the block.
- The protocol was taken instead from the official **`@streamerbot/client` npm package v2.0.1** (MIT licence, published 2026-07-20, fetched through the npm registry on 2026-10-13). Its compiled source and type definitions document:
  - the default endpoint, `ws://127.0.0.1:8080/`;
  - the `Hello` handshake, including an `authentication: {salt, challenge}` object when auth is on;
  - the auth formula: `base64(sha256(base64(sha256(password + salt)) + challenge))`, sent as `{"request":"Authenticate","authentication":...}`;
  - the request/response `id` + `status` convention;
  - the `Subscribe` request format, `{"events": {"Twitch": ["ChatMessage", ...]}}`;
  - the event envelope: `{timeStamp, event: {source, type}, data}`;
  - the payload fields for `Twitch.ChatMessage` (`data.message.{userId, username, displayName, message}`), `Twitch.RewardRedemption` (`user_*`, `user_input`, `reward.title`), `Twitch.Raid` (`from_broadcaster_user_*`, `viewers`) and `Twitch.Follow` (`user_*`);
  - the full list of event names, which is where the paid-event list comes from.
- I only read the package for protocol facts. No code was copied from it.
- Payload shapes can drift between Streamer.bot versions. As a hedge, the chat normaliser also accepts a `data.user.{id, login, name}` + `data.text` shape. **Unverified:** check against your real Streamer.bot with `"debug": {"log_events": true}`.

## Anti-bot / AI-crawler checks (at your request)

- **github.com**: the sandbox blocked reading robots.txt. I only downloaded the official Godot release zip, which is the documented download location, and crawled nothing.
- **registry.npmjs.org**: this is the package API built for the `npm` client and has no robots.txt. I used it for one `npm view` and one `npm pack`.
- **www.npmjs.com**: serves a Cloudflare bot challenge. I never fetched pages from it.
- **docs.streamer.bot / streamer.bot**: blocked by sandbox policy, so I accessed nothing.
- **Web search**: I used it once to find the docs page names. Only search result snippets were read.

## Design decisions and defaults

- **No Streamer.bot actions are required.** The overlay subscribes to the raw `Twitch.*` events over the WebSocket. Chat commands are parsed in the overlay, so there is nothing to configure in Streamer.bot except enabling the WebSocket server, and setup can't go out of sync.
- **Events the overlay subscribes to:** only `Twitch.ChatMessage`, `Twitch.Raid` and `Twitch.Follow`, plus `Twitch.RewardRedemption` when redeems are enabled. The list is derived from what the loaded modules declare.
- **Redeems are off by default** (`redeems.enabled: false`), as required. When enabled, they skip per-user cooldowns (the viewer paid points) but still go through the shared queue.
- **Cooldowns:**
  - 2 s per-user gap between any two commands;
  - per-command cooldowns: `!join` 5 s, `!bonk` 20 s, `!hi` 30 s, others 10 s by default;
  - channel-wide limits on follows (2 s) and raids (30 s).
  - Cooldowns are checked **before** queueing, so spam never fills the queue, and unknown commands consume nothing.
- **Queue:** capacity 50, at most 2 pending events per viewer, and 4 events per second dispatched to modules. When the queue is full, the *new* event is rejected, so earlier viewers keep their place.
- **Isolation:** GDScript has no exceptions, but a runtime error aborts only the failing function, which then returns `null`. Handlers must `return true`; 5 failures in a row disable that module and nothing else. Godot 4.5+'s `Logger` API counts engine and script errors, both in tests and in the overlay's `STATS` output.
- **Paid events:** see `core/paid_events.gd`. I included some debatable entries on the safe side:
  - `Twitch.AutomaticRewardRedemption` and `Twitch.PowerUp*` (Twitch power-ups cost bits);
  - `CrowdControl.EffectRequest` and `CrowdControl.CoinExchange` (paid coins);
  - Trovo spells (paid);
  - wildcards like `Twitch.*`.
  - Regular channel point redemptions (`Twitch.RewardRedemption`) and community goal contributions are free and allowed.
- **Cheer messages:** chat messages that contain cheers still arrive as `ChatMessage`. A command inside one is treated like any other chat command (free for everyone); the bits amount is never read.
- **Greeter module:** I added this small module (`!hi`) in stage 1 so the core had something to exercise end to end. It also serves as the example in "Adding a new module". Disable it with `modules.greeter.enabled: false`.
- **Critter Race:**
  - 6 lanes; the race starts once 3 viewers join, or after 30 s with NPC fill.
  - Viewers who join mid-race get a reserved spot in the next race.
  - Each viewer always gets the same critter (picked by a hash of their user id).
  - A raid starts a race with the raider as a big pink triangle. If the lobby is already full of viewers, the raider isn't added; a viewer is never bumped.
- **Bonk:**
  - Objects follow a ballistic arc computed to land on the cam region (`launch_velocity`), with a random aim offset.
  - The cam region is an invisible static box that objects bounce off, and an invisible floor (on by default) catches them.
  - "BONK!" and the hit sound fire only when an object touches the cam region.
  - Labels show `viewer -> target`.
  - A raid throws min(viewers, 10) objects.
  - Follow bonks are off by default.
- **Default regions** assume a 1920×1080 canvas: race bottom-left, cam bottom-right, greeter pops in the upper band. Adjust them with `debug.show_regions: true`.
- **Transparency:** the overlay uses per-pixel transparency by default, with a documented chroma-key fallback (`window.transparent: false` + `background_color`).
- **Config:** JSON, so it's easy to hand-edit and supports `_comment` keys. User maps replace default maps rather than merging (e.g. `bonk.objects`, `redeems.rewards`), so you can remove the defaults.
- **Text safety:** names and messages are stripped of control characters, zero-width characters and bidi overrides, and trimmed to 25 and 300 characters.

## What was verified here vs. what wasn't

**Verified in the sandbox with Godot 4.7.2 headless and xvfb:**
- 119 unit tests pass.
- The integration runs pass, ending with zero engine or script errors and no leaks.
- The paid guard fails on the bad fixture, as intended.
- Virtual-display screenshots work (see `docs/screenshots/`).

**Not verifiable here, so please check by hand:**
1. A real Streamer.bot connection, and that real payloads match the shapes above. Turn on `debug.log_events` for one stream.
2. Window transparency on Windows, and whether OBS captures it: Game Capture with "Allow Transparency" vs. Window Capture. If it doesn't work, fall back to chroma key.
3. Click-through on Windows (`window.click_through`).
4. Sound output. The sandbox has no audio device, so loading was tested but playback wasn't heard.
5. An exported Windows build. Module discovery handles exported `.remap` files, but I didn't run an actual export.
6. Font coverage for emoji and unusual names. Godot's default font may show boxes for some emoji.

## Open questions for you

- The "minimal copyrighted assets" allowance wasn't needed. Everything is code-drawn shapes, with no third-party assets.
- Should `!bonk` targets be limited to users currently in chat? Right now any name is accepted and only shown as a label.
- Would you like a Streamer.bot-side "send message" reply in chat (e.g. "@alice joined the race!")? That would need a Streamer.bot `SendMessage` request, which I left out to keep the overlay read-only.
