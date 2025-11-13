/*===============================================================================
Schema.............: adventure_works_test
Activity...........: DDL – Create Dimension Tables (Type 1 and Type 2)
Description........:
    Defines dimension layer tables for the Adventure Works analytical model.
    Includes SCD Type 2 dimensions (Customer, Product, Reseller, Sales Territory)
    with validity ranges and current-record flag, and Type 1 dimensions
    (Date, Sales Order). All tables include technical audit columns.
Owner..............: Olga Pankova
Created............: 2025-10-29
===============================================================================*/


-- ===========================================================
-- 1. DIM_CUSTOMER_DATA  (SCD Type 2)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_customer_data (
    customerkey      BIGINT      NOT NULL,                -- Business key
    customer_id      TEXT,                                -- Source system customer ID
    customer         TEXT,                                -- Customer name
    city             TEXT,
    state_province   TEXT,
    country_region   TEXT,
    postal_code      TEXT,
    update_ts        TIMESTAMP   NOT NULL,                -- Source record timestamp
    valid_from       DATE DEFAULT '2000-01-01',           -- Version start date
    valid_to         DATE DEFAULT '3000-01-01',           -- Version end date
    is_valid         INT,                                 -- 1 = current, 0 = historical
    CONSTRAINT pk_dim_customer_data
        PRIMARY KEY (customerkey, update_ts)
);
ALTER TABLE adventure_works_test.dim_customer_data OWNER TO postgres;



-- ===========================================================
-- 2. DIM_DATE_DATA  (Type 1 – slowly growing calendar)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_date_data (
    datekey        BIGINT NOT NULL PRIMARY KEY,           -- Surrogate key (YYYYMMDD)
    date           TIMESTAMP,                             -- Calendar date
    fiscal_year    TEXT,
    fiscal_quarter TEXT,
    month          TEXT,
    full_date      TEXT,
    monthkey       BIGINT,
    update_ts      TIMESTAMP                              -- Source load timestamp
);
ALTER TABLE adventure_works_test.dim_date_data OWNER TO postgres;



-- ===========================================================
-- 3. DIM_PRODUCT_DATA  (SCD Type 2)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_product_data (
    productkey     BIGINT      NOT NULL,                  -- Business key
    sku            TEXT,
    product        TEXT,
    standard_cost  DOUBLE PRECISION,
    color          TEXT,
    list_price     DOUBLE PRECISION,
    model          TEXT,
    subcategory    TEXT,
    category       TEXT,
    update_ts      TIMESTAMP   NOT NULL,
    valid_from     DATE DEFAULT '2000-01-01',
    valid_to       DATE DEFAULT '3000-01-01',
    is_valid       INT,
    CONSTRAINT pk_dim_product_data
        PRIMARY KEY (productkey, update_ts)
);
ALTER TABLE adventure_works_test.dim_product_data OWNER TO postgres;



-- ===========================================================
-- 4. DIM_RESELLER_DATA  (SCD Type 2)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_reseller_data (
    resellerkey    BIGINT      NOT NULL,                  -- Business key
    reseller_id    TEXT,
    business_type  TEXT,
    reseller       TEXT,
    city           TEXT,
    state_province TEXT,
    country_region TEXT,
    postal_code    TEXT,
    update_ts      TIMESTAMP   NOT NULL,
    valid_from     DATE DEFAULT '2000-01-01',
    valid_to       DATE DEFAULT '3000-01-01',
    is_valid       INT,
    CONSTRAINT pk_dim_reseller_data
        PRIMARY KEY (resellerkey, update_ts)
);
ALTER TABLE adventure_works_test.dim_reseller_data OWNER TO postgres;



-- ===========================================================
-- 5. DIM_SALES_TERRITORY_DATA  (SCD Type 2)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_sales_territory_data (
    salesterritorykey BIGINT    NOT NULL,                 -- Business key
    region            TEXT,
    country           TEXT,
    group_region      TEXT,
    update_ts         TIMESTAMP NOT NULL,
    valid_from        DATE DEFAULT '2000-01-01',
    valid_to          DATE DEFAULT '3000-01-01',
    is_valid          INT,
    CONSTRAINT pk_dim_sales_territory_data
        PRIMARY KEY (salesterritorykey, update_ts)
);
ALTER TABLE adventure_works_test.dim_sales_territory_data OWNER TO postgres;



-- ===========================================================
-- 6. DIM_SALES_ORDER_DATA  (Type 1)
-- ===========================================================
CREATE TABLE adventure_works_test.dim_sales_order_data (
    salesorderlinekey BIGINT PRIMARY KEY,                 -- Line-level unique key
    channel           TEXT,
    sales_order       TEXT,
    sales_order_line  TEXT,
    update_ts         TIMESTAMP                           -- Source timestamp
);
ALTER TABLE adventure_works_test.dim_sales_order_data OWNER TO postgres;



-- ===========================================================
-- 7. Supporting Indexes
-- ===========================================================


-- Ensure unique matching for MERGE/UPSERT operations
CREATE UNIQUE INDEX idx_dim_sales_order_data_linekey
    ON adventure_works_test.dim_sales_order_data (salesorderlinekey);
