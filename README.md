# Crusader Kingdoms (working title)

A real-time medieval kingdom builder for phones: found a tiny realm anywhere on a
map of Europe and the Near East, grow it into an empire, and keep it alive through
war, faith, diplomacy and family politics.

This repo contains **Layers 1–3** (living map, your realm, battles) from the
design document (`docs/game-design-document.pdf`).

## Running it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot → **Import** → pick `project.godot` in this folder.
3. Press **F5** (Run project).

Desktop controls: drag to pan, mouse wheel to zoom, click to select.
Keys: `Space` pause/resume, `0` slow-motion (¼), `1` / `2` / `3` speed.
Phone/tablet: one finger pans, two fingers pinch-zoom, tap to select.

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

## Layout

| Folder | What's in it |
| --- | --- |
| `data/` | `world.json` (coastlines, seas, terrain zones, rivers, cultures), `realms.json` (starting realms), `buildings.json` (costs, limits, effects), `names.json` (name syllables). Edit these to tweak content. |
| `sim/` | The simulation, separate from visuals: `world.gd` (clock, AI, wars, sieges, rebellions), `economy.gd` (resources, buildings, people, taxes, happiness, recruiting), `battle.gd` + `regiment.gd` (tactical battles), `map_builder.gd` (provinces from the outline), `province.gd`, `realm.gd`, `army.gd`, `names.gd`. |
| `map/` | `map_view.gd` (parchment map), `labels_view.gd` (names, settlements, roads), `overlay_view.gd` (armies, sieges, battle smoke), `battle_view.gd` (battle blocks and soldiers), `camera_rig.gd` (pan/zoom/pinch). |
| `ui/` | `hud.gd` — top bar, news feed, info panel, spawn prompt, chronicle. |
| `main.gd` | Wires it together and handles taps/selection. |

Tuning knobs are constants at the top of `sim/world.gd` (day length, terrain,
aggression, truces) and `sim/economy.gd` (yields, food, upkeep, taxes, recruit costs).

## Exporting to phones

In **Project → Export**, add the Android/iOS preset and under *Resources* set
**Filters to export non-resource files** to `data/*.json`, or the game won't find
its map data. iOS builds need a Mac with Xcode.

## Roadmap

1. ~~Layer 1 — Living map~~
2. ~~Layer 2 — Your realm~~
3. ~~Layer 3 — Battles~~
4. Layer 4 — Diplomacy, religion, crusades
5. Layer 5 — Dynasty & drama
6. Layer 6 — Polish & phone builds

Not yet: save/load, real province shapes, sound, art pass.
