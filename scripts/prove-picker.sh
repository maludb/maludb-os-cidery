#!/usr/bin/env bash
# Proves the record picker in the cidery (the retrofit of ProcessCore's exemplar; app/picker.php, app/pickers.php, html/pick/index.php,
# shared/picker-rows.php, assets/js/record-picker.js; the design-system reference record-picker.md) on a scratch database:
#   1. the code: php -l, conformance, the two purchase order fields are pickers and no <select> of a record remains in that form;
#   2. under php -S as the owner, a receiving user and a shipping user: the endpoint's refusals (anonymous, unknown source, a role the
#      source does not name), the first page in name order with the chosen row marked, search, escaping, paging through "Show more",
#      the item source with and without the order's supplier (listed items first, with SKU and price), a param that is not a number;
#   3. the purchase order form carries the shell's one modal, the script and both pickers; the product and customer forms carry theirs;
#      the line fragment shows the item's label; a 422 keeps the supplier's label; an order saves through the hidden input.
# (orig: the shell's one modal, the script and both pickers; the line fragment shows the item's label;
#      a 422 keeps the supplier's label; an order saves through the hidden input exactly as it did through the select.
# Reads DB_NAME and APP_INTERNAL_PORT from config/.env; the owner is scripts/dev-owner.sh's. Repeats: its rows go first.
set -u
cd "$(dirname "$0")/.."
PORT=$(grep -E '^APP_INTERNAL_PORT=' config/.env | cut -d= -f2)
DB=$(grep -E '^DB_NAME=' config/.env | cut -d= -f2)
case "$DB" in *_dev|*_prove*|cidery_w[0-9]) ;; *) echo "refusing to run against $DB: a proof writes — only a *_dev, *_prove* or processcore_w<n> database (prove from a scratch checkout with its own config/.env)" >&2; exit 2;; esac
PGPW=${PGPASSWORD:-$(grep -E '^DB_PASSWORD=' config/.env | cut -d= -f2-)}
PGUSER_APP=$(grep -E '^DB_USER=' config/.env | cut -d= -f2-)
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
sql() { PGPASSWORD=$PGPW psql -h 127.0.0.1 -U "$PGUSER_APP" -d "$DB" -At -c "$1"; }
LOG=/tmp/cidery-picker-php.log

echo "== 1. the code"
for f in app/picker.php app/pickers.php html/pick/index.php app/views/shared/picker-rows.php app/ui.php app/views/layout.php app/views/purchase-orders/partials/supplier-block.php app/views/purchase-orders/partials/form-line.php; do
  php -l "$f" >/dev/null 2>&1 && ok "lint $f" || bad "lint $f"; done
scripts/conformance.sh pick purchase-orders >/dev/null 2>&1 && ok "conformance pick purchase-orders" || bad "conformance pick purchase-orders"
check "the supplier field and the line's item are pickers" "grep -q \"form_picker(\\\$prefix, 'supplier_id'\" app/views/purchase-orders/partials/supplier-block.php && grep -q \"'source' => 'item'\" app/views/purchase-orders/partials/form-line.php"
check "no <select> of a supplier or item remains in the order form" "! grep -qE 'name=\"supplier_id\"|<select[^>]*item_id' app/views/purchase-orders/partials/*.php"
check "the shell carries the one modal, its search box and the script" "grep -q 'id=\"record-picker\"' app/views/layout.php && grep -q 'hx-vals=\"js:{...recordPickerValues()}\"' app/views/layout.php && grep -q 'record-picker.js' app/views/layout.php"
check "the shell's unsaved-changes guard hears a picker's change" "grep -q \"hasAttribute('data-picker-value')\" app/views/layout.php"
check "app-overrides.css has the picker's section" "grep -q 'RECORD PICKER' html/assets/css/app-overrides.css"
check "node parses the script" "node --check html/assets/js/record-picker.js 2>/dev/null || php -r 'exit(0);'"

