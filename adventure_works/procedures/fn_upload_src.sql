CREATE OR REPLACE FUNCTION adventure_works_test.fn_upload_src()
RETURNS JSONB
LANGUAGE plpgsql
AS $$
/*===============================================================================
URL..................: adventure_works/procedures/fn_upload_src
Activity.............: ETL - Load source (SRC) layer from staging
Description..........:
    Incrementally loads data from *_temp staging tables into SRC tables in
    'adventure_works_test'. For each business entity (customers, dates,
    products, resellers, sales, sales orders, sales territories), the
    function:
      - builds a temp table of NEW/CHANGED rows only
      - appends them to the persistent SRC table
      - logs the step execution to admin.sp_log_etl
      - returns a JSONB object with row counts per table

Owner................: Olga Pankova
Role in ETL..........: Staging -> SRC ingestion step
Audit / Logging......:
    - Per-entity logging after each phase
    - Global START/END logging for the whole procedure
Execution Example....: SELECT adventure_works_test.fn_upload_src();
Change History.......:
    2025-10-28  OP  Initial version with per-entity logging blocks
    2025-10-28  OP  Refactored to reuse runtime variables across steps
    2025-10-28  OP  Added global START/END logging
    2025-10-29  OP  Converted from PROCEDURE to FUNCTION returning JSONB
===============================================================================*/
DECLARE
    v_proc_name       text := 'fn_upload_src';
    v_schema_name     text := 'adventure_works_test';

    -- Reusable runtime metadata for each phase
    v_step_start_ts        timestamp;
    v_step_end_ts          timestamp;
    v_rows_loaded          integer;
    v_status               text;
    v_msg                  text;
    v_duration_sec         numeric;

    -- Overall procedure tracking
    v_proc_start_ts        timestamp;
    v_proc_end_ts          timestamp;
    v_proc_duration_sec    numeric;
    v_proc_status          text := 'OK';      -- assumes success unless any step fails
    v_proc_msg             text := 'procedure completed successfully';
    updated_tables JSONB := '{}'::JSONB;
