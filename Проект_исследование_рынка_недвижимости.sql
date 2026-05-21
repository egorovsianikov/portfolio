/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор: Овсяников Егор
 * Дата: 07.03.2026
*/



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),

-- Продолжите запрос здесь
-- Используйте id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
-- Выведем объявления без выбросов:
prepared_data AS (
    SELECT
        f.id,
        f.rooms,
        f.balcony,
        f.total_area,
        f.living_area,
        f.kitchen_area,
        f.ceiling_height,
        f.floor,
        f.floors_total,
        f.is_apartment,
        f.open_plan,
        a.first_day_exposition AS dt_published,
        a.days_exposition,
        a.last_price AS price,
        a.last_price/f.total_area AS price_per_sqm,
        c.city AS city_name,
        CASE
            WHEN c.city_id = '6X8I' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region_category,
        t.type AS city_type_name,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN a.days_exposition >= 181 THEN '181+ days'
            ELSE 'non category'
        END AS activity_category
    FROM real_estate.flats f
    INNER JOIN filtered_id ff ON f.id = ff.id
    INNER JOIN real_estate.advertisement a ON f.id = a.id
    LEFT JOIN real_estate.city c ON f.city_id = c.city_id
    LEFT JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE LOWER(t.type) = 'город'
      AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
)
SELECT
    region_category AS "Регион",
    activity_category AS "Категория активности",
    COUNT(*) AS "Кол-во объявлений",
    ROUND(AVG(price_per_sqm)) AS "Ср. цена кв.м., руб",
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)::numeric, 1) AS "Мед. цена кв.м., руб",
    ROUND(AVG(total_area)::numeric, 1) AS "Ср. площадь общ., кв.м",
    ROUND(AVG(rooms)::numeric, 1) AS "Ср. кол-во комнат",
    ROUND(AVG(balcony)::numeric, 1) AS "Ср. кол-во балконов",
    ROUND(AVG(ceiling_height)::numeric, 2) AS "Ср. высота потолков, м",
    ROUND(100.0 * SUM(is_apartment)::numeric / COUNT(*), 1) AS "Доля апартаментов, %",
    ROUND(100.0 * SUM(open_plan)::numeric / COUNT(*), 1) AS "Доля свободной планировки, %"
FROM prepared_data
WHERE region_category IS NOT NULL
GROUP BY region_category, activity_category
ORDER BY
    region_category,
    CASE activity_category
        WHEN '1-30 days' THEN 1
        WHEN '31-90 days' THEN 2
        WHEN '91-180 days' THEN 3
        WHEN '181+ days' THEN 4
        WHEN 'non category' THEN 5
    END;


-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    -- Определяем аномальные значения для фильтрации
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_flats_id AS (
    -- ID квартир без аномалий
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Продолжите запрос здесь
-- Используйте id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
advertisement_data AS (
    -- Подготавливаем данные по объявлениям
    SELECT
        a.id,
        a.first_day_exposition AS publication_date,
        a.days_exposition,
        a.last_price,
        f.total_area,
        EXTRACT(MONTH FROM a.first_day_exposition) AS pub_month,
        -- Рассчитываем дату снятия объявления
        CASE
            WHEN a.days_exposition IS NOT NULL 
            THEN a.first_day_exposition + a.days_exposition * INTERVAL '1 day'
            ELSE NULL
        END AS removal_date,
        -- Стоимость квадратного метра
        a.last_price / f.total_area AS price_per_sqm
    FROM real_estate.advertisement a
    JOIN filtered_flats_id ff ON a.id = ff.id
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE 
        EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
        AND LOWER(t.type) = 'город'
),
-- Данные по публикациям
publications AS (
    SELECT
        pub_month AS month,
        COUNT(*) AS publications_count,
        ROUND(AVG(price_per_sqm)) AS avg_price_per_sqm_pub,
        ROUND(AVG(total_area)::numeric, 1) AS avg_total_area_pub
    FROM advertisement_data
    GROUP BY pub_month
),
-- Данные по снятиям
removals AS (
    SELECT
        EXTRACT(MONTH FROM removal_date) AS month,
        COUNT(*) AS removals_count,
        ROUND(AVG(price_per_sqm)) AS avg_price_per_sqm_rem,
        ROUND(AVG(total_area)::numeric, 1) AS avg_total_area_rem
    FROM advertisement_data
    WHERE removal_date IS NOT NULL
    GROUP BY EXTRACT(MONTH FROM removal_date)
)
-- Итоговая таблица с агрегацией по месяцам (без учёта года)
SELECT
    COALESCE(p.month, r.month) AS "Месяц",
    -- Публикации
    COALESCE(p.publications_count, 0) AS "Кол-во публикаций",
    p.avg_price_per_sqm_pub AS "Ср. цена кв.м (публикации), руб",
    p.avg_total_area_pub AS "Ср. площадь (публикации), кв.м",
    -- Снятия
    COALESCE(r.removals_count, 0) AS "Кол-во снятий",
    r.avg_price_per_sqm_rem AS "Ср. цена кв.м (снятия), руб",
    r.avg_total_area_rem AS "Ср. площадь (снятия), кв.м"
FROM publications p
FULL JOIN removals r ON p.month = r.month
ORDER BY COALESCE(p.month, r.month);