# Jotra pixel art guide

This guide sets the visual direction for Jotra: colorful Nordic dark fantasy in detailed, readable pixel art. Use it to keep new assets coherent while preserving the project's existing technical scale.

## Scale and rendering

- Camera: top-down, with the existing slightly angled character and terrain art.
- World tile: 16 × 16 px (`WorldGen.TILE`). The game viewport is 640 × 360 and uses pixel snapping.
- Character sheet frame: 48 × 48 px; the visible body is about 28 px high and feet align near the frame bottom (`PlayerView`). The 32 px target is a useful visible-footprint goal, not the current frame size.
- Character directions: down, up, left, right. The current player sheet mirrors the right-facing frames for left.
- Animation: player walk cycle advances every 110 ms. Keep the feet at a stable ground point across frames.
- Texture filtering: nearest-neighbor (`rendering/textures/canvas_textures/default_texture_filter=0`); retain pixel snapping.
- Transparency: use transparent backgrounds for characters, props, and item sprites when the game composites them over the world.

## Style

- **Mood:** rugged, ancient, and a little eerie, with moments of warmth and wonder. The world should feel dangerous, not relentlessly bleak.
- **Pixel treatment:** hand-authored-looking pixel clusters, crisp edges, and enough small material detail to reward a closer look. Keep silhouettes and major color masses legible at normal gameplay zoom; avoid noisy one-pixel texture everywhere.
- **Palette:** use rich, earthy base colors—pine and moss greens, weathered wood browns, slate and blue-grey stone, muted soil—then bring scenes to life with clear accents such as amber firelight, berry reds, lichen, pale snow, and restrained magical cyan or violet. Let each biome have its own recognizable hue while sharing the same overall contrast and material treatment.
- **Brightness:** keep midtones present in forests and interiors. Use deep shadow selectively to frame focal areas and establish danger; don't put a dark overlay over the whole scene. Make night, caves, and haunted places darker through lighting and color shifts while keeping paths, characters, and interactable objects readable.
- **Lighting:** favor cool ambient shadows with localized warm light from fires, windows, lanterns, and spells. Keep light direction and shadow placement coherent within each scene. Use highlights to describe form, not as a glossy outline on every object.
- **Shapes and materials:** use sturdy, slightly exaggerated forms for people, buildings, tools, and props. Distinguish timber, rough stone, iron, cloth, fur, bone, and vegetation through their pixel patterns and value ranges. Build Nordic identity from carved wood, runes, longhouse forms, shields, ironwork, and cold-weather plants rather than relying on generic fantasy ornament.
- **Outlines:** prefer selective dark edging and interior value separation over a uniform black border. Keep the treatment consistent within an asset family; record deliberate exceptions in that family's source notes.
- The project currently combines separately licensed packs. Use a shared color and lighting direction for new work, but don't assume every existing pack has the same palette or outline treatment.
- Preserve the source generation or source pack, prompt/reference metadata when applicable, and license information. Keep candidate files separate from approved runtime assets until reviewed.
- Keep tall props as independently sortable objects where their canopy or structure must pass in front of a character.

## Art approval target

Before expanding the library, approve a small in-game sample containing one player, one enemy, a patch of forest floor, a stone or dirt path, a timber structure, and a warm light source. Check that the sample feels Nordic and atmospheric while staying colorful and readable at the game's normal zoom. Use it as the visual reference for later families.

## Review at game scale

Before approval, inspect silhouettes, stray/smoothed pixels, transparency, palette drift, character foot alignment and animation jumps, terrain seams, collision, and draw order in the actual camera. Automated checks can confirm file/layout constraints; they cannot approve the art.

## Asset naming and manifest

Use stable lowercase paths and describe each sheet in `assets/manifest.json`. Keep source files under `assets/source/` when the license allows their retention. Runtime assets should remain in their existing family directories unless there is a concrete reason to reorganize them.

## Validation

From the repository root, run `godot --headless --path game --script res://tools/validate_assets.gd` to check manifest paths, image dimensions, frame divisibility, alpha-channel presence, and references. Add candidate records before approval; the validator does not alter assets or decide visual quality.
