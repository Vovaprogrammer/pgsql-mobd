-- =============================================================================
-- Лабораторная работа №2. Наполнение базы данных marketplace тестовыми данными
--
-- Запускать после schema.sql (ЛР 1), подключившись к базе marketplace.
-- Скрипт можно выполнять повторно: сначала таблицы очищаются, затем данные
-- генерируются заново.
--
-- Приём, на котором построен скрипт: каждая таблица наполняется командой
--     INSERT INTO ... SELECT ... FROM generate_series(1, N) AS g;
-- где g — номер строки. Из g формулами (остаток от деления %, массивы
-- ARRAY[...][индекс], random()) получаются значения столбцов.
--
-- Так как таблицы очищаются с RESTART IDENTITY, идентификаторы в каждой
-- таблице идут подряд с 1. Поэтому внешние ключи можно считать арифметически
-- (например, user_id = 50 + g), не выбирая значения подзапросами.
--
-- Состав пользователей: id 1..40 — продавцы, 41..50 — администраторы,
-- 51..1200 — покупатели (1150 человек).
-- Даты подобраны так, чтобы порядок событий был правдоподобным:
-- регистрация (500-730 дней назад) -> товар (380-480 дней назад) ->
-- заказы (за последние 365 дней).
-- =============================================================================

BEGIN;

-- фиксируем генератор случайных чисел, чтобы данные были повторяемыми
SELECT setseed(0.42);

-- очистка всех таблиц и сброс счётчиков идентификаторов
TRUNCATE TABLE
    promo_usages, promo_codes, wishlist, reviews, deliveries, payments,
    order_items, orders, addresses, cart_items, carts, stock, products,
    categories, sellers, users
RESTART IDENTITY CASCADE;

-- -----------------------------------------------------------------------------
-- users: 1200 пользователей. Пол определяется чётностью номера, чтобы имя
-- и фамилия согласовались (Иванов / Иванова). У ~20% телефон не указан (NULL).
-- -----------------------------------------------------------------------------
INSERT INTO users (full_name, email, phone, role, created_at)
SELECT
    CASE WHEN g % 2 = 0
         THEN (ARRAY['Анна','Мария','Елена','Ольга','Наталья','Татьяна',
                     'Екатерина','Ирина','Софья','Дарья'])[1 + floor(random() * 10)::int]
         ELSE (ARRAY['Иван','Алексей','Дмитрий','Сергей','Андрей','Михаил',
                     'Николай','Артём','Максим','Егор'])[1 + floor(random() * 10)::int]
    END
    || ' ' ||
    (ARRAY['Иванов','Петров','Смирнов','Кузнецов','Попов','Соколов','Лебедев',
           'Козлов','Новиков','Морозов','Волков','Фёдоров','Михайлов',
           'Беляев','Орлов'])[1 + floor(random() * 15)::int]
    || CASE WHEN g % 2 = 0 THEN 'а' ELSE '' END,
    'user' || g || '@' || (ARRAY['mail.ru','yandex.ru','gmail.com'])[1 + g % 3],
    CASE WHEN random() < 0.2 THEN NULL
         ELSE '+79' || lpad(floor(random() * 1000000000)::bigint::text, 9, '0')
    END,
    CASE WHEN g <= 40 THEN 'seller'
         WHEN g <= 50 THEN 'admin'
         ELSE 'customer'
    END,
    now() - (500 + random() * 230) * interval '1 day'
FROM generate_series(1, 1200) AS g;

-- -----------------------------------------------------------------------------
-- sellers: магазины для пользователей 1..40 (у каждого четвёртого нет описания)
-- -----------------------------------------------------------------------------
INSERT INTO sellers (user_id, store_name, description, created_at)
SELECT g,
       (ARRAY['ТехноМир','ДомАрт','СпортЛайн','КнигаПлюс','ЭлитСтиль',
              'ЗелёныйДвор','Мегастор','ЛавкаМастера'])[1 + g % 8] || ' ' || g,
       CASE WHEN g % 4 = 0 THEN NULL
            ELSE 'Официальный магазин, быстрая отправка и гарантия на товары'
       END,
       now() - (480 + random() * 18) * interval '1 day'
FROM generate_series(1, 40) AS g;

