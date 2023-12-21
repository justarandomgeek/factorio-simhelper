
# Sim Helper

Sim Helper contains libraries to assist in creating simulations.

## Mod Loader

`modloader` is a wrapper to allow running a mostly-unmodified `control.lua` from a mod as an `event_handler` library inside `level`. This is useful because simulations do not load mods, however there is a good chance you need your mod to be loaded for the simulation to work, so it runs in `level` instead.

For a more detailed explanation see [here](modloader.md).