BEGIN
    ----------------------------------------------------------------
    -- GLOBAL START LOG
    ----------------------------------------------------------------
    v_proc_start_ts := NOW();

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,        -- start_ts
        v_proc_start_ts,        -- end_ts (same at start)
        NULL,                   -- rows_loaded (not applicable yet)
        'STARTED',              -- status
        'fn_upload_src execution started', -- msg
        0                       -- duration_sec so far
    );


    ----------------------------------------------------------------
    -- PHASE 1: src_customer_data
    -- Goal:
    --   Insert only new / changed customer rows.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_customer_data;

        CREATE TEMP TABLE tmp_customer_data
        ON COMMIT DROP
        AS
        SELECT
            customerkey,
            customer_id,
            customer,
            city,
            state_province,
            country_region,
            postal_code,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_customer_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_customer_data d
            WHERE t.customerkey      = d.customerkey
              AND t.customer         = d.customer
              AND t.customer_id      = d.customer_id
              AND t.postal_code      = d.postal_code
              AND t.state_province   = d.state_province
              AND t.city             = d.city
              AND t.country_region   = d.country_region
        )
        GROUP BY customerkey, customer_id, customer, city,
                 state_province, country_region, postal_code;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_customer_data;
        updated_tables := updated_tables || ('{"dim_customer_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_customer_data (
            customerkey,
            customer_id,
            customer,
            city,
            state_province,
            country_region,
            postal_code,
            update_ts
        )
        SELECT customerkey,
               customer_id,
               customer,
               city,
               state_province,
               country_region,
               postal_code,
               update_ts
        FROM tmp_customer_data;

        v_msg := 'src_customer_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';  -- bubble up to global
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 2: src_date_data
    -- Goal:
    --   Insert calendar rows that do not yet exist by datekey.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_src_date_data;

        CREATE TEMP TABLE tmp_src_date_data
        ON COMMIT DROP
        AS
        SELECT
            datekey,
            date,
            fiscal_year,
            fiscal_quarter,
            month,
            full_date,
            monthkey,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_date_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_date_data d
            WHERE t.datekey = d.datekey
        )
        GROUP BY datekey, date, fiscal_year, fiscal_quarter,
                 month, full_date, monthkey;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_src_date_data;

        updated_tables := updated_tables || ('{"dim_date_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_date_data (
            datekey,
            date,
            fiscal_year,
            fiscal_quarter,
            month,
            full_date,
            monthkey,
            update_ts
        )
        SELECT datekey,
               date,
               fiscal_year,
               fiscal_quarter,
               month,
               full_date,
               monthkey,
               update_ts
        FROM tmp_src_date_data;

        v_msg := 'src_date_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 3: src_product_data
    -- Goal:
    --   Insert new/changed product rows.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_product_data;

        CREATE TEMP TABLE tmp_product_data
        ON COMMIT DROP
        AS
        SELECT
            productkey,
            sku,
            product,
            standard_cost,
            color,
            list_price,
            model,
            subcategory,
            category,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_product_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_product_data d
            WHERE t.productkey            = d.productkey
              AND t.sku                   = d.sku
              AND t.product               = d.product
              AND t.standard_cost         = d.standard_cost
              AND COALESCE(t.color, '')   = COALESCE(d.color, '')
              AND t.list_price            = d.list_price
              AND t.subcategory           = d.subcategory
              AND t.category              = d.category
              AND t.model                 = d.model
        )
        GROUP BY productkey, sku, product, standard_cost, color,
                 list_price, model, subcategory, category ;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_product_data;

        updated_tables := updated_tables || ('{"dim_product_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_product_data (
            productkey,
            sku,
            product,
            standard_cost,
            color,
            list_price,
            model,
            subcategory,
            category,
            update_ts
        )
        SELECT *
        FROM tmp_product_data;

        v_msg := 'src_product_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 4: src_reseller_data
    -- Goal:
    --   Insert new/changed reseller rows.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_reseller_data;

        CREATE TEMP TABLE tmp_reseller_data
        ON COMMIT DROP
        AS
        SELECT
            resellerkey,
            reseller_id,
            business_type,
            reseller,
            city,
            state_province,
            country_region,
            postal_code,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_reseller_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_reseller_data d
            WHERE t.resellerkey        = d.resellerkey
              AND t.reseller_id        = d.reseller_id
              AND t.reseller           = d.reseller
              AND t.business_type      = d.business_type
              AND t.city               = d.city
              AND t.state_province     = d.state_province
              AND t.country_region     = d.country_region
              AND t.postal_code        = d.postal_code
        )
        GROUP BY resellerkey, reseller_id, business_type, reseller,
                 city, state_province, country_region, postal_code ;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_reseller_data;
        updated_tables := updated_tables || ('{"dim_reseller_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_reseller_data (
            resellerkey,
            reseller_id,
            business_type,
            reseller,
            city,
            state_province,
            country_region,
            postal_code,
            update_ts
        )
        SELECT resellerkey,
               reseller_id,
               business_type,
               reseller,
               city,
               state_province,
               country_region,
               postal_code,
               update_ts
        FROM tmp_reseller_data;

        v_msg := 'src_reseller_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 5: src_sales_data
    -- Goal:
    --   Insert new sales transaction lines.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_sales_data;

        CREATE TEMP TABLE tmp_sales_data
        ON COMMIT DROP
        AS
        SELECT
            salesorderlinekey,
            resellerkey,
            customerkey,
            productkey,
            orderdatekey,
            duedatekey,
            shipdatekey,
            salesterritorykey,
            order_quantity,
            unit_price,
            extended_amount,
            unit_price_discount_pct,
            product_standard_cost,
            total_product_cost,
            sales_amount,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_sales_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_sales_data d
            WHERE t.salesorderlinekey           = d.salesorderlinekey
              AND t.resellerkey                 = d.resellerkey
              AND t.customerkey                 = d.customerkey
              AND t.productkey                  = d.productkey
              AND t.orderdatekey                = d.orderdatekey
              AND t.duedatekey                  = d.duedatekey
              AND COALESCE(t.shipdatekey, 0)    = COALESCE(d.shipdatekey, 0)
              AND t.salesterritorykey           = d.salesterritorykey
              AND t.order_quantity              = d.order_quantity
              AND t.unit_price                  = d.unit_price
              AND t.extended_amount             = d.extended_amount
              AND t.unit_price_discount_pct     = d.unit_price_discount_pct
              AND t.product_standard_cost       = d.product_standard_cost
              AND t.total_product_cost          = d.total_product_cost
              AND t.sales_amount                = d.sales_amount
        )
        GROUP BY salesorderlinekey, resellerkey, customerkey, productkey,
                 orderdatekey, duedatekey, shipdatekey, salesterritorykey,
                 order_quantity, unit_price, extended_amount,
                 unit_price_discount_pct, product_standard_cost,
                 total_product_cost, sales_amount ;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_sales_data;
        updated_tables := updated_tables || ('{"fct_sales_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_sales_data (
            salesorderlinekey,
            resellerkey,
            customerkey,
            productkey,
            orderdatekey,
            duedatekey,
            shipdatekey,
            salesterritorykey,
            order_quantity,
            unit_price,
            extended_amount,
            unit_price_discount_pct,
            product_standard_cost,
            total_product_cost,
            sales_amount,
            update_ts
        )
        SELECT salesorderlinekey,
               resellerkey,
               customerkey,
               productkey,
               orderdatekey,
               duedatekey,
               shipdatekey,
               salesterritorykey,
               order_quantity,
               unit_price,
               extended_amount,
               unit_price_discount_pct,
               product_standard_cost,
               total_product_cost,
               sales_amount,
               update_ts
        FROM tmp_sales_data;

        v_msg := 'src_sales_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 6: src_sales_order_data
    -- Goal:
    --   Insert unique order header/line mappings.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_sales_order_data;

        CREATE TEMP TABLE tmp_sales_order_data
        ON COMMIT DROP
        AS
        SELECT
            channel,
            salesorderlinekey,
            sales_order,
            sales_order_line,
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_sales_order_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_sales_order_data d
            WHERE t.channel               = d.channel
              AND t.salesorderlinekey     = d.salesorderlinekey
              AND t.sales_order           = d.sales_order
              AND t.sales_order_line      = d.sales_order_line
        )
        GROUP BY channel, salesorderlinekey, sales_order, sales_order_line ;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_sales_order_data;
        updated_tables := updated_tables || ('{"dim_sales_order_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_sales_order_data (
            channel,
            salesorderlinekey,
            sales_order,
            sales_order_line,
            update_ts
        )
        SELECT channel, salesorderlinekey, sales_order, sales_order_line, update_ts
        FROM tmp_sales_order_data;

        v_msg := 'src_sales_order_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- PHASE 7: src_sales_territory_data
    -- Goal:
    --   Insert new territory definitions.
    ----------------------------------------------------------------
    v_step_start_ts := NOW();
    v_rows_loaded   := 0;
    v_status        := 'OK';
    v_msg           := 'upload completed';

    BEGIN
        DROP TABLE IF EXISTS tmp_sales_territory_data;

        CREATE TEMP TABLE tmp_sales_territory_data
        ON COMMIT DROP
        AS
        SELECT
            salesterritorykey,
            region,
            country,
            "group",
            max(update_ts) AS update_ts
        FROM adventure_works_test.src_sales_territory_data_temp t
        WHERE NOT EXISTS (
            SELECT 1
            FROM adventure_works_test.src_sales_territory_data d
            WHERE t.salesterritorykey   = d.salesterritorykey
              AND t.region              = d.region
              AND t.country             = d.country
              AND t."group"             = d."group"
        )
        GROUP BY salesterritorykey, region, country, "group" ;

        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_sales_territory_data;

        updated_tables := updated_tables || ('{"dim_sales_territory_data":' || v_rows_loaded || '}')::JSONB;

        INSERT INTO adventure_works_test.src_sales_territory_data (
            salesterritorykey,
            region,
            country,
            "group",
            update_ts
        )
        SELECT *
        FROM tmp_sales_territory_data;

        v_msg := 'src_sales_territory_data uploaded successfully';

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'upload failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more phases failed';
    END;

    v_step_end_ts := NOW();
    v_duration_sec := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_step_start_ts,
        v_step_end_ts,
        v_rows_loaded,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );


    ----------------------------------------------------------------
    -- GLOBAL END LOG
    ----------------------------------------------------------------
    v_proc_end_ts := NOW();
    v_proc_duration_sec := EXTRACT(EPOCH FROM (v_proc_end_ts - v_proc_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,          -- we keep the original start
        v_proc_end_ts,            -- final end
        NULL,                     -- rows_loaded (not summed here, can be NULL)
        v_proc_status,            -- 'OK' or 'ERROR'
        LEFT(v_proc_msg, 250),    -- "procedure completed successfully" or "one or more phases failed"
        v_proc_duration_sec
    );

    RETURN updated_tables;

END;
$$;