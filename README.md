# Enhanced Loot

Standalone WoW addon that replaces the **Enhanced_Loot** WeakAura (`wago.io/UihWPxSyL`). No WeakAuras required.

It shows short-lived bars for **looted items**, **money gained** and **experience gained**, styled after the original aura:
a see-through black bar with a black border, the icon flush left, a quality-coloured name, and the vendor price in bronze with coin icons.

Target client: **WoW Forever** live (1.60.x, `## Interface: 16001`).

Author: **voidlol** ([github.com/voidlol](https://github.com/voidlol))

## Install

Download a zip from [Releases](../../releases) and extract the `EnhancedLoot` folder into
`World of Warcraft/_forever_/Interface/AddOns/`. Restart the client the first time; after that, `/reload` picks up changes.

## Usage

`/el` opens the settings panel (also under *Options → AddOns → Enhanced Loot*). `/el help` lists all commands.

| Command | Effect |
|---|---|
| `/el test` | preview bars (loot, quest item, money, XP) |
| `/el duration <sec>` | how long a bar stays (default 5) |
| `/el darkmode on\|off` / `/el lightmode on\|off` | black / white backdrop |
| `/el glow on\|off` | pulsing glow |
| `/el currency on\|off` / `/el experience on\|off` | show money / XP gains |
| `/el rarity <0-6> on\|off` | item quality filter |
| `/el questmark on\|off` | quest "!" icon before quest items |
| `/el font <name>` / `/el fontsize <n>` / `/el outline none\|outline\|thick` | text style (SharedMedia aware, `/el fonts`) |
| `/el scale <n>` / `/el width <n>` / `/el height <n>` | bar size |
| `/el maxbars <n>` / `/el growth up\|down` | stack size and direction |
| `/el unlock` / `/el lock` | drag the anchor to move the stack |
| `/el reset` | restore defaults |

Settings are saved in `EnhancedLootDB` (per account).

## Behaviour

| Kind | Trigger | Icon | Name | Right side |
|---|---|---|---|---|
| Loot | `CHAT_MSG_LOOT` (own loot) | item icon, bag count on it | quality colour + green `xN` | vendor price |
| Money | `PLAYER_MONEY` (gains) | coin pile, size by amount | `Coins` | amount with coin icons |
| XP | `CHAT_MSG_COMBAT_XP_GAIN` | XP icon | `Experience` (purple) | green `+N` |

Repeated gains of the same item, money or XP kind merge into the existing bar and reset its timer.
Quest items skip the quality filter and get Blizzard's quest "!" icon.

## Releasing

Releases are built by [BigWigsMods/packager](https://github.com/BigWigsMods/packager) on GitHub Actions
when a tag is pushed. `@project-version@` in the TOC is replaced with the tag.

```sh
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

The workflow needs *Settings → Actions → General → Workflow permissions* set to **Read and write**.
To also upload to CurseForge, WoWInterface or Wago, add `CF_API_KEY`, `WOWI_API_TOKEN` or `WAGO_API_TOKEN` as repository secrets.
