# Crusader Kingdoms (working title)

A real-time medieval kingdom builder for phones: found a tiny realm anywhere on a
map of Europe and the Near East, grow it into an empire, and keep it alive through
war, faith, diplomacy and family politics.

This repo contains **all six layers** (living map, your realm, battles,
diplomacy & religion, dynasty & drama, polish & phone) from the
design document (`docs/game-design-document.pdf`).

## Running it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot → **Import** → pick `project.godot` in this folder.
3. Press **F5** (Run project).

**Controls**
- **Move the map:** drag (it glides on when you let go), two-finger drag on a
  trackpad, or WASD / arrow keys. **Zoom:** scroll wheel or pinch (zooms where
  your cursor is), double-click to zoom in, Q/E or -/= keys.
- **Your armies** wear a gold ring; the **army bar** (bottom right) lists them;
  click one to fly to it. Your army is selected when you start.
- **March:** with your army selected, **hover** any province to see the route and
  how many days it takes; **click or right-click** to send it, or **drag** the
  army onto a province. Marching routes flow with arrows.
- `Space` pause/resume, `0` slow-motion (¼), `1` / `2` / `3` speed, `Esc` deselect, `F11` (or ⌘⌃F) fullscreen. The window opens maximized.
- Phone/tablet: one finger pans, two fingers pinch-zoom, tap to select, tap to march.

## Play it on your phone

**Easiest (any phone, iPhone included): play in the browser** at
**https://art282811.github.io/LocalConnect/** — once GitHub Pages is switched on
(repo **Settings → Pages → Deploy from a branch → `claude/new-session-9t693o` →
`/docs` → Save**). In Safari, **Share → Add to Home Screen** gives it an app icon.
The web build lives in `docs/`; rebuild it with
`godot --headless --path . --export-release "Web" build/web/index.html` and copy
`build/web/*` into `docs/`. Add `?perf` to the URL to log frame rate to the console.

**Android — easiest, no computer needed:**
1. Install **Godot Engine** (4.3 or newer) from Google Play.
2. Unzip the project into a folder on the phone.
3. Open Godot → **Import** → pick `project.godot` → tap **Run** (▶).

**Android — as a real app (needs a computer once):**
1. On a PC/Mac install Godot 4.3+, then in Godot: **Editor → Manage Export
   Templates → Download**.
2. Install **OpenJDK 17** and the **Android SDK** (easiest: install Android
   Studio). In Godot: **Editor → Editor Settings → Export → Android**, point it
   at the Java and Android SDK folders.
3. **Project → Export → Android** (the preset is already set up) → **Export
   Project** → you get `build/android/crusader-kingdoms.apk`.
4. Copy the `.apk` to your phone, open it, allow "install unknown apps".
   (Or plug the phone in with USB debugging on and press the Android icon at the
   top right of Godot to install and run it directly.)