-- -----------------------------------------------------------------------------
-- categories: дерево из трёх уровней (parent_id ссылается на id той же таблицы).
-- Первые 6 строк — корневые категории (parent_id = NULL), их id равны 1..6.
-- -----------------------------------------------------------------------------
INSERT INTO categories (parent_id, name) VALUES
    (NULL, 'Электроника'),              -- 1
    (NULL, 'Книги'),                    -- 2
    (NULL, 'Одежда'),                   -- 3
    (NULL, 'Дом и сад'),                -- 4
    (NULL, 'Спорт и отдых'),            -- 5
    (NULL, 'Красота и здоровье'),       -- 6
    (1, 'Смартфоны'),                   -- 7
    (1, 'Ноутбуки'),                    -- 8
    (1, 'Наушники'),                    -- 9
    (1, 'Телевизоры'),                  -- 10
    (2, 'Художественная литература'),   -- 11
    (2, 'Научная литература'),          -- 12
    (2, 'Детские книги'),               -- 13
    (3, 'Мужская одежда'),              -- 14
    (3, 'Женская одежда'),              -- 15
    (3, 'Обувь'),                       -- 16
    (4, 'Мебель'),                      -- 17
    (4, 'Посуда'),                      -- 18
    (4, 'Садовый инвентарь'),           -- 19
    (5, 'Велосипеды'),                  -- 20
    (5, 'Туризм'),                      -- 21
    (5, 'Фитнес'),                      -- 22
    (6, 'Косметика'),                   -- 23
    (6, 'Парфюмерия'),                  -- 24
    (6, 'Уход за волосами'),            -- 25
    (8, 'Игровые ноутбуки'),            -- 26 (потомок категории «Ноутбуки»)
    (9, 'Беспроводные наушники');       -- 27 (потомок категории «Наушники»)

-- -----------------------------------------------------------------------------
-- products: 3000 товаров в категориях 7..27 (по кругу: 7 + g % 21).
-- Название типа товара и ориентировочная цена берутся из массивов по тому же
-- индексу, поэтому они всегда соответствуют категории.
-- Цена = ориентировочная * случайный множитель (0.5..2.0), округлена до 10 руб.
-- -----------------------------------------------------------------------------
INSERT INTO products (seller_id, category_id, title, description, price, is_active, created_at)
SELECT
    1 + g % 40,
    7 + g % 21,
    (ARRAY['Смартфон','Ноутбук','Наушники','Телевизор','Роман','Учебник',
           'Сборник сказок','Мужская рубашка','Женское платье','Кроссовки',
           'Диван','Набор посуды','Лопата','Велосипед','Палатка','Гантели',
           'Крем для лица','Туалетная вода','Шампунь','Игровой ноутбук',
           'Беспроводные наушники'])[1 + g % 21]
    || ' ' ||
    (ARRAY['Aurora','Nordis','Volna','Kristal','Zenit','Orbita','Tandem',
           'Lumen'])[1 + (g / 3) % 8]
    || ' ' || chr(65 + g % 26) || '-' || (100 + g * 37 % 900),
    CASE WHEN random() < 0.25 THEN NULL
         ELSE 'Качественный товар с гарантией производителя'
    END,
    GREATEST(10, round(
        (ARRAY[25000,60000,3000,40000,500,1200,400,2500,3500,6000,30000,2500,
               700,25000,8000,2000,800,3500,400,110000,6000])[1 + g % 21]
        * (0.5 + 1.5 * random()) / 10) * 10)::numeric(12,2),
    random() < 0.92,
    now() - (380 + random() * 100) * interval '1 day'
FROM generate_series(1, 3000) AS g;

-- -----------------------------------------------------------------------------
-- stock: остаток для каждого товара (product_id = g); у ~10% товаров остаток 0
-- -----------------------------------------------------------------------------
INSERT INTO stock (product_id, quantity, updated_at)
SELECT g,
       CASE WHEN random() < 0.1 THEN 0 ELSE floor(random() * 200)::int END,
       now() - random() * 30 * interval '1 day'
FROM generate_series(1, 3000) AS g;

