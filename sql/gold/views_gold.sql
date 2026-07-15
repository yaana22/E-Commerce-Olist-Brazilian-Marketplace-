-- ==========================================
-- CREATE GOLD SCHEMA
-- ==========================================

CREATE SCHEMA IF NOT EXISTS gold;


-- ==========================================
-- DROP EXISTING VIEWS (FOR RERUN)
-- ==========================================

DROP VIEW IF EXISTS gold.fact_reviews;
DROP VIEW IF EXISTS gold.fact_payments;
DROP VIEW IF EXISTS gold.fact_order_items;
DROP VIEW IF EXISTS gold.fact_orders;

DROP VIEW IF EXISTS gold.dim_date;
DROP VIEW IF EXISTS gold.dim_sellers;
DROP VIEW IF EXISTS gold.dim_products;
DROP VIEW IF EXISTS gold.dim_customers;



-- ==========================================
-- DIMENSION VIEWS
-- ==========================================


-- CUSTOMER VIEW

CREATE VIEW gold.dim_customers AS

SELECT DISTINCT

    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state

FROM silver.customers;



-- PRODUCT VIEW

CREATE VIEW gold.dim_products AS

SELECT DISTINCT

    product_id,
    product_category_name,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM silver.products;



-- SELLER VIEW

CREATE VIEW gold.dim_sellers AS

SELECT DISTINCT

    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state

FROM silver.sellers;



-- DATE VIEW

CREATE VIEW gold.dim_date AS

SELECT DISTINCT

    order_purchase_timestamp::date AS date_id,

    EXTRACT(YEAR FROM order_purchase_timestamp) AS year,

    EXTRACT(MONTH FROM order_purchase_timestamp) AS month,

    EXTRACT(DAY FROM order_purchase_timestamp) AS day,

    TO_CHAR(order_purchase_timestamp::date,'Month') AS month_name


FROM silver.orders

WHERE order_purchase_timestamp IS NOT NULL;




-- ==========================================
-- FACT VIEWS
-- ==========================================


-- ORDERS FACT VIEW

CREATE VIEW gold.fact_orders AS

SELECT

    order_id,

    customer_id,

    order_status,

    order_purchase_timestamp::date AS order_date,

    order_delivered_customer_date,

    order_estimated_delivery_date


FROM silver.orders;




-- ORDER ITEMS FACT VIEW

CREATE VIEW gold.fact_order_items AS

SELECT

    order_id,

    order_item_id,

    product_id,

    seller_id,

    shipping_limit_date,

    price,

    freight_value


FROM silver.order_items;




-- PAYMENT FACT VIEW

CREATE VIEW gold.fact_payments AS

SELECT

    order_id,

    payment_sequential,

    payment_type,

    payment_installments,

    payment_value


FROM silver.order_payments;




-- REVIEW FACT VIEW

CREATE VIEW gold.fact_reviews AS

SELECT

    review_id,

    order_id,

    review_score,

    review_creation_date,

    review_answer_timestamp


FROM silver.order_reviews;




-- ==========================================
-- CHECK GOLD VIEWS
-- ==========================================

SELECT 

    table_name

FROM information_schema.views

WHERE table_schema='gold'

ORDER BY table_name;