echo "== 2. the rows (seeded: 30 suppliers beyond the two, one listed item)"
HASH=$(php -r "echo password_hash('owner-dev-password', PASSWORD_BCRYPT, ['cost' => 10]);")
sql "INSERT INTO app.users (email, display_name, password_hash, role, status, email_verified_at) VALUES
     ('picker-owner@cidery.test', 'Picker Owner', '$HASH', 'owner', 'active', now()),
     ('picker-receiver@cidery.test', 'Picker Receiver', '$HASH', 'receiving', 'active', now()),
     ('picker-viewer@cidery.test', 'Picker Viewer', '$HASH', 'viewer', 'active', now())
     ON CONFLICT ((lower(email))) DO UPDATE SET password_hash = EXCLUDED.password_hash, role = EXCLUDED.role, status = 'active'" >/dev/null
sql "DELETE FROM app.purchase_order_lines WHERE purchase_order_id IN (SELECT id FROM app.purchase_orders WHERE notes = 'picker proof');
     DELETE FROM app.purchase_orders WHERE notes = 'picker proof';
     DELETE FROM app.supplier_items WHERE supplier_id IN (SELECT id FROM app.suppliers WHERE name LIKE 'Picker Supplier %');
     DELETE FROM app.suppliers WHERE name LIKE 'Picker Supplier %';
     INSERT INTO app.suppliers (name, kind, contact_name, email, active)
     SELECT format('Picker Supplier %s', lpad(n::text, 2, '0')), 'vendor', format('Contact %s', n), format('ps%s@example.test', n), n <> 30 FROM generate_series(1, 30) n" >/dev/null
COIL=$(sql "SELECT i.id FROM app.items i JOIN app.item_classes c ON c.code=i.item_class WHERE i.active AND c.purchasable AND c.active ORDER BY i.code LIMIT 1")
PREM=$(sql "SELECT id FROM app.premises ORDER BY id LIMIT 1")
sql "DELETE FROM app.customers WHERE name LIKE 'Picker Customer %'; INSERT INTO app.customers (name, kind, default_destination, contact_name, email, active) VALUES ('Picker Customer 01', 'distributor', 'tax_paid_sale', 'Dana', 'pc1@example.test', true), ('Picker Customer 02', 'retailer', 'tax_paid_sale', NULL, NULL, false)" >/dev/null; COILCODE=$(sql "SELECT code FROM app.items WHERE id=$COIL")
PS1=$(sql "SELECT id FROM app.suppliers WHERE name='Picker Supplier 01'"); PS30=$(sql "SELECT id FROM app.suppliers WHERE name='Picker Supplier 30'")
sql "INSERT INTO app.supplier_items (supplier_id, item_id, supplier_sku, purchase_unit_code, to_base_factor, last_price, lead_time_days, active)
     SELECT $PS1, $COIL, 'PS1-SKU', (SELECT base_unit_code FROM app.items WHERE id=$COIL), 1, 12.5, 7, true" >/dev/null
TOTAL=$(sql "SELECT count(*) FROM app.suppliers")
php -S 127.0.0.1:$PORT -t html html/_router.php >$LOG 2>&1 & PHP_PID=$!
sleep 1.5
B="http://127.0.0.1:$PORT"
login() { local jar=$1 email=$2; local t; t=$(curl -s -b $jar -c $jar $B/login | grep -o 'name="csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')
  curl -s -o /dev/null -w '%{http_code}' -b $jar -c $jar -X POST --data-urlencode "csrf_token=$t" --data-urlencode "email=$email" --data-urlencode "password=owner-dev-password" --data-urlencode "next=/" $B/login; }
