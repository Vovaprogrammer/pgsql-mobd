-- =============================================================================
-- Лабораторная работа №5. Триггеры
-- Запускать в базе marketplace (после schema.sql и seed.sql).
-- Объекты создаются через IF NOT EXISTS / CREATE OR REPLACE, скрипт можно
-- выполнять повторно.
-- =============================================================================

-- Пункт 4. Аудит изменения цены товара.
-- Журнал: какой товар, старая и новая цена, когда изменена.
CREATE TABLE IF NOT EXISTS product_price_history (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT        NOT NULL
                   REFERENCES products(id) ON DELETE CASCADE ON UPDATE CASCADE,
    old_price  NUMERIC(12,2) NOT NULL,
    new_price  NUMERIC(12,2) NOT NULL,
    changed_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Триггерная функция: OLD — строка товара до изменения, NEW — после.
CREATE OR REPLACE FUNCTION log_price_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO product_price_history (product_id, old_price, new_price)
    VALUES (NEW.id, OLD.price, NEW.price);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Срабатывает после UPDATE столбца price для каждой изменённой строки,
-- если цена действительно стала другой.
CREATE OR REPLACE TRIGGER trg_log_price_change
AFTER UPDATE OF price ON products
FOR EACH ROW
WHEN (OLD.price <> NEW.price)
EXECUTE FUNCTION log_price_change();

-- Проверка: одной командой поднять цену товаров 2 и 5 на 100 руб.
UPDATE products SET price = price + 100 WHERE id IN (2, 5);

SELECT * FROM product_price_history ORDER BY id;

-- Пункт 5. Денормализованное поле products.rating — средняя оценка товара.
-- Хранится в products, чтобы не считать AVG по reviews при каждом показе.
ALTER TABLE products ADD COLUMN IF NOT EXISTS rating NUMERIC(3,2);

-- Начальное заполнение по уже существующим отзывам (без отзывов — NULL)
UPDATE products AS p
SET rating = (SELECT ROUND(AVG(r.score), 2)
              FROM reviews AS r
              WHERE r.product_id = p.id);

-- Триггерная функция: пересчитать рейтинг товара, к которому добавлен отзыв
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

CREATE OR REPLACE TRIGGER trg_refresh_rating
AFTER INSERT ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();

-- Проверка: товар 10 (два отзыва с оценкой 5) до и после отзыва с оценкой 2
-- от покупателя 189, купившего этот товар.
SELECT id, title, rating FROM products WHERE id = 10;

INSERT INTO reviews (user_id, product_id, score) VALUES (189, 10, 2);

SELECT id, title, rating FROM products WHERE id = 10;
