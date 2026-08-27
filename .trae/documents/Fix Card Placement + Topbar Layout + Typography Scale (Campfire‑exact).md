## Assumptions
- Follow Campfire layout: navigation on the left within the header; the “What’s included” card sits on the right, visually starting at page top, in front of (over) the header layer. If you intended nav to the right of the card, I’ll invert the grid, but I’ll implement the reference alignment first.

## Header/Card Layout
- Create a header grid container that reserves a right slot for the card:
  - Topbar wrapper: `fixed top-0 left-0 right-0 z-[50] bg-card/80 backdrop-blur-sm border-b`.
  - Inner container: `max-w-6xl mx-auto h-[var(--topbar-h)] px-4 md:px-6 grid grid-cols-[1fr_380px] items-center gap-6`.
  - Left cell: logo + nav + theme toggle + auth button.
  - Right cell: empty (reserved).
- Place the card as an overlay aligned to the reserved slot:
  - Card element (moved from Hero to Header) with `fixed z-[60] top-0 right-[calc((100vw-1152px)/2)] w-[380px] rounded-2xl border bg-card p-6 shadow`.
  - Mobile: `hidden`.
- Reserve space on the page content so text never flows beneath the card:
  - Apply `lg:pr-[420px]` on main content sections (already added) and keep consistent.

## Show/Hide Animation & Visibility
- Keep IntersectionObserver on `#plans`:
  - When `#plans` visible → add `campfire-card-out` (opacity 0, translateY 8px, pointer-events none).
  - Otherwise → `campfire-card-in` (opacity 1, translateY 0). Duration 180ms ease‑out.
- Maintain full hide on mobile (`hidden lg:block`).

## Typography Scale (30% increase)
- Introduce a site-wide class for Campfire pages: `.campfire-body`.
- Rules:
  - `:root --para-scale: 1.3;`.
  - `.campfire-body p { font-size: calc(1rem * var(--para-scale)); line-height: 1.65; }`.
  - Clamp for large screens: `font-size: clamp(1.3rem, 1.15vw, 1.4rem)` to follow reference feel.
- Apply `.campfire-body` to `HeroCampfire`, `LetterCard`, and all section wrappers.

## Headings Consistency (hero, h2, h3)
- Hero slogan: `text-6xl md:text-7xl font-extrabold tracking-tight`.
- Section `h2`: `text-5xl md:text-6xl font-bold`.
- Section `h3`: `text-3xl md:text-4xl font-bold`.
- Ensure consistent margins: `mt-3` for paragraph after heading; `mt-6` between blocks.

## File‑level Changes
- `src/components/campfire/Topbar.tsx`:
  - Convert inner layout to grid with right slot width 380px.
  - Expose `--topbar-h` (e.g., 76px) and align header height.
- `src/components/campfire/HeroCampfire.tsx`:
  - Remove card from Hero and move it to a new `HeaderCard` component inside the header.
  - Keep `lg:pr-[420px]` on hero grid.
  - Keep IntersectionObserver logic at page level (or lift to `HomePage` and pass state down) to toggle card classes.
- `src/components/campfire/HeaderCard.tsx` (new):
  - The fixed, animated card overlay with visibility logic props.
- `src/styles/tokens-campfire.css`:
  - Add variables: `--topbar-h`, `--para-scale`.
  - Add `.campfire-body p` rule and `campfire-card-in/out` classes.

## Verification
- Desktop: card starts at page top at the same visual Y as reference and aligns to container right; nav sits to the left; text sections never overlap the card.
- Mobile: card hidden; text sizes increased per rule; headings consistent.
- Plans visibility hides the card with a subtle animation.

## Next Step
- Implement header grid + overlay card, move card from hero to header, apply paragraph scaling and heading sizes, and validate pixel alignment. If you prefer nav on the right of the card, I’ll flip grid columns after we confirm the initial fit.