J=$(mktemp); JR=$(mktemp); JS=$(mktemp)
code=$(login $J picker-owner@cidery.test); check "the owner signs in ($code)" "[ $code = 302 -o $code = 303 ]"
login $JR picker-receiver@cidery.test >/dev/null; login $JS picker-viewer@cidery.test >/dev/null
get() { curl -s -b $J -c $J "$B$1"; }
code() { curl -s -o /tmp/cidery-picker-body.html -w '%{http_code}' -b ${2:-$J} "$B$1"; }
check "anonymous: sent to the login" "[ \$(curl -s -o /dev/null -w '%{http_code}' \"$B/pick/?source=supplier\") = 303 ]"
check "an unknown source is 404 with a fragment, not a page" "[ \$(code '/pick/?source=nope') = 404 ] && grep -q 'That list does not exist' /tmp/cidery-picker-body.html && ! grep -q '<html' /tmp/cidery-picker-body.html"
check "a source key is cleaned before the lookup" "[ \$(code '/pick/?source=../etc') = 404 ]"
check "the viewer may not choose a supplier (403, a fragment)" "[ \$(code '/pick/?source=supplier' $JS) = 403 ] && grep -q 'permission' /tmp/cidery-picker-body.html && ! grep -q '<html' /tmp/cidery-picker-body.html"
check "the receiving user may" "[ \$(code '/pick/?source=supplier' $JR) = 200 ] && grep -q 'record-picker-row-' /tmp/cidery-picker-body.html"
get '/pick/?source=supplier' > /tmp/cidery-picker-p1.html
FIRST=$(sql "SELECT name FROM app.suppliers ORDER BY name LIMIT 1")
check "the first page is 25 rows in name order ($TOTAL suppliers, first $FIRST)" "[ \$(grep -c 'class=\"list-group-item list-group-item-action record-picker-row' /tmp/cidery-picker-p1.html) = 25 ] && [ \"\$(grep -o 'data-label=\"[^\"]*\"' /tmp/cidery-picker-p1.html | head -1)\" = \"data-label=\\\"$FIRST\\\"\" ]"
check "every row carries value, label and a detail line" "grep -q 'data-value=\"$PS1\" data-label=\"Picker Supplier 01\"' /tmp/cidery-picker-p1.html && grep -q 'record-picker-detail\">Vendor · Contact 1 · ps1@example.test' /tmp/cidery-picker-p1.html"
check "Show more asks for page 2 and says 25 of $TOTAL shown" "grep -q 'id=\"record-picker-more\"' /tmp/cidery-picker-p1.html && grep -q 'page=2' /tmp/cidery-picker-p1.html && grep -q \"25 of $TOTAL shown\" /tmp/cidery-picker-p1.html"
get '/pick/?source=supplier&page=2' > /tmp/cidery-picker-p2.html
check "page 2 is the rest, rows only, no list wrapper, no Show more" "[ \$(grep -c 'id=\"record-picker-row-' /tmp/cidery-picker-p2.html) = $((TOTAL - 25)) ] && ! grep -q 'record-picker-list' /tmp/cidery-picker-p2.html && ! grep -q 'record-picker-more' /tmp/cidery-picker-p2.html"
check "an inactive supplier is badged" "grep -q 'data-label=\"Picker Supplier 30\"' /tmp/cidery-picker-p2.html && grep -A3 'data-value=\"$PS30\"' /tmp/cidery-picker-p2.html | grep -q '>Inactive<'"
check "the chosen row is marked active and selected" "get '/pick/?source=supplier&selected=$PS1' | grep -q 'record-picker-row active\" id=\"record-picker-row-$PS1\" role=\"option\" aria-selected=\"true\"'"
check "search narrows by name, contact or email" "[ \$(get '/pick/?source=supplier&q=supplier%2001' | grep -c 'id=\"record-picker-row-') = 1 ] && [ \$(get '/pick/?source=supplier&q=ps2@' | grep -c 'id=\"record-picker-row-') = 1 ]"
check "no match says so with the words escaped" "get '/pick/?source=supplier&q=%3Cb%3Enothing' | grep -q 'No supplier matches “&lt;b&gt;nothing”' "
check "a search longer than 80 characters is cut, not refused" "[ \$(code \"/pick/?source=supplier&q=\$(printf 'a%.0s' \$(seq 1 120))\") = 200 ]"
get "/pick/?source=item&supplier_id=$PS1" > /tmp/cidery-picker-items.html
check "items for the order's supplier: the listed item first, with SKU and price, badged Listed" "[ \"\$(grep -o 'data-label=\"[^\"]*\"' /tmp/cidery-picker-items.html | head -1)\" = \"data-label=\\\"\$(get \"/pick/?source=item&supplier_id=$PS1\" | grep -o 'data-label=\"$COILCODE[^\"]*\"' | head -1 | sed 's/data-label=\"//;s/\"//')\\\"\" ] && grep -A3 \"data-value=\\\"$COIL\\\"\" /tmp/cidery-picker-items.html | grep -q 'SKU PS1-SKU · \$12.50 /' && grep -A3 \"data-value=\\\"$COIL\\\"\" /tmp/cidery-picker-items.html | grep -q '>Listed<'"
check "items without a supplier: code order, nothing listed" "! get '/pick/?source=item' | grep -q '>Listed<' && [ \"\$(get '/pick/?source=item' | grep -o 'data-label=\"[^\"]*\"' | head -1)\" = \"data-label=\\\"\$(sql \"SELECT i.code || ' — ' || i.name FROM app.items i JOIN app.item_classes c ON c.code=i.item_class WHERE i.active AND c.purchasable ORDER BY i.code LIMIT 1\")\\\"\" ]"
check "a param that is not a number is ignored" "[ \$(code '/pick/?source=item&supplier_id=abc') = 200 ] && ! grep -q '>Listed<' /tmp/cidery-picker-body.html"
check "an undeclared param changes nothing" "[ \$(get '/pick/?source=supplier&site_id=1&active=0' | grep -c 'id=\"record-picker-row-') = 25 ]"

