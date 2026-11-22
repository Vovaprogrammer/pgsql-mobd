-- =============================================================================
-- Лабораторная работа №6. Тип данных JSONB
-- Запускать в базе marketplace (после schema.sql и seed.sql).
-- =============================================================================

-- Пункт 1. Характеристики товара в столбце JSONB. Набор ключей зависит от
-- корневой категории товара (номера категорий — из seed.sql); значения
-- вычисляются из id, поэтому при повторном запуске получаются те же.
-- split_part(title, ' ', -2) — предпоследнее слово названия, марка товара.
ALTER TABLE products ADD COLUMN IF NOT EXISTS attributes JSONB;

UPDATE products
SET attributes = CASE
    WHEN category_id IN (7, 8, 9, 10, 26, 27) THEN      -- электроника
        jsonb_build_object(
            'brand', split_part(title, ' ', -2),
            'color', (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4])
    WHEN category_id IN (11, 12, 13) THEN               -- книги
        jsonb_build_object(
            'author', (ARRAY['Л. Толстой', 'А. Пушкин', 'А. Чехов',
                             'М. Булгаков', 'Н. Гоголь'])[1 + id % 5],
            'pages',  100 + id % 11 * 40,
            'cover',  (ARRAY['hard', 'soft'])[1 + id % 2])
    WHEN category_id IN (14, 15, 16) THEN               -- одежда и обувь
        jsonb_build_object(
            'color',    (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4],
            'material', (ARRAY['cotton', 'linen', 'wool', 'viscose',
                               'polyester'])[1 + id % 5])
    WHEN category_id IN (17, 18, 19, 20, 21, 22) THEN   -- дом и сад, спорт
        jsonb_build_object(
            'color',           (ARRAY['black', 'white', 'grey', 'blue'])[1 + id % 4],
            'warranty_months', (ARRAY[6, 12, 18, 24, 36])[1 + id % 5])
    WHEN category_id IN (23, 24, 25) THEN               -- красота и здоровье
        jsonb_build_object(
            'volume_ml', (ARRAY[30, 50, 100, 250])[1 + id % 4])
END;

-- Проверка: по одному товару из каждой корневой категории
SELECT id, title, attributes
FROM products
WHERE id IN (1, 4, 7, 10, 13, 16)
ORDER BY id;

-- Пункт 2. Извлечение полей: -> возвращает значение как JSONB, ->> — как
-- текст. Книги от 460 страниц: у товаров без ключа pages ->> даёт NULL.
SELECT id, title,
       attributes -> 'author'         AS author_json,
       attributes ->> 'author'        AS author,
       (attributes ->> 'pages')::int  AS pages
FROM products
WHERE (attributes ->> 'pages')::int >= 460
ORDER BY id
LIMIT 5;

-- Фильтрация по вхождению фрагмента: книги Булгакова в твёрдом переплёте.
SELECT id, title, attributes
FROM products
WHERE attributes @> '{"author": "М. Булгаков", "cover": "hard"}'
ORDER BY id
LIMIT 5;
