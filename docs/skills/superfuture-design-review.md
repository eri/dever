# design-review (superfuture)

Source: Figma Community skill "superfuture-design-review" by Joey Primiani
(https://www.figma.com/community/skill/65434/superfuture-design-review, from crit.officialjp.com).
Copied here because the page cannot be fetched without a browser. Use it as a critique rubric for
Dever screens: evaluate, report ranked findings with concrete fixes, then apply the safe ones.

A senior-level craft critique. Opinionated and specific, not a generic checklist dump.

## 1. Evaluate against the rubric

Check actual numbers where possible (contrast ratios, line-heights, measure in ch, tap-target px,
animation durations) rather than vibes.

### Visual hierarchy & layout
- One clear focal point; obvious primary action. Eye knows where to go first.
- Scan path follows importance (size, weight, color, position).
- Related items grouped (proximity); unrelated items separated. Gestalt holds up.
- Everything aligns to a grid / shared edges; no near-but-not-quite alignments.
- Whitespace used as structure, not leftover. Generous around focal elements.

### Typography
- Limited type scale (≈5–7 steps), each step clearly distinct (≥ ~1.2 ratio).
- Line-height: tighter for display (1.0–1.2), ~1.4–1.6 for body.
- Measure ~45–75 characters for body text.
- Display text tightened letter-spacing; small labels slightly loose.
- ≤2 typefaces. Consistent weights.
- No widows/orphans on headlines; numerals tabular where aligning.

### Spacing & rhythm
- Consistent spacing scale (4/8px steps); no arbitrary 13px/27px gaps.
- Vertical rhythm consistent between sections; symmetric padding.
- Density appropriate to content.

### Color & contrast
- WCAG AA: body text ≥ 4.5:1; large text and UI/icons ≥ 3:1.
- Never rely on color alone (add icon/label/shape).
- Restrained palette; accent used sparingly for emphasis/CTAs.
- Disabled/placeholder readable without reading as active.

### Motion
- Purposeful, not decoration that delays.
- UI transitions ~150–250ms; larger/entrance ~300–500ms.
- Ease-out for enters, ease-in for exits; avoid linear.
- Honors reduced motion. No layout shift or jank.

### Component states
- Every interactive element has hover, focus-visible, active, and disabled states.
- Visible focus ring.
- Loading, empty, and error states designed.
- Tap targets ≥ 44×44 (touch) with adequate spacing.
- Primary vs secondary clearly differentiated.

### Accessibility
- Semantic structure; ARIA only to fill gaps.
- Images have meaningful alt; icons have labels.
- Inputs have labels; errors announced and linked.
- Full keyboard operability; logical focus order; visible focus.
- Supports zoom/200% and reduced motion.

### Responsiveness
- Fluid type/spacing or sensible breakpoints; nothing clipped or overlapping.

### Content & copy
- Headlines clear and specific; jargon-free.
- CTA labels describe the action.
- Microcopy guides; no misleading states.

### Consistency & brand
- Design tokens reused; consistent radii, elevation, icon stroke.
- Matches the product's visual language across screens.

## 2. Report: ranked, concrete, scannable

Group findings by severity, most important first. Lead with the few that matter. For each:
- **What**: the specific issue (name the exact element).
- **Why**: the craft or usability reason (one line).
- **Fix**: a concrete change (exact value, not "increase spacing").

Severity: 🔴 Blocking (broken, inaccessible, fails WCAG AA) · 🟠 Important (hurts hierarchy,
readability, usability, consistency) · 🟡 Polish.

End with **Strengths** (2–4 things done well) and the single highest-leverage change to make first.

## 3. Apply fixes

Make the changes for the clear, safe findings (contrast, spacing, focus states, reduced motion,
semantics, alt text). Leave subjective or restructuring changes as recommendations unless confirmed.
Re-verify values after editing.

## Tone

Direct and respectful, like reviewing a colleague's work: precise, never vague, always paired with
the fix. Calibrate depth to the surface.