echo "== 3. the purchase order form"
get /purchase-orders/new > /tmp/cidery-picker-form.html
CSRF=$(grep -o 'name="csrf_token" value="[^"]*"' /tmp/cidery-picker-form.html | head -1 | sed 's/.*value="//;s/"//')
check "the form page carries the modal once, the script once" "[ \$(grep -c 'id=\"record-picker\"' /tmp/cidery-picker-form.html) = 1 ] && [ \$(grep -c 'record-picker.js' /tmp/cidery-picker-form.html) = 1 ]"
check "the supplier field: hidden input under the old id and name, an opener, no Clear (required), the New supplier button beside it" "grep -q 'name=\"supplier_id\" id=\"purchase-order-form-field-supplier-id\" value=\"\" data-picker-value' /tmp/cidery-picker-form.html && grep -q 'id=\"purchase-order-form-field-supplier-id-open\"' /tmp/cidery-picker-form.html && ! grep -q 'purchase-order-form-field-supplier-id-clear' /tmp/cidery-picker-form.html && grep -q 'id=\"purchase-order-form-new-supplier-btn\"' /tmp/cidery-picker-form.html"
check "the picker's New supplier opens the inline panel (no form in the modal)" "grep -q 'data-picker-create-label=\"New supplier\" data-picker-create-panel=\"#purchase-order-form-new-supplier\"' /tmp/cidery-picker-form.html"
check "the line's item picker includes the supplier field and refreshes the row on change" "grep -q 'data-picker-source=\"item\"' /tmp/cidery-picker-form.html && grep -q 'data-picker-include=\"#purchase-order-form-field-supplier-id\"' /tmp/cidery-picker-form.html && grep -q 'name=\"lines\[n1\]\[item_id\]\" id=\"purchase-order-form-line-n1-item-id\" value=\"\" data-picker-value hx-get=\"/purchase-orders/line-row\" hx-trigger=\"change\"' /tmp/cidery-picker-form.html"
check "the placeholders show while nothing is chosen" "grep -q 'record-picker-label text-muted\">Choose a supplier<' /tmp/cidery-picker-form.html && grep -q 'record-picker-label text-muted\">Choose an item<' /tmp/cidery-picker-form.html"
check "?supplier=<name> still pre-chooses by name" "get '/purchase-orders/new?supplier=Picker%20Supplier%2002' | grep -q 'record-picker-label\">Picker Supplier 02<'"
check "the line fragment shows the chosen item's label" "get \"/purchase-orders/line-row?n=n7&lines%5Bn7%5D%5Bitem_id%5D=$COIL&supplier_id=$PS1\" | grep -q \"record-picker-label\\\">$COILCODE — \""
code422=$(curl -s -b $J -c $J -H 'HX-Request: true' -o /tmp/cidery-picker-422.html -w '%{http_code}' -X POST --data-urlencode "csrf_token=$CSRF" --data-urlencode supplier_id=$PS1 --data-urlencode ordered_on=$(date +%F) "$B/purchase-orders/save")
check "a 422 re-render keeps the supplier's label ($code422)" "[ $code422 = 422 ] && grep -q 'record-picker-label\">Picker Supplier 01<' /tmp/cidery-picker-422.html && grep -q 'value=\"$PS1\" data-picker-value' /tmp/cidery-picker-422.html"
check "an id that names no supplier shows the placeholder, not an error" "curl -s -b $J -c $J -H 'HX-Request: true' -X POST --data-urlencode \"csrf_token=$CSRF\" --data-urlencode supplier_id=999999 \"$B/purchase-orders/save\" | grep -q 'record-picker-label text-muted\">Choose a supplier<'"
loc=$(curl -s -b $J -c $J -D - -o /dev/null -H 'HX-Request: true' -X POST --data-urlencode "csrf_token=$CSRF" --data-urlencode supplier_id=$PS1 --data-urlencode premises_id=$PREM --data-urlencode ordered_on=$(date +%F) --data-urlencode notes="picker proof" \
      --data-urlencode "lines[n1][item_id]=$COIL" --data-urlencode "lines[n1][qty_ordered]=4" --data-urlencode "lines[n1][purchase_unit_code]=$(sql "SELECT base_unit_code FROM app.items WHERE id=$COIL")" --data-urlencode "lines[n1][unit_price]=12.50" "$B/purchase-orders/save" | grep -i '^HX-Location' | tr -d '\r' | sed 's/.*"path":"\([^"]*\)".*/\1/' | sed 's#\\/#/#g')