-- -----------------------------------------------------------------------------
-- addresses: по 2 адреса у каждого из 1150 покупателей.
-- Адреса 1..1150 — первые адреса покупателей 51..1200 (адрес g принадлежит
-- пользователю 50 + g), адреса 1151..2300 — вторые. Квартира иногда не указана.
-- -----------------------------------------------------------------------------
INSERT INTO addresses (user_id, city, street, house, apartment)
SELECT 51 + (g - 1) % 1150,
       (ARRAY['Москва','Санкт-Петербург','Казань','Новосибирск','Екатеринбург',
              'Нижний Новгород','Самара','Ростов-на-Дону'])[1 + floor(random() * 8)::int],
       (ARRAY['ул. Ленина','ул. Гагарина','пр. Мира','ул. Советская','ул. Пушкина',
              'ул. Садовая','пр. Победы','ул. Центральная','ул. Новая',
              'ул. Школьная'])[1 + floor(random() * 10)::int],
       (1 + floor(random() * 150))::int::text,
       CASE WHEN random() < 0.3 THEN NULL
            ELSE (1 + floor(random() * 300))::int::text
       END
FROM generate_series(1, 2300) AS g;

-- -----------------------------------------------------------------------------
-- carts: корзины у покупателей 51..450 (по одной на пользователя)
-- -----------------------------------------------------------------------------
INSERT INTO carts (user_id, created_at)
SELECT 50 + g,
       now() - random() * 30 * interval '1 day'
FROM generate_series(1, 400) AS g;

-- -----------------------------------------------------------------------------
-- cart_items: по 3 товара в каждой корзине. Две серии (c — корзины, k — номер
-- позиции) дают все сочетания; формула product_id даёт разные товары для
-- разных k, поэтому пара (cart_id, product_id) не повторяется.
-- -----------------------------------------------------------------------------
INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT c,
       1 + (c * 7 + k * 1001) % 3000,
       1 + floor(random() * 3)::int
FROM generate_series(1, 400) AS c
CROSS JOIN generate_series(1, 3) AS k;

-- -----------------------------------------------------------------------------
-- promo_codes: 15 промокодов (процентные и фиксированные, с лимитом и без;
-- часть уже истекла, один ещё не начал действовать, один отключён)
-- -----------------------------------------------------------------------------
INSERT INTO promo_codes (code, discount_type, discount_value, usage_limit, valid_from, valid_until, is_active) VALUES
    ('WELCOME10',     'percent',   10, NULL, now() - interval '500 days', now() + interval '365 days', TRUE),
    ('SALE15',        'percent',   15,  500, now() - interval '300 days', now() +  interval '30 days', TRUE),
    ('SUMMER20',      'percent',   20,  300, now() - interval '400 days', now() - interval '200 days', TRUE),
    ('FIX500',        'fixed',    500,  400, now() - interval '365 days', now() + interval '200 days', TRUE),
    ('FIX1000',       'fixed',   1000,  100, now() - interval '200 days', now() + interval '100 days', TRUE),
    ('VIP25',         'percent',   25,   50, now() - interval '100 days', now() + interval '100 days', TRUE),
    ('BLACKFRIDAY30', 'percent',   30,  200, now() - interval '340 days', now() - interval '320 days', TRUE),
    ('NEWYEAR5',      'percent',    5, NULL, now() - interval '250 days', now() - interval '230 days', TRUE),
    ('OLD2024',       'percent',   10, NULL, now() - interval '700 days', now() - interval '400 days', TRUE),
    ('DISABLED50',    'percent',   50, NULL, now() - interval '300 days', now() + interval '300 days', FALSE),
    ('FIX200',        'fixed',    200, NULL, now() - interval '365 days', now() + interval '365 days', TRUE),
    ('FIX3000',       'fixed',   3000,   30, now() - interval '150 days', now() +  interval '60 days', TRUE),
    ('SPRING7',       'percent',    7, 1000, now() - interval '180 days', now() - interval '100 days', TRUE),
    ('FUTURE10',      'percent',   10, NULL, now() + interval '10 days',  now() + interval '100 days', TRUE),
    ('APP12',         'percent',   12, NULL, now() - interval '365 days', now() + interval '180 days', TRUE);

