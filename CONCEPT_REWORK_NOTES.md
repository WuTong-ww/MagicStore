# Concept rework package

This package rebuilds the UI shell around the newly generated concept art direction.

## What changed
- Added generated concept references:
  - `assets/frontdesk_concept_reference.png`
  - `assets/ui/concept_button_sheet.png`
- Reworked the shared midnight theme into a translucent gold-on-teal style.
- Updated the front desk UI so the scene is no longer just a static illustration:
  - clickable in-scene hotspots for 店外 / 原料商店 / 储物柜 / 咨询区 / 工坊 / 来客信件
  - front desk and guest panel use transparent concept-style buttons
- Kept all original gameplay scripts and data structure intact.

## Main edited files
- `themes/midnight.tres`
- `scripts/ui/ui_kit.gd`
- `scripts/ui/shop_front.gd`
