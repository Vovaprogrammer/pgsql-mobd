-- =============================================================================
-- Лабораторная работа №7. Итоговая схема базы данных маркетплейса
--
-- Единый DDL-скрипт итоговой схемы: таблицы с ограничениями и индексами
-- (ЛР 1, 5, 6), функции и триггеры (ЛР 5), представления (ЛР 3). Демонстрационных
-- запросов нет, они остались в скриптах своих работ.
--
-- Порядок сборки базы: create_database.sql (ЛР 1), затем в базе marketplace
-- этот скрипт, seed.sql (ЛР 2) и jsonb.sql (ЛР 6). Скрипт можно выполнять
-- повторно: сначала удаляет существующие объекты, затем создаёт схему заново.
-- Обоснование правил ON DELETE — в schema.sql ЛР 1.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Очистка (для повторного воспроизведения схемы с нуля)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS seller_revenue;
DROP VIEW IF EXISTS product_rating;

DROP TABLE IF EXISTS product_price_history CASCADE;
DROP TABLE IF EXISTS promo_usages CASCADE;
DROP TABLE IF EXISTS promo_codes CASCADE;
DROP TABLE IF EXISTS wishlist CASCADE;
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS deliveries CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS addresses CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS carts CASCADE;
DROP TABLE IF EXISTS stock CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- -----------------------------------------------------------------------------
-- users — учётные записи площадки
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  TEXT        NOT NULL,
    email      TEXT        NOT NULL UNIQUE,
    phone      TEXT,
    role       TEXT        NOT NULL DEFAULT 'customer'
                   CHECK (role IN ('customer', 'seller', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- sellers — магазины (правило 1: не более одного магазина на пользователя)
-- -----------------------------------------------------------------------------
CREATE TABLE sellers (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT      NOT NULL UNIQUE
                    REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    store_name  TEXT        NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- categories — иерархический классификатор (самоссылка, правило 4, 6)
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id BIGINT
                  REFERENCES categories(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    name      TEXT NOT NULL UNIQUE
);

CREATE INDEX idx_categories_parent ON categories(parent_id);

-- -----------------------------------------------------------------------------
-- products — карточки товаров (правило 3, 5). rating — средняя оценка,
-- поддерживается триггером (ЛР 5); attributes — характеристики, набор ключей
-- зависит от категории (ЛР 6).
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id   BIGINT         NOT NULL
                    REFERENCES sellers(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    category_id BIGINT         NOT NULL
                    REFERENCES categories(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    title       TEXT           NOT NULL,
    description TEXT,
    price       NUMERIC(12,2)  NOT NULL CHECK (price > 0),
    is_active   BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    rating      NUMERIC(3,2),
    attributes  JSONB
);

CREATE INDEX idx_products_seller   ON products(seller_id);
CREATE INDEX idx_products_category ON products(category_id);
-- ЛР 6: выборка самых дорогих товаров и фильтрация по характеристикам (@>)
CREATE INDEX idx_products_price      ON products(price);
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);

-- -----------------------------------------------------------------------------
-- product_price_history — журнал изменения цены товара (ЛР 5)
-- -----------------------------------------------------------------------------
CREATE TABLE product_price_history (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT        NOT NULL
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    old_price  NUMERIC(12,2) NOT NULL,
    new_price  NUMERIC(12,2) NOT NULL,
    changed_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- stock — складские остатки (правило 7; PK = FK, отношение 1:1 к товару)
-- -----------------------------------------------------------------------------
CREATE TABLE stock (
    product_id BIGINT      PRIMARY KEY
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    quantity   INTEGER     NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- carts — корзина (правило 9: не более одной активной корзины на пользователя)
-- -----------------------------------------------------------------------------
CREATE TABLE carts (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL UNIQUE
                   REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- cart_items — позиции корзины (ассоциативная таблица M:N carts <-> products)
-- -----------------------------------------------------------------------------
CREATE TABLE cart_items (
    cart_id    BIGINT  NOT NULL
                   REFERENCES carts(id) ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT  NOT NULL
                   REFERENCES products(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (cart_id, product_id)
);

-- -----------------------------------------------------------------------------
-- addresses — адреса пользователей
-- -----------------------------------------------------------------------------
CREATE TABLE addresses (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id   BIGINT NOT NULL
                  REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    city      TEXT   NOT NULL,
    street    TEXT   NOT NULL,
    house     TEXT   NOT NULL,
    apartment TEXT
);

CREATE INDEX idx_addresses_user ON addresses(user_id);

-- -----------------------------------------------------------------------------
-- orders — заказы (правило 10)
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT         NOT NULL
                     REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    status       TEXT           NOT NULL DEFAULT 'created'
                     CHECK (status IN ('created', 'paid', 'shipped', 'delivered', 'cancelled')),
    total_amount NUMERIC(12,2)  NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_user ON orders(user_id);
-- ЛР 6: частичный индекс для поиска покупателей с отменённым заказом
CREATE INDEX idx_orders_cancelled_user ON orders(user_id)
WHERE status = 'cancelled';

-- -----------------------------------------------------------------------------
-- order_items — позиции заказа (M:N orders <-> products; правило 11 — цена
-- фиксируется на момент покупки, поэтому unit_price хранится отдельно от
-- products.price)
-- -----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_id   BIGINT         NOT NULL
                   REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT         NOT NULL
                   REFERENCES products(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    quantity   INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2)  NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id)
);

-- -----------------------------------------------------------------------------
-- payments — оплата заказа (правило 16: 0..1 платёж на заказ)
-- -----------------------------------------------------------------------------
CREATE TABLE payments (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT         NOT NULL UNIQUE
                   REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    amount     NUMERIC(12,2)  NOT NULL CHECK (amount > 0),
    status     TEXT           NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
    paid_at    TIMESTAMPTZ
);

-- -----------------------------------------------------------------------------
-- deliveries — доставка заказа (правило 17: ровно один адрес)
-- -----------------------------------------------------------------------------
CREATE TABLE deliveries (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        BIGINT      NOT NULL UNIQUE
                        REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    address_id      BIGINT      NOT NULL
                        REFERENCES addresses(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    delivery_status TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (delivery_status IN ('pending', 'in_transit', 'delivered', 'cancelled')),
    delivery_date   TIMESTAMPTZ
);

CREATE INDEX idx_deliveries_address ON deliveries(address_id);

-- -----------------------------------------------------------------------------
-- reviews — отзывы (правило 18)
-- -----------------------------------------------------------------------------
CREATE TABLE reviews (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT      NOT NULL
                   REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT      NOT NULL
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    score      INTEGER     NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment    TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_reviews_product ON reviews(product_id);

-- -----------------------------------------------------------------------------
-- wishlist — избранное (M:N users <-> products; правило 8 — уникальная пара)
-- -----------------------------------------------------------------------------
CREATE TABLE wishlist (
    user_id    BIGINT      NOT NULL
                   REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    product_id BIGINT      NOT NULL
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);

-- -----------------------------------------------------------------------------
-- promo_codes — промокоды (общие; правило 12)
-- -----------------------------------------------------------------------------
CREATE TABLE promo_codes (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           TEXT           NOT NULL UNIQUE,
    discount_type  TEXT           NOT NULL CHECK (discount_type IN ('percent', 'fixed')),
    discount_value NUMERIC(12,2)  NOT NULL CHECK (discount_value > 0),
    usage_limit    INTEGER        CHECK (usage_limit IS NULL OR usage_limit > 0),
    valid_from     TIMESTAMPTZ    NOT NULL,
    valid_until    TIMESTAMPTZ    NOT NULL,
    is_active      BOOLEAN        NOT NULL DEFAULT TRUE,
    CHECK (valid_until > valid_from),
    CHECK (discount_type <> 'percent' OR discount_value <= 100)
);

-- -----------------------------------------------------------------------------
-- promo_usages — применения промокода к заказу
-- (M:N orders <-> promo_codes; правило 13 — не более одного промокода
-- на заказ, обеспечивается UNIQUE(order_id))
-- -----------------------------------------------------------------------------
CREATE TABLE promo_usages (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promo_id        BIGINT         NOT NULL
                        REFERENCES promo_codes(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    order_id        BIGINT         NOT NULL UNIQUE
                        REFERENCES orders(id) ON DELETE CASCADE ON UPDATE CASCADE,
    user_id         BIGINT         NOT NULL
                        REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE,
    discount_amount NUMERIC(12,2)  NOT NULL CHECK (discount_amount > 0),
    used_at         TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_promo_usages_promo ON promo_usages(promo_id);
CREATE INDEX idx_promo_usages_user  ON promo_usages(user_id);

-- -----------------------------------------------------------------------------
-- Функции (ЛР 5)
-- -----------------------------------------------------------------------------

-- Атомарное оформление заказа: p_product_ids[i] и p_quantities[i] — товар и
-- количество i-й позиции. При нехватке товара RAISE EXCEPTION откатывает все
-- изменения вызова.
CREATE OR REPLACE FUNCTION place_order(p_user_id     BIGINT,
                                       p_product_ids BIGINT[],
                                       p_quantities  INT[])
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_price    NUMERIC(12,2);
    v_stock    INT;
BEGIN
    INSERT INTO orders (user_id) VALUES (p_user_id) RETURNING id INTO v_order_id;

    FOR i IN 1 .. array_length(p_product_ids, 1) LOOP
        SELECT p.price, s.quantity INTO v_price, v_stock
        FROM products AS p
        JOIN stock    AS s ON s.product_id = p.id
        WHERE p.id = p_product_ids[i];

        IF v_stock < p_quantities[i] THEN
            RAISE EXCEPTION 'Недостаточно товара % на складе: остаток %, заказано %',
                p_product_ids[i], v_stock, p_quantities[i];
        END IF;

        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, p_product_ids[i], p_quantities[i], v_price);

        UPDATE stock SET quantity = quantity - p_quantities[i]
        WHERE product_id = p_product_ids[i];
    END LOOP;

    UPDATE orders
    SET total_amount = (SELECT SUM(quantity * unit_price)
                        FROM order_items
                        WHERE order_id = v_order_id)
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Выручка продавца за период с p_from по p_to включительно (без отменённых
-- заказов); 0, если продаж за период не было.
CREATE OR REPLACE FUNCTION seller_revenue_for_period(p_seller_id BIGINT,
                                                     p_from      DATE,
                                                     p_to        DATE)
RETURNS NUMERIC AS $$
DECLARE
    v_revenue NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0) INTO v_revenue
    FROM order_items AS oi
    JOIN orders      AS o ON o.id = oi.order_id
    JOIN products    AS p ON p.id = oi.product_id
    WHERE p.seller_id = p_seller_id
      AND o.status <> 'cancelled'
      AND o.created_at::date BETWEEN p_from AND p_to;

    RETURN v_revenue;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Триггеры (ЛР 5)
-- -----------------------------------------------------------------------------

-- Аудит изменения цены: старая и новая цена записываются в журнал.
CREATE OR REPLACE FUNCTION log_price_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO product_price_history (product_id, old_price, new_price)
    VALUES (NEW.id, OLD.price, NEW.price);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_price_change
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price <> NEW.price)
EXECUTE FUNCTION log_price_change();

-- Пересчёт products.rating товара, к которому добавлен отзыв. Срабатывает и
-- при наполнении базы seed.sql, поэтому начальное заполнение не нужно.
CREATE OR REPLACE FUNCTION refresh_product_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products
    SET rating = (SELECT ROUND(AVG(score), 2)
                  FROM reviews
                  WHERE product_id = NEW.product_id)
    WHERE id = NEW.product_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_rating
AFTER INSERT ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();

-- -----------------------------------------------------------------------------
-- Представления для типовых отчётов (ЛР 3)
-- -----------------------------------------------------------------------------

-- seller_revenue — выручка каждого продавца (без отменённых заказов)
CREATE VIEW seller_revenue AS
SELECT
    s.id                             AS seller_id,
    s.store_name,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM sellers AS s
JOIN products    AS p  ON p.seller_id = s.id
JOIN order_items AS oi ON oi.product_id = p.id
JOIN orders      AS o  ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY s.id, s.store_name;

-- product_rating — число отзывов и средняя оценка товара (товары без отзывов
-- тоже попадают: reviews_count = 0, avg_score = NULL)
CREATE VIEW product_rating AS
SELECT
    p.id                   AS product_id,
    p.title,
    c.name                 AS category,
    COUNT(r.id)            AS reviews_count,
    ROUND(AVG(r.score), 2) AS avg_score
FROM products AS p
JOIN categories   AS c ON c.id = p.category_id
LEFT JOIN reviews AS r ON r.product_id = p.id
GROUP BY p.id, p.title, c.name;
