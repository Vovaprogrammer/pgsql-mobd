# Словарь данных — база данных маркетплейса

Словарь данных ко всем 16 таблицам схемы, реализованной в `schema.sql`
(лабораторная работа №1). Для каждой таблицы перечислены столбцы, их типы,
ограничения и назначение.

### users

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор пользователя |
| full_name | TEXT | NOT NULL | имя пользователя |
| email | TEXT | NOT NULL, UNIQUE | email, уникален (правило 2) |
| phone | TEXT | — | телефон |
| role | TEXT | NOT NULL, CHECK IN (customer, seller, admin), DEFAULT 'customer' | роль в системе |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата регистрации |

### sellers

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор магазина |
| user_id | BIGINT | NOT NULL, UNIQUE, FK → users(id) ON DELETE CASCADE | владелец магазина (правило 1: не более одного на пользователя) |
| store_name | TEXT | NOT NULL | название магазина |
| description | TEXT | — | описание магазина |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата создания магазина |

### categories

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор категории |
| parent_id | BIGINT | FK → categories(id) ON DELETE RESTRICT | родительская категория (самоссылка, правило 4) |
| name | TEXT | NOT NULL, UNIQUE | название категории (правило 6) |

### products

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор товара |
| seller_id | BIGINT | NOT NULL, FK → sellers(id) ON DELETE RESTRICT | продавец товара (правило 3) |
| category_id | BIGINT | NOT NULL, FK → categories(id) ON DELETE RESTRICT | категория товара (правило 3) |
| title | TEXT | NOT NULL | название товара |
| description | TEXT | — | описание товара |
| price | NUMERIC(12,2) | NOT NULL, CHECK > 0 | цена (правило 5) |
| is_active | BOOLEAN | NOT NULL, DEFAULT TRUE | доступен ли товар к продаже |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата добавления товара |

### stock

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| product_id | BIGINT | PK, FK → products(id) ON DELETE CASCADE | товар (PK = FK, отношение 1:1) |
| quantity | INTEGER | NOT NULL, CHECK >= 0, DEFAULT 0 | остаток на складе (правило 7) |
| updated_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата последнего обновления остатка |

### carts

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор корзины |
| user_id | BIGINT | NOT NULL, UNIQUE, FK → users(id) ON DELETE CASCADE | владелец корзины (правило 9: не более одной активной) |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата создания корзины |

### cart_items

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| cart_id | BIGINT | PK (часть составного), FK → carts(id) ON DELETE CASCADE | корзина |
| product_id | BIGINT | PK (часть составного), FK → products(id) ON DELETE RESTRICT | товар в корзине |
| quantity | INTEGER | NOT NULL, CHECK > 0 | количество товара в корзине |

### addresses

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор адреса |
| user_id | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | владелец адреса |
| city | TEXT | NOT NULL | город |
| street | TEXT | NOT NULL | улица |
| house | TEXT | NOT NULL | дом |
| apartment | TEXT | — | квартира |

### orders

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор заказа |
| user_id | BIGINT | NOT NULL, FK → users(id) ON DELETE RESTRICT | покупатель (правило 10) |
| status | TEXT | NOT NULL, CHECK IN (created, paid, shipped, delivered, cancelled), DEFAULT 'created' | статус заказа |
| total_amount | NUMERIC(12,2) | NOT NULL, CHECK >= 0, DEFAULT 0 | итоговая сумма заказа |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата оформления заказа |

### order_items

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| order_id | BIGINT | PK (часть составного), FK → orders(id) ON DELETE CASCADE | заказ |
| product_id | BIGINT | PK (часть составного), FK → products(id) ON DELETE RESTRICT | товар в заказе |
| quantity | INTEGER | NOT NULL, CHECK > 0 | количество товара в позиции |
| unit_price | NUMERIC(12,2) | NOT NULL, CHECK > 0 | цена на момент покупки (правило 11) |

### payments

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор платежа |
| order_id | BIGINT | NOT NULL, UNIQUE, FK → orders(id) ON DELETE CASCADE | оплачиваемый заказ (правило 16: 0..1 на заказ) |
| amount | NUMERIC(12,2) | NOT NULL, CHECK > 0 | сумма платежа |
| status | TEXT | NOT NULL, CHECK IN (pending, succeeded, failed, refunded), DEFAULT 'pending' | статус платежа |
| paid_at | TIMESTAMPTZ | — | дата фактической оплаты |

### deliveries

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор доставки |
| order_id | BIGINT | NOT NULL, UNIQUE, FK → orders(id) ON DELETE CASCADE | доставляемый заказ |
| address_id | BIGINT | NOT NULL, FK → addresses(id) ON DELETE RESTRICT | адрес доставки (правило 17) |
| delivery_status | TEXT | NOT NULL, CHECK IN (pending, in_transit, delivered, cancelled), DEFAULT 'pending' | статус доставки |
| delivery_date | TIMESTAMPTZ | — | дата доставки |

### reviews

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор отзыва |
| user_id | BIGINT | NOT NULL, FK → users(id) ON DELETE CASCADE | автор отзыва (правило 18) |
| product_id | BIGINT | NOT NULL, FK → products(id) ON DELETE CASCADE | товар отзыва (правило 18) |
| score | INTEGER | NOT NULL, CHECK BETWEEN 1 AND 5 | оценка |
| comment | TEXT | — | текст отзыва |
| created_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата отзыва |

### wishlist

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| user_id | BIGINT | PK (часть составного), FK → users(id) ON DELETE CASCADE | пользователь |
| product_id | BIGINT | PK (часть составного), FK → products(id) ON DELETE CASCADE | избранный товар |
| added_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата добавления в избранное (правило 8: пара уникальна как PK) |

### promo_codes

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор промокода |
| code | TEXT | NOT NULL, UNIQUE | код промокода |
| discount_type | TEXT | NOT NULL, CHECK IN (percent, fixed) | тип скидки |
| discount_value | NUMERIC(12,2) | NOT NULL, CHECK > 0, CHECK <= 100 при percent | величина скидки |
| usage_limit | INTEGER | CHECK > 0 или NULL | максимум применений (NULL = без лимита) |
| valid_from | TIMESTAMPTZ | NOT NULL, CHECK < valid_until | начало действия |
| valid_until | TIMESTAMPTZ | NOT NULL | окончание действия (правило 12) |
| is_active | BOOLEAN | NOT NULL, DEFAULT TRUE | активен ли промокод |

### promo_usages

| Столбец | Тип | Ограничения | Назначение |
|---|---|---|---|
| id | BIGINT | PK, IDENTITY | идентификатор применения |
| promo_id | BIGINT | NOT NULL, FK → promo_codes(id) ON DELETE RESTRICT | применённый промокод |
| order_id | BIGINT | NOT NULL, UNIQUE, FK → orders(id) ON DELETE CASCADE | заказ (правило 13: не более одного промокода на заказ) |
| user_id | BIGINT | NOT NULL, FK → users(id) ON DELETE RESTRICT | пользователь, применивший промокод |
| discount_amount | NUMERIC(12,2) | NOT NULL, CHECK > 0 | сумма скидки, зафиксированная на момент применения (правило 15) |
| used_at | TIMESTAMPTZ | NOT NULL, DEFAULT now() | дата применения |

