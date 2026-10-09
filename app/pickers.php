<?php
declare(strict_types=1);

/**
 * The registry of what a form can pick (app/picker.php has the contract; the design-system reference record-picker.md).
 * One entry per record kind; `search` reuses the feature's own query, `label` names one record, `roles` gates the endpoint
 * like the screens that use the field, `params` are the only filter keys the endpoint forwards (integers).
 */
return [
    'supplier' => [
        'title' => 'Suppliers', 'noun' => 'supplier', 'roles' => ['receiving', 'production', 'sales'], 'params' => [],
        'search' => static function (PDO $pdo, string $q, array $params, int $page): array {
            require_once __DIR__ . '/features/suppliers/queries.php';
            $result = find_suppliers($pdo, $q, 'name', $page);
            $result['rows'] = array_map(static fn(array $s): array => [
                'id' => (int) $s['id'], 'label' => $s['name'],
                'detail' => implode(' · ', array_filter([SUPPLIER_KINDS[$s['kind']] ?? $s['kind'], $s['contact_name'], $s['email']])),
                'badge' => $s['active'] ? null : 'Inactive', 'color' => 'secondary',
            ], $result['rows']);
            return $result;
        },
        'label' => static function (PDO $pdo, int $id): ?string {
            require_once __DIR__ . '/features/suppliers/queries.php';
            return find_supplier($pdo, $id)['name'] ?? null;
        },
    ],
    'item' => [
        // Purchasable items; with supplier_id (the purchase order's) the supplier's listed items come first with their terms.
        'title' => 'Items', 'noun' => 'item', 'roles' => ['receiving', 'production'], 'params' => ['supplier_id'],
        'search' => static function (PDO $pdo, string $q, array $params, int $page): array {
            require_once __DIR__ . '/features/purchase-orders/queries.php';
            $result = find_purchasable_items($pdo, $q, $params['supplier_id'] ?? null, $page);
            $result['rows'] = array_map(static fn(array $i): array => [
                'id' => (int) $i['id'], 'label' => $i['code'] . ' — ' . $i['name'],
                'detail' => implode(' · ', array_filter([$i['class_name'], 'per ' . $i['base_unit_code'], $i['supplier_sku'] !== null ? 'SKU ' . $i['supplier_sku'] : null,
                    $i['last_price'] !== null ? '$' . number_format((float) $i['last_price'], 2) . ' / ' . $i['purchase_unit_code'] : null])),
                'badge' => $i['listed'] ? 'Listed' : null, 'color' => 'success',
            ], $result['rows']);
            return $result;
        },
        'label' => static function (PDO $pdo, int $id): ?string {
            require_once __DIR__ . '/features/items/queries.php';
            $item = find_item($pdo, $id);
            return $item === null ? null : $item['code'] . ' — ' . $item['name'];
        },
    ],
    'product' => [
        // Products that are not retired (what products_options() listed); retired=1 (the approvals form) includes them.
        'title' => 'Products', 'noun' => 'product', 'roles' => ['production', 'compliance', 'sales'], 'params' => ['retired'],
        'search' => static function (PDO $pdo, string $q, array $params, int $page): array {
            require_once __DIR__ . '/features/products/queries.php';
            $result = find_products($pdo, $q, null, 'name', $page);
            if (empty($params['retired'])) {
                $result = find_products_not_retired($pdo, $q, $page);
            }
            $result['rows'] = array_map(static fn(array $p): array => [
                'id' => (int) $p['id'], 'label' => $p['name'],
                'detail' => implode(' · ', array_filter([$p['code'], PRODUCT_BEVERAGES[$p['beverage_type']] ?? $p['beverage_type'], $p['style']])),
                'badge' => $p['status'] === 'active' ? null : (PRODUCT_STATUSES[$p['status']] ?? $p['status']), 'color' => $p['status'] === 'draft' ? 'dark' : 'secondary',
            ], $result['rows']);
            return $result;
        },
        'label' => static function (PDO $pdo, int $id): ?string {
            $statement = $pdo->prepare('SELECT name FROM app.products WHERE id = :id');
            $statement->execute(['id' => $id]);
            $name = $statement->fetchColumn();
            return $name === false ? null : (string) $name;
        },
    ],
    'product_cider' => [
        // Active cider products — what a batch or a blend is made as (batches_product_options()).
        'title' => 'Cider products', 'noun' => 'product', 'roles' => ['production'], 'params' => [],
        'search' => static function (PDO $pdo, string $q, array $params, int $page): array {
            require_once __DIR__ . '/features/products/queries.php';
            $result = find_products($pdo, $q, 'active', 'name', $page, 'cider');
            $result['rows'] = array_map(static fn(array $p): array => ['id' => (int) $p['id'], 'label' => $p['name'], 'detail' => implode(' · ', array_filter([$p['code'], $p['style']]))], $result['rows']);
            return $result;
        },
        'label' => static function (PDO $pdo, int $id): ?string {
            $statement = $pdo->prepare('SELECT name FROM app.products WHERE id = :id');
            $statement->execute(['id' => $id]);
            $name = $statement->fetchColumn();
            return $name === false ? null : (string) $name;
        },
    ],
    'customer' => [
        'title' => 'Customers', 'noun' => 'customer', 'roles' => ['compliance', 'production', 'sales'], 'params' => [],
        'search' => static function (PDO $pdo, string $q, array $params, int $page): array {
            require_once __DIR__ . '/features/customers/queries.php';
            $result = find_customers($pdo, $q, 'name', $page);
            $result['rows'] = array_map(static fn(array $c): array => [
                'id' => (int) $c['id'], 'label' => $c['name'],
                'detail' => implode(' · ', array_filter([CUSTOMER_KINDS[$c['kind']] ?? $c['kind'], $c['contact_name'], $c['email']])),
                'badge' => $c['active'] ? null : 'Inactive', 'color' => 'secondary',
            ], $result['rows']);
            return $result;
        },
        'label' => static function (PDO $pdo, int $id): ?string {
            require_once __DIR__ . '/features/customers/queries.php';
            return find_customer($pdo, $id)['name'] ?? null;
        },
    ],
];
