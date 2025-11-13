CREATE OR REPLACE PROCEDURE adventure_works_test.sp_refresh_dims(
    p_tabname varchar(250)  -- expected values:
                            -- dim_customer_data,
                            -- dim_date_data,
                            -- dim_product_data,
                            -- dim_reseller_data,
                            -- dim_sales_order_data,
                            -- dim_sales_territory_data
)
LANGUAGE plpgsql
AS $$
/*===============================================================================
URL..................: adventure_works/procedures/sp_refresh_dims
Activity.............: ETL - Refresh dimension (DIM) layer
Description..........:
    Rebuilds or incrementally updates dimension tables in
    'adventure_works_test' schema. The procedure refreshes a single DIM table
    specified by parameter p_tabname, performing one of the following actions:
      - Full rebuild (TRUNCATE + INSERT) for slowly changing dimensions
      - Incremental UPSERT / MERGE for transactional dimensions
      - Writes detailed ETL logs for each branch execution

    Supported dimension tables:
      - dim_customer_data
      - dim_date_data
      - dim_product_data
      - dim_reseller_data
      - dim_sales_order_data
      - dim_sales_territory_data

Owner................: Olga Pankova
Role in ETL..........: SRC -> DIM enrichment and historicalization step
Audit / Logging......:
    - Per-branch logging via admin.sp_log_etl
    - Global START and END audit log for the entire procedure
Execution Example....: CALL adventure_works_test.sp_refresh_dims('dim_product_data');
Change History.......:
    2025-10-28  OP  Initial version with per-branch execution blocks
    2025-10-29  OP  Converted PHASE → BRANCH, unified English logs and comments
    2025-10-29  OP  Added ELSE branch for unsupported table names
    2025-10-29  OP  Standardized START/END global logging
===============================================================================*/

DECLARE
    v_proc_name       text := 'sp_refresh_dims';
    v_schema_name     text := 'adventure_works_test';

    -- Per-branch runtime metadata
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
    v_proc_status          text := 'OK';      -- assume success unless a branch fails
    v_proc_msg             text := 'procedure completed successfully';
