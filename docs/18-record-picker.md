# The record picker (2026-10-09)

The owner's decision (the builder plugin 0.8.0, `design-system/references/record-picker.md`; the plan in the plugin's
`docs/record-picker-plan.md`): a form chooses a **record** — a supplier, an item, a product, a customer, anything a person adds
rows to without limit — through one searchable modal, never a `<select>` that lists every row. ProcessCore's purchase order was
the exemplar; the cidery is the first retrofit, mechanical from the plugin's reference.

- **Added:** `app/picker.php`, `app/pickers.php` (sources `supplier`, `item` with the order's `supplier_id` — the supplier's listed
  items first with SKU and last price —, `product` (not retired; `retired=1` for the approvals form), `product_cider` (active cider
  products, what a batch or a blend is made as), `customer`), `html/pick/index.php`, `app/views/shared/picker-rows.php`,
  `assets/js/record-picker.js`, the RECORD PICKER section of `app-overrides.css`, the `#record-picker` modal and the script in
  `layout.php` (the unsaved-changes guard admits a picker's hidden value), `form_picker()` in `app/ui.php`,
  `find_purchasable_items()` and `find_products_not_retired()`.
- **Converted (the hidden input keeps each select's name and id, so no handler, `hx-include`, smoke or manifest row changed):**
  the purchase order's supplier and the line's item (the inline New supplier panel kept and reachable from the picker); the product
  of a production order, a batch and a blend (`product_cider`, what `production_product_options()` and `batches_product_options()` listed),
  of a packaging configuration and an approval (`product`); the customer of a removal and of a keg return.
- **Still selects, by the rule (D7):** premises, vessels, stages, units, reasons, statuses, kinds — configuration lists. **Owed:**
  the lot choices (`array_map` labels filtered by premises and state — a dependent source each) and the vessel choices if a site
  grows past a handful; both go through the same registry.
- **Proven:** `scripts/prove-picker.sh` on a scratch copy (`cidery_dev`; the live install's `config/.env` names the live database
  and the proof refuses it): the endpoint's refusals, search, escaping, paging, the dependent param, every converted form rendering
  its picker, the 422 keeping the label, a purchase order saved through the hidden inputs.