-- -----------------------------------------------------------------------------
-- orders: 5000 заказов. Покупатели по кругу (51..1200). Статус определяется
-- остатком от деления номера на 20: по 5% created, paid, shipped, cancelled
-- и 80% delivered. Итоговая сумма пока 0 — она считается ниже по позициям.
-- -----------------------------------------------------------------------------
INSERT INTO orders (user_id, status, created_at)
SELECT 51 + (g - 1) % 1150,
       CASE g % 20 WHEN 0 THEN 'created'
                   WHEN 1 THEN 'paid'
                   WHEN 2 THEN 'shipped'
                   WHEN 3 THEN 'cancelled'
                   ELSE 'delivered'
       END,
       now() - random() * 365 * interval '1 day'
FROM generate_series(1, 5000) AS g;

-- -----------------------------------------------------------------------------
-- order_items: в заказе g от 1 до 4 разных товаров (1 + g % 4 позиций).
-- unit_price — цена на момент покупки: она немного (±10%) отличается от
-- текущей цены товара, как будто цена с тех пор менялась.
-- -----------------------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o,
       p.id,
       1 + (o + k) % 3,
       round((p.price * (0.9 + random() * 0.2))::numeric, 2)
FROM generate_series(1, 5000) AS o
CROSS JOIN generate_series(1, 4) AS k
JOIN products p ON p.id = 1 + (o * 13 + k * 701) % 3000
WHERE k <= 1 + o % 4;

-- итоговая сумма заказа = сумма (количество * цена) по его позициям
UPDATE orders
SET total_amount = (SELECT SUM(quantity * unit_price)
                    FROM order_items
                    WHERE order_items.order_id = orders.id);

-- -----------------------------------------------------------------------------
-- promo_usages: промокод применён примерно к 28% заказов. Для применения
-- выбраны промокоды, которые активны и действуют весь период заказов:
--   номер заказа % 16 = 0 или 4 -> WELCOME10 (id 1, скидка 10%)
--   номер заказа % 16 = 8       -> FIX200     (id 11, скидка 200 руб.)
--   номер заказа % 16 = 12      -> APP12      (id 15, скидка 12%)
--   номер заказа % 40 = 1       -> FIX500     (id 4, скидка 500 руб.)
-- Фиксированная скидка не больше половины суммы заказа.
-- -----------------------------------------------------------------------------
INSERT INTO promo_usages (promo_id, order_id, user_id, discount_amount, used_at)
SELECT pc.id,
       o.id,
       o.user_id,
       CASE WHEN pc.discount_type = 'percent'
            THEN round(o.total_amount * pc.discount_value / 100, 2)
            ELSE LEAST(pc.discount_value, round(o.total_amount * 0.5, 2))
       END,
       o.created_at
FROM orders o
JOIN promo_codes pc
  ON pc.id = CASE WHEN o.id % 40 = 1 THEN 4
                  ELSE CASE o.id % 16 WHEN 0 THEN 1
                                      WHEN 4 THEN 1
                                      WHEN 8 THEN 11
                                      WHEN 12 THEN 15
                       END
             END;

-- вычитаем скидку из итоговой суммы заказа
UPDATE orders
SET total_amount = total_amount - (SELECT discount_amount
                                   FROM promo_usages
                                   WHERE promo_usages.order_id = orders.id)
WHERE id IN (SELECT order_id FROM promo_usages);

-- -----------------------------------------------------------------------------
-- payments: статус платежа зависит от статуса заказа.
--   created              -> pending (платёж есть у каждого второго заказа)
--   paid/shipped/delivered -> succeeded
--   cancelled            -> refunded или failed (у части заказов платежа нет)
-- Сумма платежа равна итоговой сумме заказа.
-- -----------------------------------------------------------------------------
INSERT INTO payments (order_id, amount, status, paid_at)
SELECT id,
       total_amount,
       CASE WHEN status = 'created'   THEN 'pending'
            WHEN status = 'cancelled' THEN CASE WHEN id % 3 = 0 THEN 'refunded'
                                                ELSE 'failed' END
            ELSE 'succeeded'
       END,
       CASE WHEN status IN ('paid', 'shipped', 'delivered')
              OR (status = 'cancelled' AND id % 3 = 0)
            THEN LEAST(created_at + interval '1 hour', now())
       END
FROM orders
WHERE status IN ('paid', 'shipped', 'delivered')
   OR (status = 'created'   AND id % 2 = 0)
   OR (status = 'cancelled' AND id % 3 <> 2);

