## Goal
Replace the current checkout CTA that uses the `Button` component with a semantic `<a>` styled as a button (matching the pattern from the Campfire example), inside the existing layout.

## Changes
1. In `frontend/src/components/campfire/HeaderCard.tsx`, replace the `Button` in the checkout section with an `<a>` element styled as a button.
2. Preserve the current `href` logic: `selected ? /checkout/<id-or-identifier> : /plans`.
3. Remove the `Button` import since it will no longer be used.
4. Ensure accessibility: add `aria-label` to the link and keep keyboard focus styles via the existing `btn` class.
5. Keep the surrounding layout (`mt-6` wrapper) and dark/light theme compatibility.

## Implementation Snippet
```tsx
// Before (lines 87–90)
<div className="mt-6">
  <a href={selected ? `/checkout/${encodeURIComponent(selected.identifier || selected.id)}` : '/plans'}>
    <Button variant="uiverse" className="w-full h-11 text-sm">Baixar o código</Button>
  </a>
</div>

// After
<div className="mt-6">
  <a
    href={selected ? `/checkout/${encodeURIComponent(selected.identifier || selected.id)}` : '/plans'}
    className="btn w-full h-11 text-sm"
    aria-label="Baixar o código"
  >
    <span>Baixar o código</span>
  </a>
</div>
```

## Validation
- Run the frontend dev server, navigate to the page, verify the CTA renders with the same visual weight as the prior button, and confirm navigation works for both selected and fallback cases.
- Check focus behavior and dark/light themes.

## Notes
- We will not add the external `buy__button` class since the project uses Tailwind + a `btn` utility class; this keeps styling consistent with the rest of the app.
- If desired, we can also fix the `Entrar` CTA (currently an `<a>` wrapping a `<button>`) in a follow-up to avoid invalid nested interactive elements.