# Enhanced Loot

Clean pop-up bars for **looted items**, **money gained** and **experience gained**. No dependencies.

Each bar is a see-through black bar with a 1px border, the icon flush left, a quality-coloured name, and the vendor price in bronze with coin icons.
Items you couldn't loot (bags full, window closed early) show up as **dark red** bars.

Target client: **WoW Forever** live (1.60.x, `## Interface: 16001`). Works with any client language.

Author: **voidlol** ([github.com/voidlol](https://github.com/voidlol)) · License: [MIT](LICENSE)

## Install

Download a zip from [Releases](../../releases) and extract the `EnhancedLoot` folder into
`World of Warcraft/_forever_/Interface/AddOns/`. Restart the client the first time; after that, `/reload` picks up changes.

## Usage

`/el` opens the settings panel (also under *Options → AddOns → Enhanced Loot*). `/el help` lists all commands.

| Command | Effect |
|---|---|
| `/el test` | preview bars (loot, quest item, legendary, money, XP, unlooted) |
| `/el duration <sec>` | how long a bar stays (default 5) |
| `/el darkmode on\|off` / `/el lightmode on\|off` | black / white backdrop |
| `/el qualitybg on\|off` | tint green / blue / epic / legendary / quest item bars in their colour (default off) |
| `/el glow on\|off` | pulsing glow |
| `/el currency on\|off` / `/el experience on\|off` | show money / XP gains |
| `/el unlooted on\|off` | red bars for items left in the loot window (default on) |
| `/el rarity <0-6> on\|off` | item quality filter |
| `/el questmark on\|off` | quest "!" icon before quest items |
| `/el tooltips on\|off` | item tooltip on mouseover (off = bars stay click-through) |
| `/el font <name>` / `/el fontsize <n>` / `/el outline none\|outline\|thick` | text style (SharedMedia aware, `/el fonts`) |
| `/el scale <n>` / `/el width <n>` / `/el height <n>` | bar size |
| `/el maxbars <n>` / `/el growth up\|down` | stack size and direction |
| `/el unlock` / `/el lock` | drag the anchor to move the stack |
| `/el reset` | restore defaults |

Settings are saved in `EnhancedLootDB` (per account). The settings panel can't open in combat.

## Behaviour

| Kind | Trigger | Icon | Name | Right side |
|---|---|---|---|---|
| Loot | `CHAT_MSG_LOOT` (own loot) | item icon, bag count on it | quality colour + green `xN` | vendor price |
| Money | `PLAYER_MONEY` (gains) | coin pile, size by amount | `Coins` | amount with coin icons |
| XP | `CHAT_MSG_COMBAT_XP_GAIN` | XP icon | `Experience` | green `+N` |
| Unlooted | loot window closed with items left | item icon | quality colour + `xN`, dark red bar | vendor price |

- Repeated gains of the same item, money or XP kind merge into the existing bar and reset its timer.
- Quest items skip the quality filter and get Blizzard's quest "!" icon.
- **Own loot** is only counted from the client's own localized "You receive loot / item" templates
  (`LOOT_ITEM_SELF*`), so it works in every language. Group-roll lines ("You have selected Need for", "You won")
  never count, and the looter's GUID rules out other players' loot.
  Kill vs. quest XP is told apart with the localized `COMBATLOG_XPGAIN_FIRSTPERSON` template.
- **Unlooted items** are confirmed 1.5 s after the loot window closes, and only if the item neither appeared in the
  loot chat nor in your bags, so fast autoloot doesn't cause false alarms. Items that go to a group roll or the master
  looter (at or above the loot threshold, or a roll was started for them) are never reported, and re-opening the
  same corpse within 5 minutes doesn't repeat them.
- Hovering a loot or unlooted bar shows the item's tooltip with the cursor; turning tooltips off keeps the bars
  click-through, so they never eat clicks in combat.
- Borders are exactly one physical pixel; bar size and position snap to the pixel grid for your UI scale.

## Files

| File | Contents |
|---|---|
| `EnhancedLoot.toc` | addon manifest |
| `EnhancedLoot.lua` | bars, event handling, loot/XP parsing, slash commands |
| `Options.lua` | settings panel |

## Releasing

Releases are built by [BigWigsMods/packager](https://github.com/BigWigsMods/packager) on GitHub Actions
when a tag is pushed. `@project-version@` in the TOC is replaced with the tag.

```sh
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

The same run uploads the zip to [CurseForge](https://www.curseforge.com/) (project `1807543`, set by
`X-Curse-Project-ID` in the TOC) using the `CF_API_TOKEN` repository secret. Wago works the same way with
`WAGO_API_TOKEN` and an `X-Wago-ID` line. WoWInterface has no Forever category.
