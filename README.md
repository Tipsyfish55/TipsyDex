# PlasmaDex

A searchable Pokédex drawer for KDE Plasma 6.0 and newer. Add the applet to a
panel and press its PlasmaDex button to open the drawer. It loads Pikachu when
opened and shows PokémonDB regular and shiny sprites, species type and
Pokédex description, color-coded type badges and damage defenses,
compact base-stat/EV/IV bars, and an evolution tree with matching Pokémon
sprites, level requirements, and item icons when available. The narrow drawer
includes type-ahead search suggestions as you enter a name and a Poké Ball
red, white, and black color scheme. The panel button uses a custom Poké Ball
icon, and the search field and suggestions display Pokémon sprites.

## Data and stat notes

Species, stats, and evolution requirements are loaded from the PokéAPI
(`pokeapi.co`), including defensive type matchups. The selected Pokémon's
regular and shiny sprites are loaded
from Pokémon Database (`img.pokemondb.net`); evolution sprites use the same
source, with PokéAPI sprites as a fallback, and item sprites come from the
PokéAPI sprites repository. An internet connection is
required. EV values are the yield for defeating that species, not EVs
belonging to an individual Pokémon. IVs are individual values and can range
from 0 to 31 per stat; the bars show that range rather than a fixed species
value.

## Install
NOTE: The org.example.pokedex.tar.gz file is the structured applet! extract it within your .local/share/plasma/plasmoids folder to install it!

Install the package with Plasma's package tool, then use **Add or Manage
Widgets** on a panel and add **PlasmaDex** from the widget chooser. Use the
panel button to open and close the drawer; do not add it to the desktop. If
an earlier broken copy is already on the panel, remove that instance and add
the applet again after installing.

```sh
kpackagetool6 --type Plasma/Applet --install .
```

For later updates to an installed package, use:

```sh
kpackagetool6 --type Plasma/Applet --upgrade .
```

The applet uses the Plasma 6 applet API and Qt 6. Reload Plasma Shell after
editing QML if it is already running.
