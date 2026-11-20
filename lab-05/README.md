# Лабораторная работа №5 — файлы

- [`transaction.sql`](transaction.sql) — оформление заказа в транзакции: фиксация связанных изменений `COMMIT` и их отмена `ROLLBACK` после ошибки.
- [`functions.sql`](functions.sql) — функции на PL/pgSQL: атомарное оформление заказа с проверкой остатка (`place_order`) и выручка продавца за период (`seller_revenue_for_period`).
- [`triggers.sql`](triggers.sql) — триггеры: аудит изменения цены товара в журнал `product_price_history` и пересчёт среднего рейтинга товара `products.rating` при добавлении отзыва.
- [`REPORT.md`](REPORT.md) — отчёт по лабораторной работе (текст каждого скрипта, его назначение и результат, обоснование размещения логики в базе данных и в приложении).

Скрипты выполняются в базе `marketplace` после `schema.sql` (лабораторная работа №1) и `seed.sql` (лабораторная работа №2) в порядке `transaction.sql`, `functions.sql`, `triggers.sql`.