BEGIN
    ----------------------------------------------------------------
    -- GLOBAL START LOG
    ----------------------------------------------------------------
    v_proc_start_ts := NOW();

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,                      -- start_ts
        v_proc_start_ts,                      -- end_ts (same at start)
        NULL,                                 -- rows_loaded not known yet
        'STARTED',
        'sp_refresh_dims execution started',
        0
    );

    ----------------------------------------------------------------
    -- BRANCH 1: dim_customer_data (full rebuild with SCD history logic)
    ----------------------------------------------------------------
    IF p_tabname = 'dim_customer_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            -- full rebuild: truncate target
            TRUNCATE adventure_works_test.dim_customer_data;

            -- temp table with the same structure
            DROP TABLE IF EXISTS tmp_dim_customer_data;
            CREATE TEMP TABLE tmp_dim_customer_data
            (
                LIKE adventure_works_test.dim_customer_data INCLUDING ALL
            )
            ON COMMIT DROP;

            INSERT INTO tmp_dim_customer_data (
                customerkey,
                customer_id,
                customer,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            WITH CTE_ORDERED AS (
                SELECT
                    customerkey,
                    customer_id,
                    customer,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    row_number() OVER (
                        PARTITION BY customerkey
                        ORDER BY update_ts ASC
                    ) AS rn
                FROM adventure_works_test.src_customer_data
            ),
            CTE_VALIDATED AS (
                SELECT
                    customerkey,
                    customer_id,
                    customer,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    rn,
                    ( LEAD(update_ts) OVER (
                          PARTITION BY customerkey
                          ORDER BY rn
                      )::date - 1
                    ) AS valid_to,
                    LEAD(update_ts) OVER (
                        PARTITION BY customerkey
                        ORDER BY update_ts
                    )::date AS next_valid_from
                FROM CTE_ORDERED
            ),
            CTE_ALL_VALIDATED AS (
                SELECT
                    customerkey,
                    customer_id,
                    customer,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    COALESCE(
                        LEAD(next_valid_from) OVER (
                            PARTITION BY customerkey
                            ORDER BY rn DESC
                        ),
                        '2000-01-01'
                    ) AS valid_from,
                    COALESCE(valid_to, '3000-01-01') AS valid_to
                FROM CTE_VALIDATED
            )
            SELECT
                customerkey,
                customer_id,
                customer,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                CASE
                    WHEN NOW()::date BETWEEN valid_from AND valid_to
                    THEN 1 ELSE 0
                END AS is_valid
            FROM CTE_ALL_VALIDATED
            ORDER BY customerkey DESC, update_ts DESC;

            SELECT COUNT(*) INTO v_rows_loaded
            FROM tmp_dim_customer_data;

            INSERT INTO adventure_works_test.dim_customer_data (
                customerkey,
                customer_id,
                customer,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            SELECT
                customerkey,
                customer_id,
                customer,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            FROM tmp_dim_customer_data;

            v_msg := 'dim_customer_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- BRANCH 2: dim_date_data (append new rows only)
    ----------------------------------------------------------------
    ELSIF p_tabname = 'dim_date_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            INSERT INTO adventure_works_test.dim_date_data (
                datekey,
                date,
                fiscal_year,
                fiscal_quarter,
                month,
                full_date,
                monthkey,
                update_ts
            )
            SELECT
                s.datekey,
                s.date,
                s.fiscal_year,
                s.fiscal_quarter,
                s.month,
                s.full_date,
                s.monthkey,
                s.update_ts
            FROM adventure_works_test.src_date_data s
            LEFT JOIN adventure_works_test.dim_date_data d
                ON s.datekey = d.datekey
            WHERE d.datekey IS NULL;

            GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
            v_msg := 'dim_date_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- BRANCH 3: dim_product_data (full rebuild + SCD-like ranges)
    ----------------------------------------------------------------
    ELSIF p_tabname = 'dim_product_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            TRUNCATE adventure_works_test.dim_product_data;

            DROP TABLE IF EXISTS tmp_dim_product_data;
            CREATE TEMP TABLE tmp_dim_product_data
            (
                LIKE adventure_works_test.dim_product_data INCLUDING ALL
            )
            ON COMMIT DROP;

            INSERT INTO tmp_dim_product_data (
                productkey,
                sku,
                product,
                standard_cost,
                color,
                list_price,
                model,
                subcategory,
                category,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            WITH CTE_ORDERED AS (
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
                    update_ts,
                    row_number() OVER (
                        PARTITION BY productkey
                        ORDER BY update_ts ASC
                    ) AS rn
                FROM adventure_works_test.src_product_data
            ),
            CTE_VALIDATED AS (
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
                    update_ts,
                    rn,
                    ( LEAD(update_ts) OVER (
                          PARTITION BY productkey
                          ORDER BY rn
                      )::date - 1
                    ) AS valid_to,
                    LEAD(update_ts) OVER (
                        PARTITION BY productkey
                        ORDER BY update_ts
                    )::date AS next_valid_from
                FROM CTE_ORDERED
            ),
            CTE_ALL_VALIDATED AS (
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
                    update_ts,
                    COALESCE(
                        LEAD(next_valid_from) OVER (
                            PARTITION BY productkey
                            ORDER BY rn DESC
                        ),
                        '2000-01-01'
                    ) AS valid_from,
                    COALESCE(valid_to, '3000-01-01') AS valid_to
                FROM CTE_VALIDATED
            )
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
                update_ts,
                valid_from,
                valid_to,
                CASE
                    WHEN NOW()::date BETWEEN valid_from AND valid_to
                    THEN 1 ELSE 0
                END AS is_valid
            FROM CTE_ALL_VALIDATED
            ORDER BY productkey DESC, update_ts DESC;

            SELECT COUNT(*) INTO v_rows_loaded
            FROM tmp_dim_product_data;

            INSERT INTO adventure_works_test.dim_product_data (
                productkey,
                sku,
                product,
                standard_cost,
                color,
                list_price,
                model,
                subcategory,
                category,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
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
                update_ts,
                valid_from,
                valid_to,
                is_valid
            FROM tmp_dim_product_data;

            v_msg := 'dim_product_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- BRANCH 4: dim_reseller_data (full rebuild + SCD-like ranges)
    ----------------------------------------------------------------
    ELSIF p_tabname = 'dim_reseller_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            TRUNCATE adventure_works_test.dim_reseller_data;

            DROP TABLE IF EXISTS tmp_dim_reseller_data;
            CREATE TEMP TABLE tmp_dim_reseller_data
            (
                LIKE adventure_works_test.dim_reseller_data INCLUDING ALL
            )
            ON COMMIT DROP;

            INSERT INTO tmp_dim_reseller_data (
                resellerkey,
                reseller_id,
                business_type,
                reseller,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            WITH CTE_ORDERED AS (
                SELECT
                    resellerkey,
                    reseller_id,
                    business_type,
                    reseller,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    row_number() OVER (
                        PARTITION BY resellerkey
                        ORDER BY update_ts ASC
                    ) AS rn
                FROM adventure_works_test.src_reseller_data
            ),
            CTE_VALIDATED AS (
                SELECT
                    resellerkey,
                    reseller_id,
                    business_type,
                    reseller,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    rn,
                    ( LEAD(update_ts) OVER (
                          PARTITION BY resellerkey
                          ORDER BY rn
                      )::date - 1
                    ) AS valid_to,
                    LEAD(update_ts) OVER (
                        PARTITION BY resellerkey
                        ORDER BY update_ts
                    )::date AS next_valid_from
                FROM CTE_ORDERED
            ),
            CTE_ALL_VALIDATED AS (
                SELECT
                    resellerkey,
                    reseller_id,
                    business_type,
                    reseller,
                    city,
                    state_province,
                    country_region,
                    postal_code,
                    update_ts,
                    COALESCE(
                        LEAD(next_valid_from) OVER (
                            PARTITION BY resellerkey
                            ORDER BY rn DESC
                        ),
                        '2000-01-01'
                    ) AS valid_from,
                    COALESCE(valid_to, '3000-01-01') AS valid_to
                FROM CTE_VALIDATED
            )
            SELECT
                resellerkey,
                reseller_id,
                business_type,
                reseller,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                CASE
                    WHEN NOW()::date BETWEEN valid_from AND valid_to
                    THEN 1 ELSE 0
                END AS is_valid
            FROM CTE_ALL_VALIDATED
            ORDER BY resellerkey DESC, update_ts DESC;

            SELECT COUNT(*) INTO v_rows_loaded
            FROM tmp_dim_reseller_data;

            INSERT INTO adventure_works_test.dim_reseller_data (
                resellerkey,
                reseller_id,
                business_type,
                reseller,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            SELECT
                resellerkey,
                reseller_id,
                business_type,
                reseller,
                city,
                state_province,
                country_region,
                postal_code,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            FROM tmp_dim_reseller_data;

            v_msg := 'dim_reseller_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- BRANCH 5: dim_sales_order_data (upsert / merge latest version)
    ----------------------------------------------------------------
    ELSIF p_tabname = 'dim_sales_order_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            WITH CTE_CORRECTED AS (
                SELECT
                    channel,
                    salesorderlinekey,
                    (salesorderlinekey / 1000)::text AS salesordertext,
                    sales_order,
                    sales_order_line,
                    update_ts
                FROM adventure_works_test.src_sales_order_data
            ),
            CTE_RANKED AS (
                SELECT
                    channel,
                    salesorderlinekey,
                    salesordertext,
                    sales_order,
                    sales_order_line,
                    update_ts,
                    row_number() OVER (
                        PARTITION BY salesorderlinekey
                        ORDER BY update_ts DESC
                    ) AS rn
                FROM CTE_CORRECTED
                WHERE sales_order      LIKE '%' || salesordertext || '%'
                  AND sales_order_line LIKE '%' || salesordertext || '%'
            ),
            CTE_PREPARE AS (
                SELECT
                    channel,
                    salesorderlinekey,
                    sales_order,
                    sales_order_line,
                    update_ts
                FROM CTE_RANKED
                WHERE rn = 1
            )
            MERGE INTO adventure_works_test.dim_sales_order_data AS d
            USING CTE_PREPARE AS s
            ON (d.salesorderlinekey = s.salesorderlinekey)
            WHEN MATCHED THEN
                UPDATE SET
                    channel          = s.channel,
                    sales_order      = s.sales_order,
                    sales_order_line = s.sales_order_line,
                    update_ts        = s.update_ts
            WHEN NOT MATCHED THEN
                INSERT (
                    salesorderlinekey,
                    channel,
                    sales_order,
                    sales_order_line,
                    update_ts
                )
                VALUES (
                    s.salesorderlinekey,
                    s.channel,
                    s.sales_order,
                    s.sales_order_line,
                    s.update_ts
                );

            GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
            v_msg := 'dim_sales_order_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- BRANCH 6: dim_sales_territory_data (full rebuild + SCD-like ranges)
    ----------------------------------------------------------------
    ELSIF p_tabname = 'dim_sales_territory_data' THEN

        BEGIN
            v_step_start_ts := NOW();
            v_rows_loaded   := 0;
            v_status        := 'OK';
            v_msg           := 'upload completed';

            TRUNCATE adventure_works_test.dim_sales_territory_data;

            DROP TABLE IF EXISTS tmp_dim_sales_territory_data;
            CREATE TEMP TABLE tmp_dim_sales_territory_data
            (
                LIKE adventure_works_test.dim_sales_territory_data INCLUDING ALL
            )
            ON COMMIT DROP;

            INSERT INTO tmp_dim_sales_territory_data (
                salesterritorykey,
                region,
                country,
                group_region,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            WITH CTE_ORDERED AS (
                SELECT
                    salesterritorykey,
                    region,
                    country,
                    "group" AS group_region,
                    update_ts,
                    row_number() OVER (
                        PARTITION BY salesterritorykey
                        ORDER BY update_ts ASC
                    ) AS rn
                FROM adventure_works_test.src_sales_territory_data
            ),
            CTE_VALIDATED AS (
                SELECT
                    salesterritorykey,
                    region,
                    country,
                    group_region,
                    update_ts,
                    rn,
                    ( LEAD(update_ts) OVER (
                          PARTITION BY salesterritorykey
                          ORDER BY rn
                      )::date - 1
                    ) AS valid_to,
                    LEAD(update_ts) OVER (
                        PARTITION BY salesterritorykey
                        ORDER BY update_ts
                    )::date AS next_valid_from
                FROM CTE_ORDERED
            ),
            CTE_ALL_VALIDATED AS (
                SELECT
                    salesterritorykey,
                    region,
                    country,
                    group_region,
                    update_ts,
                    COALESCE(
                        LEAD(next_valid_from) OVER (
                            PARTITION BY salesterritorykey
                            ORDER BY rn DESC
                        ),
                        '2000-01-01'
                    ) AS valid_from,
                    COALESCE(valid_to, '3000-01-01') AS valid_to
                FROM CTE_VALIDATED
            )
            SELECT
                salesterritorykey,
                region,
                country,
                group_region,
                update_ts,
                valid_from,
                valid_to,
                CASE
                    WHEN NOW()::date BETWEEN valid_from AND valid_to
                    THEN 1 ELSE 0
                END AS is_valid
            FROM CTE_ALL_VALIDATED
            ORDER BY salesterritorykey DESC, update_ts DESC;

            SELECT COUNT(*) INTO v_rows_loaded
            FROM tmp_dim_sales_territory_data;

            INSERT INTO adventure_works_test.dim_sales_territory_data (
                salesterritorykey,
                region,
                country,
                group_region,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            )
            SELECT
                salesterritorykey,
                region,
                country,
                group_region,
                update_ts,
                valid_from,
                valid_to,
                is_valid
            FROM tmp_dim_sales_territory_data;

            v_msg := 'dim_sales_territory_data uploaded successfully';

        EXCEPTION
            WHEN OTHERS THEN
                v_status      := 'ERROR';
                v_msg         := 'upload failed: ' || SQLERRM;
                v_proc_status := 'ERROR';
                v_proc_msg    := 'branch failed';
        END;

        v_step_end_ts   := NOW();
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    -- UNKNOWN BRANCH
    ----------------------------------------------------------------
    ELSE
        -- table name not supported
        v_proc_status := 'ERROR';
        v_proc_msg    := 'unsupported table name: ' || COALESCE(p_tabname, '<NULL>');

        -- optional: write a branch-like log row with 0 rows and ERROR
        v_step_start_ts := NOW();
        v_step_end_ts   := NOW();
        v_rows_loaded   := 0;
        v_status        := 'ERROR';
        v_msg           := v_proc_msg;
        v_duration_sec  := EXTRACT(EPOCH FROM (v_step_end_ts - v_step_start_ts));

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
    END IF;

    ----------------------------------------------------------------
    -- GLOBAL END LOG
    ----------------------------------------------------------------
    v_proc_end_ts := NOW();
    v_proc_duration_sec := EXTRACT(EPOCH FROM (v_proc_end_ts - v_proc_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,          -- initial start
        v_proc_end_ts,            -- final end
        NULL,                     -- total rows_loaded not aggregated here
        v_proc_status,            -- 'OK' or 'ERROR'
        LEFT(v_proc_msg, 250),    -- message
        v_proc_duration_sec
    );

END;
$$;
