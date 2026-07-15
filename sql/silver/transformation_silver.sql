-- =====================================================
-- SILVER LAYER TRANSFORMATION
-- Bronze -> Silver
-- Full Refresh Load
-- =====================================================


-- =====================================================
-- 1. CLEAR SILVER TABLES
-- =====================================================

TRUNCATE TABLE silver.order_items CASCADE;
TRUNCATE TABLE silver.order_payments CASCADE;
TRUNCATE TABLE silver.order_reviews CASCADE;
TRUNCATE TABLE silver.orders CASCADE;
TRUNCATE TABLE silver.customers CASCADE;
TRUNCATE TABLE silver.products CASCADE;
TRUNCATE TABLE silver.sellers CASCADE;
TRUNCATE TABLE silver.geolocation CASCADE;
TRUNCATE TABLE silver.product_category_translation CASCADE;



-- =====================================================
-- 2. CUSTOMERS
-- =====================================================

INSERT INTO silver.customers
(
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)

SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    COALESCE(TRIM(customer_city),'Unknown'),
    UPPER(COALESCE(TRIM(customer_state),'NA'))

FROM
(
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY customer_id
        ORDER BY customer_id
    ) rn

    FROM bronze.customers
    WHERE customer_id IS NOT NULL

) t

WHERE rn = 1;



-- =====================================================
-- 3. ORDERS
-- =====================================================

INSERT INTO silver.orders
(
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)

SELECT
    order_id,
    customer_id,
    LOWER(TRIM(order_status)),
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date

FROM
(
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY order_id
        ORDER BY order_purchase_timestamp
    ) rn

    FROM bronze.orders
    WHERE order_id IS NOT NULL

) t

WHERE rn = 1;



-- =====================================================
-- 4. PRODUCTS
-- =====================================================

INSERT INTO silver.products

SELECT
    product_id,
    COALESCE(product_category_name,'Unknown'),
    product_name_lenght,
    product_description_lenght,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM
(
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY product_id
        ORDER BY product_id
    ) rn

    FROM bronze.products
    WHERE product_id IS NOT NULL

) t

WHERE rn = 1;



-- =====================================================
-- 5. SELLERS
-- =====================================================

INSERT INTO silver.sellers

SELECT
    seller_id,
    seller_zip_code_prefix,
    COALESCE(TRIM(seller_city),'Unknown'),
    UPPER(COALESCE(TRIM(seller_state),'NA'))

FROM
(
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY seller_id
        ORDER BY seller_id
    ) rn

    FROM bronze.sellers
    WHERE seller_id IS NOT NULL

) t

WHERE rn = 1;



-- =====================================================
-- 6. ORDER ITEMS
-- =====================================================

INSERT INTO silver.order_items

SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,

    CASE
        WHEN price >= 0 THEN price
        ELSE NULL
    END,

    CASE
        WHEN freight_value >= 0 THEN freight_value
        ELSE NULL
    END

FROM bronze.order_items

WHERE order_id IS NOT NULL;



-- =====================================================
-- 7. PAYMENTS
-- =====================================================

INSERT INTO silver.order_payments

SELECT
    order_id,
    payment_sequential,
    LOWER(TRIM(payment_type)),
    payment_installments,

    CASE
        WHEN payment_value >= 0 THEN payment_value
        ELSE NULL
    END

FROM bronze.order_payments

WHERE order_id IS NOT NULL;



-- =====================================================
-- 8. REVIEWS
-- =====================================================

INSERT INTO silver.order_reviews

SELECT
    review_id,
    order_id,

    CASE
        WHEN review_score BETWEEN 1 AND 5
        THEN review_score
        ELSE NULL
    END,

    NULLIF(TRIM(review_comment_title),''),
    NULLIF(TRIM(review_comment_message),''),

    review_creation_date,
    review_answer_timestamp

FROM
(
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY review_id
        ORDER BY review_creation_date
    ) rn

    FROM bronze.order_reviews
    WHERE review_id IS NOT NULL

) t

WHERE rn = 1;



-- =====================================================
-- 9. GEOLOCATION
-- =====================================================

INSERT INTO silver.geolocation

SELECT DISTINCT

    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    COALESCE(TRIM(geolocation_city),'Unknown'),
    UPPER(COALESCE(TRIM(geolocation_state),'NA'))

FROM bronze.geolocation;



-- =====================================================
-- 10. CATEGORY TRANSLATION
-- =====================================================

INSERT INTO silver.product_category_translation

SELECT DISTINCT

    product_category_name,
    product_category_name_english

FROM bronze.product_category_translation;
