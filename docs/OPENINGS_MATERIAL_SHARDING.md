# Openings Material Sharding

This document describes how `Bookmoves.Openings.MaterialShard` maps a FEN position to
`material_shard_id` for the openings import/lookup pipeline.

## Goals

- Keep locality for branch traversal: if material does not change, nearby positions keep the same
  material signature.
- Make shard assignment deterministic from position state (no game/session dependence).
- Improve partition spread compared with simple `rem(material_key, 32_768)`.
- Keep mapping fast enough for the import hot path.

## Current Mapping

Implementation source: `lib/bookmoves/openings/material_shard.ex`.

### 1) Build `material_key` (19 bits)

The key packs capped piece counts (`0..7`) and side to move:

- bits `16..18`: white queens
- bits `13..15`: black queens
- bits `10..12`: white rooks
- bits `7..9`: black rooks
- bits `4..6`: white minors (bishops + knights)
- bits `1..3`: black minors (bishops + knights)
- bit `0`: side to move (`w = 0`, `b = 1`)

Notes:

- Kings and pawns are intentionally ignored in this material signature.
- Counts are clamped to 3 bits (`>= 7` becomes `7`).

### 2) Mix into 15-bit shard id

Shard domain is fixed at `0..32767` (`2^15`):

```elixir
folded = bxor(material_key &&& 0x7fff, material_key >>> 15)
mixed = folded * 20_273 + 13_849
material_shard_id = bxor(mixed, mixed >>> 9) &&& 0x7fff
```

This keeps mapping deterministic and cheap while spreading hot keys better than low-bit truncation.

## Why `20_273` and `13_849`

- They are odd, which is important for affine mixing over modulo `2^15`.
- The pair was chosen empirically as a low-cost option that reduced observed partition skew vs.
  plain `rem(material_key, 32_768)`.
- They are not chess-domain constants; they are mixer constants and can be re-tuned.

## Practical Properties

- **Deterministic**: same board material + side always yields the same shard id.
- **Branch locality preserved**: traversing moves where material stays unchanged keeps shard stable.
- **Lookup simplicity**: FEN lookup remains a single-shard equality on `material_shard_id`.

## Operational Notes

- Import and lookup must always use the same mapping version.
- Any mapping change requires rebuilding imported openings data.
- Use `mix openings.partition_skew` to monitor partition skew after imports.

Examples:

```bash
mix openings.partition_skew --limit 64 --include-empty
mix openings.partition_skew --order-by bytes
```
