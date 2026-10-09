-- =============================================================================
-- Лабораторная работа №1. Проектирование и создание структуры базы данных
-- База данных маркетплейса (МОБД)
--
-- Скрипт идемпотентен относительно повторного запуска: сначала удаляет
-- существующие объекты (если есть), затем создаёт схему заново.
-- Порядок DROP/CREATE учитывает зависимости по внешним ключам.
--
-- Про ON DELETE у ссылок на users: удаление профиля каскадом затрагивает
-- только его "личные" данные без самостоятельной ценности (sellers, carts,
-- addresses, reviews, wishlist), но если у пользователя есть товары
-- (products.seller_id -> RESTRICT) или история доставок
-- (deliveries.address_id -> RESTRICT), каскад упрётся в RESTRICT дочерней
-- таблицы и транзакция завершится ошибкой. Это осознанное поведение, а не
-- недосмотр: система не должна тихо терять историю продаж или доставок при
-- удалении учётной записи. "Мягкое" удаление (is_deleted) в рамках лабы 1
-- не рассматривается — эта тема выходит за рамки её ТЗ.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Очистка (для повторного воспроизведения схемы с нуля)
-- -----------------------------------------------------------------------------
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
-- products — карточки товаров (правило 3, 5)
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
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_seller   ON products(seller_id);
CREATE INDEX idx_products_category ON products(category_id);

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
-- deliveries — доставка заказа (правило 17: ровно один адрес; то, что этот
-- адрес принадлежит именно покупателю заказа (orders.user_id), требует
-- сравнения значений из разных таблиц и декларативным FOREIGN KEY/CHECK не
-- выражается — проверяется серверной логикой в лабораторной работе №5,
-- аналогично правилам 14 и 19)
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
-- reviews — отзывы (правило 18; правило 19 проверяется в лабе №5 триггером)
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
-- на заказ, обеспечивается UNIQUE(order_id); правило 14 — лимит применений
-- проверяется серверной логикой в лабе №5, т.к. требует агрегации COUNT(*))
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