-- -----------------------------------------------------------------------------
-- deliveries: доставка по первому адресу покупателя (адрес с номером
-- user_id - 50, см. addresses). Дата проставлена только у доставленных
-- заказов (через 2-9 дней после оформления, но не позже текущего момента).
-- -----------------------------------------------------------------------------
INSERT INTO deliveries (order_id, address_id, delivery_status, delivery_date)
SELECT id,
       user_id - 50,
       CASE status WHEN 'delivered' THEN 'delivered'
                   WHEN 'shipped'   THEN 'in_transit'
                   WHEN 'paid'      THEN 'pending'
                   ELSE 'cancelled'
       END,
       CASE WHEN status = 'delivered'
            THEN LEAST(created_at + (2 + id % 8) * interval '1 day', now())
       END
FROM orders
WHERE status IN ('paid', 'shipped', 'delivered')
   OR (status = 'cancelled' AND id % 2 = 0);

-- -----------------------------------------------------------------------------
-- reviews: отзывы к товарам из доставленных заказов (оставляет примерно
-- каждый третий покупатель). Оценка вычисляется по остатку от деления,
-- в результате оценок 4-5 больше, чем 1-2.
-- -----------------------------------------------------------------------------
INSERT INTO reviews (user_id, product_id, score, comment, created_at)
SELECT o.user_id,
       oi.product_id,
       CASE (o.id + oi.product_id) % 10
            WHEN 0 THEN 1
            WHEN 1 THEN 2
            WHEN 2 THEN 3
            WHEN 3 THEN 3
            WHEN 4 THEN 4
            WHEN 5 THEN 4
            ELSE 5
       END,
       NULL,
       LEAST(o.created_at + interval '10 days', now())
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.status = 'delivered'
  AND random() < 0.3;

-- текст отзыва по оценке; у 30% отзывов текста нет (NULL)
UPDATE reviews
SET comment = CASE
        WHEN score <= 2 THEN
             (ARRAY['Не соответствует описанию','Пришёл бракованный товар',
                    'Качество разочаровало','Не рекомендую'])[1 + id % 4]
        WHEN score = 3 THEN
             (ARRAY['Обычный товар, ничего особенного','Нормально за свои деньги',
                    'Есть небольшие недостатки','Ожидал большего'])[1 + id % 4]
        ELSE
             (ARRAY['Отличный товар, рекомендую','Всё пришло быстро, доволен',
                    'Качество на высоте','Соответствует описанию'])[1 + id % 4]
    END
WHERE id % 10 < 7;

-- -----------------------------------------------------------------------------
-- wishlist: 4000 пар (покупатель, товар). Множители 7 и 13 взаимно просты с
-- 1150 и 3000, поэтому за 4000 шагов одна и та же пара не повторяется.
-- -----------------------------------------------------------------------------
INSERT INTO wishlist (user_id, product_id, added_at)
SELECT 51 + (g * 7) % 1150,
       1 + (g * 13) % 3000,
       now() - random() * 300 * interval '1 day'
FROM generate_series(1, 4000) AS g;

COMMIT;

-- -----------------------------------------------------------------------------
-- Контроль: количество строк в каждой таблице
-- -----------------------------------------------------------------------------
SELECT 'users' AS table_name, count(*) AS rows FROM users
UNION ALL SELECT 'sellers',      count(*) FROM sellers
UNION ALL SELECT 'categories',   count(*) FROM categories
UNION ALL SELECT 'products',     count(*) FROM products
UNION ALL SELECT 'stock',        count(*) FROM stock
UNION ALL SELECT 'carts',        count(*) FROM carts
UNION ALL SELECT 'cart_items',   count(*) FROM cart_items
UNION ALL SELECT 'addresses',    count(*) FROM addresses
UNION ALL SELECT 'orders',       count(*) FROM orders
UNION ALL SELECT 'order_items',  count(*) FROM order_items
UNION ALL SELECT 'payments',     count(*) FROM payments
UNION ALL SELECT 'deliveries',   count(*) FROM deliveries
UNION ALL SELECT 'reviews',      count(*) FROM reviews
UNION ALL SELECT 'wishlist',     count(*) FROM wishlist
UNION ALL SELECT 'promo_codes',  count(*) FROM promo_codes
UNION ALL SELECT 'promo_usages', count(*) FROM promo_usages;
