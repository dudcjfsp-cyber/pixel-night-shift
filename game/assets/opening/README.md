# Opening art provenance

`title_background.png` and `city_network.png` are original assets generated for Pixel Night Shift with the built-in OpenAI image generation tool on 2026-07-22. No external source art, logos, characters, or reference-game images were supplied. The city panel used this project's generated title background only as a style and palette reference.

The built-in outputs were copied to the ignored `.godot/opening-art-sources/` working directory, then normalized by `res://tools/prepare_opening_art.gd`. The preparation step center-crops to the exact target aspect, downsamples to the documented visual grid, maps pixels to the project's 16-color opening palette, and enlarges by exactly 2x with nearest-neighbor filtering.

Prompts and final hashes are recorded in `opening_art_manifest.json`. Runtime code must reference the final PNGs in this directory, never the ignored source images.
