/*===============================================================================
Schema.............: adventure_works_test
Activity...........: DDL – Create Source (SRC) and Fact (FCT) Tables
Description........:
    Defines the Source (raw/staging) and Fact layers for the Adventure Works DWH.
    SRC tables store versioned raw entities loaded from operational systems,
    while the FCT layer contains atomic transactional facts at line level.
Owner..............: Olga Pankova
Created............: 2025-10-29
===============================================================================*/


-- ===========================================================
-- 1. SRC_CUSTOMER_DATA
-- Historical source table for customers.
-- Stores one record per version of each customer (customerkey + update_ts).
-- ===========================================================
CREATE TABLE adventure_works_test.src_customer_data (
    customerkey      BIGINT      NOT NULL,       -- Business key
    customer_id      TEXT,                      -- Source system customer ID
    customer         TEXT,                      -- Customer name
    city             TEXT,
    state_province   TEXT,
    country_region   TEXT,
    postal_code      TEXT,
    update_ts        TIMESTAMP   NOT NULL,      -- Extract/load timestamp
    CONSTRAINT pk_src_customer_data
        PRIMARY KEY (customerkey, update_ts)
);
ALTER TABLE adventure_works_test.src_customer_data OWNER TO postgres;



-- ===========================================================
-- 2. SRC_DATE_DATA
-- Calendar/date source table.
-- Contains fiscal and calendar attributes, unique by datekey.
-- ===========================================================
CREATE TABLE adventure_works_test.src_date_data (
    datekey         BIGINT       NOT NULL,      -- Surrogate key (YYYYMMDD)
    date            TIMESTAMP,                  -- Calendar date
    fiscal_year     TEXT,
    fiscal_quarter  TEXT,
    month           TEXT,
    full_date       TEXT,
    monthkey        BIGINT,
    update_ts       TIMESTAMP,                  -- Load timestamp
    CONSTRAINT pk_src_date_data
        PRIMARY KEY (datekey)
);
ALTER TABLE adventure_works_test.src_date_data OWNER TO postgres;



-- ===========================================================
-- 3. SRC_PRODUCT_DATA
-- Historical source table for products.
-- Each record represents a product version (productkey + update_ts).
-- ===========================================================
CREATE TABLE adventure_works_test.src_product_data (
    productkey      BIGINT              NOT NULL,
    sku             TEXT,
    product         TEXT,
    standard_cost   DOUBLE PRECISION,
    color           TEXT,
    list_price      DOUBLE PRECISION,
    model           TEXT,
    subcategory     TEXT,
    category        TEXT,
    update_ts       TIMESTAMP           NOT NULL,
    CONSTRAINT pk_src_product_data
        PRIMARY KEY (productkey, update_ts)
);
ALTER TABLE adventure_works_test.src_product_data OWNER TO postgres;



-- ===========================================================
-- 4. SRC_RESELLER_DATA
-- Historical source table for resellers.
-- Stores one record per version (resellerkey + update_ts).
-- ===========================================================
CREATE TABLE adventure_works_test.src_reseller_data (
    resellerkey     BIGINT      NOT NULL,
    reseller_id     TEXT,
    business_type   TEXT,
    reseller        TEXT,
    city            TEXT,
    state_province  TEXT,
    country_region  TEXT,
    postal_code     TEXT,
    update_ts       TIMESTAMP   NOT NULL,
    CONSTRAINT pk_src_reseller_data
        PRIMARY KEY (resellerkey, update_ts)
);
ALTER TABLE adventure_works_test.src_reseller_data OWNER TO postgres;



-- ===========================================================
-- 5. SRC_SALES_DATA
-- Transactional sales source table.
-- Stores atomic sales lines versioned by (salesorderlinekey, update_ts).
-- ===========================================================
CREATE TABLE adventure_works_test.src_sales_data (
    salesorderlinekey         BIGINT              NOT NULL,
    resellerkey               BIGINT,
    customerkey               BIGINT,
    productkey                BIGINT,
    orderdatekey              BIGINT,
    duedatekey                BIGINT,
    shipdatekey               BIGINT,
    salesterritorykey         BIGINT,
    order_quantity            BIGINT,
    unit_price                DOUBLE PRECISION,
    extended_amount           DOUBLE PRECISION,
    unit_price_discount_pct   DOUBLE PRECISION,
    product_standard_cost     DOUBLE PRECISION,
    total_product_cost        DOUBLE PRECISION,
    sales_amount              DOUBLE PRECISION,
    update_ts                 TIMESTAMP           NOT NULL,
    CONSTRAINT pk_src_sales_data
        PRIMARY KEY (salesorderlinekey, update_ts)
);
ALTER TABLE adventure_works_test.src_sales_data OWNER TO postgres;



-- ===========================================================
-- 6. SRC_SALES_ORDER_DATA
-- Supplementary sales order source table.
-- Contains channel, order, and line-level attributes.
-- ===========================================================
CREATE TABLE adventure_works_test.src_sales_order_data (
    channel             TEXT,
    salesorderlinekey   BIGINT      NOT NULL,
    sales_order         TEXT,
    sales_order_line    TEXT,
    update_ts           TIMESTAMP   NOT NULL,
    CONSTRAINT pk_src_sales_order_data
        PRIMARY KEY (salesorderlinekey, update_ts)
);
ALTER TABLE adventure_works_test.src_sales_order_data OWNER TO postgres;



-- ===========================================================
-- 7. SRC_SALES_TERRITORY_DATA
-- Source table for sales territories.
-- Versioned by (salesterritorykey, update_ts).
-- ===========================================================
CREATE TABLE adventure_works_test.src_sales_territory_data (
    salesterritorykey   BIGINT      NOT NULL,
    region              TEXT,
    country             TEXT,
    "group"             TEXT,       -- Renamed in DIM layer to group_region
    update_ts           TIMESTAMP   NOT NULL,
    CONSTRAINT pk_src_sales_territory_data
        PRIMARY KEY (salesterritorykey, update_ts)
);
ALTER TABLE adventure_works_test.src_sales_territory_data OWNER TO postgres;



-- ===========================================================
-- 8. FCT_SALES_DATA
-- Core fact table for transactional sales at line level.
-- Each record corresponds to one sales order line.
-- ===========================================================
CREATE TABLE adventure_works_test.fct_sales_data (
    salesorderlinekey         BIGINT PRIMARY KEY NOT NULL,  -- Unique line identifier
    resellerkey               BIGINT,
    customerkey               BIGINT,
    productkey                BIGINT,
    orderdatekey              DATE,                         -- Converted from YYYYMMDD
    duedatekey                DATE,
    shipdatekey               DATE,
    salesterritorykey         BIGINT,
    order_quantity            BIGINT,
    unit_price                DOUBLE PRECISION,
    extended_amount           DOUBLE PRECISION,
    unit_price_discount_pct   DOUBLE PRECISION,
    product_standard_cost     DOUBLE PRECISION,
    total_product_cost        DOUBLE PRECISION,
    sales_amount              DOUBLE PRECISION,
    update_ts                 TIMESTAMP NOT NULL             -- Last refresh timestamp
);
ALTER TABLE adventure_works_test.fct_sales_data OWNER TO postgres;



-- ===========================================================
-- 9. Supporting Indexes
-- ===========================================================

-- Accelerates windowed ranking and deduplication in SRC sales orders
CREATE INDEX idx_src_sales_order_data_linekey_updts
    ON adventure_works_test.src_sales_order_data (salesorderlinekey, update_ts DESC);
