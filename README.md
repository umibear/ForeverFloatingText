# Forever Floating Text

Floating combat text for **WoW: Forever** that shows only your own numbers.

In groups and dungeons the game hides who hit what. This addon works it out from your own
Combat Log lines and the timing of your swings and casts, so other players' hits don't show up
as yours.

## What it shows

- Your damage and misses over the enemy's nameplate, in spell school colors, crits bigger, or
  all in one scrolling area if you prefer (Damage options)
- Your heals, heal-over-time ticks included
- Damage and heals you take, with who healed you on direct heals
- Mana, rage and energy you gain (Mana Spring Totem, potions)
- Alerts: Windfury, your dispels, cooldowns ready, your target's emotes, entering and leaving combat
  (killing blows if you want them)
- Buffs and debuffs you gain, at their own position (fades and your own totems' buffs if you want
  them; `/fft hide <buff>` leaves one out)
- Procs that stay on screen until you use them: the game's own proc notices ("Maelstrom Ready!"),
  spells it lights up ("Clearcasting!"), reactive abilities while you can use them (Overpower, Revenge,
  Execute, Riposte, Counterattack, Hammer of Wrath...), Stormstrike reset
- Items and money you loot, items in their quality color
- Experience, honor, reputation, skill gains and currency, with your loot
- Health / Mana Low with the procs, kept while they last (crowd control on you too, if you want it:
  the game shows it already); icons where the spell or item is known

Keep enemy nameplates on, even with the scrolling area: the game reports hits on an enemy
through its nameplate. With them off only your current target's damage can show (at the
scrolling area's position).

Blizzard's own floating numbers are hidden while a feature replaces them, and come back when
you turn it off. Every logout puts your own settings back, so they're yours again if you remove
the addon. Only the Combat Log stays on the addon's filter: pick another on its tab.

## Install

1. Download the latest `ForeverFloatingText-….zip` from
   [Releases](https://github.com/umibear/ForeverFloatingText/releases) (not GitHub's green
   "Code" button: its folder name won't load in the game).
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so you get
   `AddOns\ForeverFloatingText\ForeverFloatingText.toc`.
3. Start the game and type `/reload` once. The addon sets up its own Combat Log filter on
   reload or logout.

## Commands

| Command | What it does |
|---|---|
| `/fft` | Options |
| `/fft test` | Sample numbers at every position |
| `/fft move` | Show the six fixed positions (damage and healing, incoming and resources, alerts, buffs, procs, loot and gains) to drag them |
| `/fft lock` | Lock them all again (or click Lock all, or right-click any box) |
| `/fft hide <buff>`, `/fft unhide <buff>` | Leave a buff out of the buffs position, or bring it back; `/fft hide` lists them |
| `/fft on`, `/fft off` | Turn the addon on or off |
| `/fft status` | What the addon is using right now |
| `/fft clog` | Combat Log state; turns its messages back on |
| `/fft heals` | Learned heal-over-time and damage-over-time rhythms |
| `/fft forget` | Forget the learned rhythms and swing delays |
| `/fft cvars` | Blizzard's combat text settings and their defaults |
| `/fft reset` | Put Blizzard's combat text settings back to their defaults |
| `/fft debug` | Start or stop recording a debug log |
| `/fft copy` | Show the debug log to copy |
| `/fft clearlog` | Empty the saved debug log |

## Reporting a problem

Type `/fft debug`, play until it happens, type `/reload`, and send
`WTF\Account\<your account>\SavedVariables\ForeverFloatingText.lua`.
The log has your character's name in a few lines.

## License

MIT, see [LICENSE](LICENSE).