**iPhone / iPad:**
- *Without a Mac:* use the **Web** preset (**Project → Export → Web**, already set
  up, single-threaded so it works in Safari). Upload the `build/web` folder to
  [itch.io](https://itch.io) as an HTML5 game (it can be private), open the link
  on your iPhone, then **Share → Add to Home Screen** to get an app icon.
- *With a Mac:* install Xcode, set your Apple Team ID in the iOS preset, export,
  open the generated Xcode project and run it on your phone (a free Apple ID
  works for 7 days at a time; TestFlight/App Store needs the $99/year program).

## What Layer 6 adds

- **Title screen** (Continue, New game, How to play, Settings) and an in-game
  **Menu** (save, load, steward, chronicle, settings, main menu).
- **Save & load** as JSON snapshots in the app's user folder, plus an
  **autosave every in-game year** and when you leave to the main menu.
- **Tutorial**: eight steps that walk you through your first minutes and advance
  as you do each thing (replay it from the title screen).
- **Sound**: clicks, bells, war horns, sword clashes, a funeral toll and a looping
  lute-and-drone tune, all synthesised in code (no audio files needed).
- **Heraldry**: every realm gets a coat of arms (field, division, charge) shown
  on its army banners and beside the names of great realms.
- **Parchment art pass**: age spots, a compass rose and a title cartouche.
- **Phone-ready**: text/button size setting (Normal / Large / Huge), notch-safe
  margins, landscape lock, and export presets for Android, iOS and Web.

## What Layer 1 does

- **The map.** ~390 provinces on a hand-tuned hex grid clipped to real coastlines
  (Iberia to the Caspian, Scandinavia to Egypt), with terrain (plains, forest,
  hills, mountains, marsh, desert), rivers, short sea crossings, and invented
  culture-flavoured place names.
- **40 starting realms.** Real names (France, Castile, Hungary, Kyiv…) mixed with
  invented ones, each 1–3 provinces, each ruler with a personality
  (ambitious, cruel, greedy, pious, cautious).
- **Pick your spawn.** Tap an unclaimed province to found a new realm there, or tap
  an owned one to take over that realm. Or just watch.
- **Real-time clock.** Pause / 1x / 2x / 4x. One day is 1.5 s at 1x; seasons every
  90 days; winter slows armies and causes attrition.
- **A living world.** AI realms recruit, claim empty land, declare war on weaker
  neighbours, besiege and take provinces, make peace, rise in rank
  (County → Duchy → Kingdom → Empire, with culture-specific titles), and fall.
  Big realms crack as far-flung provinces rebel; chieftains found new realms in
  the wilds.
- **Auto-resolve battles** from troops, terrain defence, general skill and luck.
- **One seamless camera.** Continent view shows realm names and great capitals;
  zoom in for towns, castles, ports, monasteries, villages, roads and army counts.
- **News feed + Chronicle** of everything that happens.
- **You can play a little already:** tap your army, then tap a province to march.
  Standing on unclaimed land claims it; standing on enemy land besieges it.
  Tap another realm to declare war or offer peace. Toggle **Steward** to let the AI
  run your wars for you.

## What Layer 2 adds

- **Six resources:** food, gold, wood, stone, iron, faith — shown in a bar under
  the top bar with their daily change. Food follows the seasons (autumn harvest,
  lean winters); people and soldiers eat it; soldiers cost gold.
- **Population & settlements.** Provinces grow when fed and content and shrink in
  famine. Villages become towns at 2,000 people and cities at 5,000, which opens
  more building slots.
- **13 buildings** (`data/buildings.json`): farms, market, barracks, blacksmith,
  walls (palisade → stone walls → castle), church, granary, tavern, lumber camp,
  quarry, mine, port, roads. Tap your province → **Build…**.
- **Taxes & happiness.** Tap **Realm** to set low / normal / high taxes or hold a
  festival. Each province explains its mood (taxes, hunger, war, foreign rulers,
  conquest, churches, taverns…). Below 30 it riots (half output); below 15 it may
  revolt and break away with a peasant army.
- **Recruiting.** In your own province: **Raise levy** (manpower + gold) or, with
  barracks, **hire men-at-arms** (cost iron, fight ~1.8× harder; a blacksmith
  makes them better). Armies at home are topped up automatically if you can pay.
- **Conquest has a cost:** plunder, damaged walls, a year of resentment.
- **AI realms play by the same rules:** they set taxes, build, hold festivals,
  starve, go broke and revolt just like you.

## What Layer 3 adds

- **Battles on the real map.** When hostile armies meet, the fight happens in
  that province, on its own terrain, while the rest of the world keeps moving.
  Several battles can rage at once.
- **One camera, three levels.** Far out: a crossed-swords marker with a strength
  bar. Zoom in: regiment blocks with counts and morale bars. Zoom right in: tiny
  stick-figure soldiers in bucket helms and tabards, horses, flying arrows,
  the fallen, a turning windmill.
- **Regiments** (spearmen, men-at-arms, archers, knights, horse archers) built
  from each army's size, quality and culture.
- **Terrain matters:** forests hide units (ambush shock) and slow cavalry; hills
  give archers range and defence; rivers slow and expose troops except at the
  bridge; the village gives defenders cover and breaks charges.
- **Flanks, charges and morale:** side and rear attacks hurt more and shake
  morale; cavalry charges hit hard but break on spears and stakes; units rout,
  may rally once, and panic spreads.
- **Generals fight on their own.** Each army has a named lord with a fighting
  style (cautious / steady / reckless) and a stance that decides when to pull
  out. Messengers report the outcome in the news feed.
- **Your orders** (tap your army): **take** (tap a province), **Hold here**
  (digs in; stakes after 4 days), **Raid…**, **Retreat**, **Join…**, stance.
- **Take command** of any battle you're in: tap a regiment, tap ground to move,
  tap an enemy to attack; set formation (line / wedge / square) and stance
  (hold / charge / skirmish). Or **Auto-resolve**, or **Withdraw**.
  Taking command drops the game to ¼ speed.
- **Sieges with walls:** defenders behind walls are hard to hurt; attackers must
  batter the gate (much faster once the siege has built rams). Besiegers can
  **Assault walls** against the town garrison; the AI does too.
- A **Battle!** button in the top bar jumps to any fight you're in.

## What Layer 4 adds

- **Opinion (−100…+100)** of every realm toward every other, with reasons you can
  read: borders, faith, culture, wars, treaties, gifts, insults, personality,
  broken oaths. Tap a foreign province → **Diplomacy…**.
- **Treaties:** gifts, insults, non-aggression pacts, alliances, defensive pacts,
  trade agreements, demanding tribute or vassalage, offering to become a vassal.
  Each proposal says whether they're likely to agree.
- **Calls to arms:** allies, defensive partners and vassals are called into wars.
  AI allies may abandon you; refusing your ally's call breaks the alliance.
  Attacking someone you have a pact with makes you an **oathbreaker** to all.
- **Envoys:** AI rulers propose pacts, demand tribute, or call you to arms —
  answer under **Realm → Offers**.
- **Trade routes** between markets and ports carry goods (grain, wine, iron,
  silk, salt, timber, furs) and pay both sides daily. Caravans and ships move
  along them; wars and pirates cut them.
- **Vassals** pay their liege and fight its wars; they may rise up if they hate a
  weak liege. Vassal lands are tinted toward their liege's colour.
- **Faiths:** Catholic, Orthodox, Sunni, Shia and three pagan faiths. Ruling
  provinces of another faith costs happiness; **send missionaries** to convert.
- **Religious heads** (Pope, Patriarch, two Caliphs) judge rulers by piety,
  donations, holy sites and wars on fellow believers — and can **excommunicate**.
  **Realm → Donate** wins their favour.
- **Crusades & jihads** (from Year 6; set in `sim/religion.gd`): the head calls a
  holy war against a region (Jerusalem first if unbelievers hold it). Three ways
  in: **join**, **pledge gold**, or **lend an army** to the leader. With enough
  faith and favour, **call your own** on any unbeliever's province. Victory
  brings faith, loot, glory and relics (permanent bonuses); failure costs faith.
  Crusade arrows sweep across the map.
- **Map modes:** Realms, Faiths, Diplomacy (green = friendly, red = hostile,
  blue = allies).

## What Layer 5 adds

- **You play a dynasty, not one man.** Every realm has a ruling house: a ruler
  with age, health, personality and skills (martial, stewardship, diplomacy,
  learning), a spouse and children. A new ruler brings a new personality, so AI
  realms change course when their kings die. Tap **Dynasty**.
- **Life and death:** people age, fall ill, have children and die — of old age,
  illness, in battle (if they lead an army: tap your army → **Lead it yourself**)
  or on the block.
- **Succession laws:** eldest son, eldest child, elective (the great families
  vote — keep them loyal), or a chosen heir. Changing the law angers the nobles.
- **Marriages** (Dynasty → Family, or Diplomacy → Royal marriage) win friends and
  give **claims**: if a realm's line dies out, the best claimant inherits — a
  ruler with a claim takes the whole realm in a personal union.
- **Great families** with loyalty, power and ambition. Grant them provinces (they
  keep a share of the income), revoke lands, bribe them, or marry into them.
  Disloyal families refuse troops, form factions, demand titles, and may try a
  **coup** or break away in **civil war**.
- **Random events with choices:** plague, bad and bumper harvests, mercenaries,
  a relic found, a travelling merchant, a comet, a rival's insult, a famous
  knight, a child prodigy, a noble's demands, a ransom, a ruler's illness.
  The game pauses while you decide.
- **Heroes:** generals have tactics, siegecraft, logistics and leadership, gain
  levels from battles, and can be killed or captured. Ransom, release or
  execute prisoners (executions appal the other courts).
- **You lose when your dynasty ends or is overthrown.** After a coup or a lost
  election you may **play on as the new house** — the design doc's open question.

## Trade roads and infrastructure

- **Found your own great trade routes.** Tap a province of yours with a market or
  port → **Start a trade route here** → tap the town at the other end (yours, an
  ally's or a trade partner's). You see the path, the founding cost and the
  expected income before you commit. Longer routes and rarer goods pay more; a
  route carrying silk across a long distance becomes a **Silk Road** (×1.5).
- **You own it.** The founder keeps 70% of the profit. Allies can use it (each
  gets a share, and their traffic raises the route's value), or set it to
  **private**. Realms it passes through take a small toll. Caravans may only
  cross your own land, allies', vassals', trade partners' or unclaimed wilds.
- **Protect it with troops.** Every province on the road is a place bandits can
  strike. Armies standing on or next to a stretch keep it safe; tap your army →
  **Patrol the …** (or Realm → Trade routes → **Guard**) and it walks the road,
  heading for the weakest stretch. Watchtowers and caravanserais help. Red **!**
  marks show your unguarded stretches. An enemy army standing on the road closes
  it and plunders the profit; the AI values provinces on its rivals' roads as
  war targets, and guards its own roads with spare armies.
- **Build the kingdom's infrastructure.** Roads appear on the map only where you
  build them (dirt roads, then paved stone roads: 25% / 40% faster for armies
  and caravans). Rivers slow armies unless the province has a **bridge** (towns
  and cities have one; elsewhere you build it), and only a built bridge exists
  to fight over in battle. Construction shows on the map as scaffolding with a
  progress bar.
- Trade agreements still open a small merchant route between partners as before.

## Pace of life

A day still passes every 1.5 s at 1x, so marching and building feel brisk, but a
**year now lasts 720 days** (seasons of 180), so people age half as fast:
about **18 minutes per year at 1x, 4½ minutes at 4x**. A 25-year reign is
roughly 7½ hours at 1x or under 2 hours at 4x. Realms you found yourself start
with a young ruler (18–26). Settings → **Pace of life** offers Brisk (the old
360-day year), Normal, or Epic (1080 days); it applies to new games.

## How the AI thinks

Every AI realm keeps a strategic "mind" (`sim/strategy.gd`), re-assessed monthly:

- **Threats:** each neighbour is scored by its strength *plus the allies who would
  likely fight for it*, how hostile it is, whether it borders us and whether its
  armies are massing on our border. A realm far stronger than the rest alarms
  everyone, so **coalitions** form against it.
- **If to attack:** for every neighbour it estimates its **chance of winning**
  (both sides' allies weighted by how likely they are to join and whether they
  can reach the front; targets already fighting someone else or ruled by a child
  are weaker) and weighs the **value** of the land it could take (people,
  markets, ports, holy sites, same culture and faith, dynastic claims) against
  what it could lose. Each personality has its own nerve and appetite; cautious
  and pious rulers won't break pacts; others will only if the prize is worth the
  dishonour. Realms with empty land nearby prefer to settle it first.
- **When:** a chosen war goes through a **preparation** phase: armies merge and
  muster at a fortified staging province on the border, flanks are secured with
  non-aggression pacts, the target's enemies are courted as allies. It declares
  only when ready, never into winter, and drops the plan if the odds worsen.
  An overwhelmingly stronger realm first demands tribute or vassalage and fights
  only if refused.
- **Where:** specific **objective provinces** ranked by value ÷ difficulty (forts,
  terrain), plus the capital when the target is small enough to finish.
- **In war:** it hunts invaders it can beat, falls back behind walls from ones it
  can't, merges detachments into a main army, refuses to march into a stronger
  enemy army, keeps sieges going and storms walls when the garrison is clearly
  outmatched.
- **Peace** is reasoned too: objectives taken, losing, exhausted, starving or
  broke. AI rulers send *you* peace offers, and accept yours only when it makes
  sense for them.
- **Diplomacy with purpose:** alliances with realms that fear the same enemy,
  encirclement of a planned target, gifts to appease a dangerous neighbour,
  dropping allies who became a threat. Proposals and calls to arms are judged on
  strategic value, and demands are accepted only by those who truly can't win.
- **Intel:** the Diplomacy screen shows what your envoys sense, e.g. *"Their
  armies are gathering on your border!"*

Tuning knobs are constants at the top of `sim/strategy.gd`.

## Testing without a phone

The `tests/` folder runs the game headless with Godot 4.3:

```
godot --headless --path . --script res://tests/check_scripts.gd      # compile every script
godot --headless --path . --script res://tests/simulate.gd -- 10 42  # 10 AI-only years, seed 42
godot --headless --path . --script res://tests/profile.gd -- 3 180   # time each part of a day
```

`simulate.gd` prints a yearly report (realms, wars by kind, battles, troops,
gold flows, mood and its causes, AI postures) and checks that saving and
loading round-trips.

## Layout

| Folder | What's in it |
| --- | --- |
| `data/` | `world.json` (coastlines, seas, terrain zones, rivers, cultures), `realms.json` (starting realms), `buildings.json` (costs, limits, effects), `religions.json` (faiths, holy sites, relics), `names.json` (name syllables). Edit these to tweak content. |
| `sim/` | The simulation, separate from visuals: `world.gd` (clock, AI, wars, sieges, rebellions), `economy.gd` (resources, buildings, people, taxes, happiness, recruiting), `battle.gd` + `regiment.gd` (tactical battles), `diplomacy.gd` (opinion, treaties, trade), `religion.gd` (faiths, heads, crusades), `dynasty.gd` + `character.gd` (people, succession, nobles, events), `strategy.gd` (AI strategy), `trade.gd` (great trade routes), `save_game.gd` (save/load), `map_builder.gd` (provinces from the outline), `province.gd`, `realm.gd`, `army.gd`, `names.gd`. |
| `map/` | `map_view.gd` (parchment map), `labels_view.gd` (names, settlements, roads), `overlay_view.gd` (armies, sieges, battle smoke), `battle_view.gd` (battle blocks and soldiers), `camera_rig.gd` (pan/zoom/pinch). |
| `ui/` | `hud.gd` — top bar, news feed, info panel, spawn prompt, chronicle. |
| `main.gd` | Wires it together and handles taps/selection. |

Tuning knobs are constants at the top of `sim/world.gd` (day length, terrain,
aggression, truces) and `sim/economy.gd` (yields, food, upkeep, taxes, recruit costs).

## Exporting

The presets in `export_presets.cfg` already include `data/*.json` (the game's
map and content). If you make a new preset, add `data/*.json` under
*Resources → Filters to export non-resource files*, or the game won't start.

## Roadmap

1. ~~Layer 1 — Living map~~
2. ~~Layer 2 — Your realm~~
3. ~~Layer 3 — Battles~~
4. ~~Layer 4 — Diplomacy, religion, crusades~~
5. ~~Layer 5 — Dynasty & drama~~
6. ~~Layer 6 — Polish & phone builds~~

Next ideas: real province shapes from public map data, naval battles (an open
question in the design doc), recorded music and art, balance tuning from play.
