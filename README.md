# RangeIndicator

A World of Warcraft addon for the **Forever** client (Interface 16001). It shows the estimated range to your target and which PvP "zone" you're in relative to it.

## Color legend

The distance number is colored by zone:

| Color | Meaning |
|---|---|
| Red | In melee range, they can hit you |
| Yellow | On a boundary (step back or closer) |
| Teal | Hunter dead zone (5-8 yd), a hunter can't hit you |
| Orange | A hunter can shoot you (8-41 yd) |
| Green | Out of melee and out of hunter range |
| White | Friendly target |
| Grey | Range unknown |

The range is a "min - max" estimate from spell, item and interact-distance checks. In combat, the game blocks item checks on enemies, so the estimate can get coarser. `/ri info` shows which distances can be measured right now.

## Commands

| Command | Does |
|---|---|
| `/ri lock` / `/ri unlock` | Lock the display, or unlock it so you can drag it |
| `/ri scale <0.5-3>` | Resize |
| `/ri colors` | Print the color legend |
| `/ri info` | List the distances that can be measured right now |
| `/ri reset` | Reset position and scale |

## Install

Copy the `RangeIndicator` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game or `/reload`.

## Libraries

Bundled under `Libs/`:

- [LibStub](https://www.wowace.com/projects/libstub): public domain
- [CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler): BSD
- [LibRangeCheck-3.0](https://github.com/WoWUIDev/LibRangeCheck-3.0): MIT. This bundled copy is patched for the Forever client.

## License

MIT. See [LICENSE](LICENSE).

## Contact

- Bugs and feature requests: open an issue on this repository.
- Anything else, including work enquiries: [d1verseti.gg@gmail.com](mailto:d1verseti.gg@gmail.com)