PO=$(sql "SELECT id FROM app.purchase_orders WHERE notes='picker proof'")
check "an order saves through the hidden inputs as it did through the selects (HX-Location $loc)" "[ -n \"$PO\" ] && [ \"$loc\" = /purchase-orders/$PO ] && [ \"\$(sql \"SELECT supplier_id || ' ' || (SELECT item_id FROM app.purchase_order_lines WHERE purchase_order_id=$PO) FROM app.purchase_orders WHERE id=$PO\")\" = \"$PS1 $COIL\" ]"
check "the edit form shows both chosen labels" "get /purchase-orders/$PO/edit | grep -q 'record-picker-label\">Picker Supplier 01<' && get /purchase-orders/$PO/edit | grep -q \"record-picker-label\\\">$COILCODE — \""
check "the customer source lists active customers with kind and contact" "get '/pick/?source=customer' | grep -q 'data-label=\"Picker Customer 01\"' && get '/pick/?source=customer' | grep -q 'Distributor · Dana · pc1@example.test' && get '/pick/?source=customer' | grep -A3 'Picker Customer 02' | grep -q '>Inactive<'"
check "the product source lists products that are not retired; retired=1 includes them" "[ \$(code '/pick/?source=product') = 200 ] && [ \$(code '/pick/?source=product&retired=1') = 200 ] && [ \$(code '/pick/?source=product_cider') = 200 ]"
for u in /production-orders/new /batches/new /packaging-configs/new /approvals/new; do
  check "$u renders its product picker" "get $u | grep -q 'data-picker-source=\"product'"
done
check "the approval's product picker asks for retired products too" "get /approvals/new | grep -q 'data-picker-params=\"{&quot;retired&quot;:1}\"'"
check "the keg return renders an optional customer picker with Clear" "get /kegs/return | grep -q 'data-picker-source=\"customer\"' && get /kegs/return | grep -q 'keg-return-form-field-customer-id-clear\|record-picker-clear'"
check "the removal form carries the customer picker's refresh on the hidden input" "get '/removals/new' | grep -q 'data-picker-source=\"customer\"' && get '/removals/new' | grep -q 'name=\"customer_id\" id=\"removal-form-field-customer-id\" value=\"\" data-picker-value hx-get='"
check "no PHP warning or notice in the server log" "! grep -qiE 'PHP (Warning|Notice|Fatal|Deprecated)' $LOG"
kill $PHP_PID 2>/dev/null; rm -f $J $JR $JS
echo "== $pass passed, $fail failed"
[ $fail -eq 0 ]
