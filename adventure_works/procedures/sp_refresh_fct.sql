CREATE OR REPLACE PROCEDURE adventure_works_test.sp_refresh_fct()
LANGUAGE plpgsql
AS $$
/*===============================================================================
URL..................: adventure_works/procedures/sp_refresh_fct
Activity.............: ETL - Refresh Fact Layer
Description..........:
    Rebuilds the fact table adventure_works_test.fct_sales_data
    from the latest version of each sales order line in
    adventure_works_test.src_sales_data.

    Steps:
      - take only the most recent record per salesorderlinekey
        (by update_ts descending),
      - convert integer date keys (YYYYMMDD) into proper DATE columns,
      - truncate the fact table,
      - insert the cleaned data,
      - write ETL audit logs.

Owner................: Olga Pankova
Role in ETL..........: Source layer (SRC) → Fact layer (FCT)
Audit / Logging......:
    - "STARTED" log when the procedure begins
    - Final log with total rows loaded and status
Execution Example....: CALL adventure_works_test.sp_refresh_fct();
Change History.......:
    2025-10-28  OP  Initial version
    2025-10-28  OP  Added START/END audit logging via admin.sp_log_etl
    2025-10-28  OP  Minor cleanup of comments and status handling
===============================================================================*/
DECLARE
    v_proc_name            text := 'sp_refresh_fct';
    v_schema_name          text := 'adventure_works_test';

    -- Procedure-level tracking for audit logging
    v_rows_loaded          integer := 0;
    v_status               text    := 'OK';
    v_msg                  text    := 'refresh completed';
    v_proc_start_ts        timestamp;
    v_proc_end_ts          timestamp;
    v_proc_duration_sec    numeric;
    v_proc_status          text    := 'OK';      -- final status of the whole procedure
    v_proc_msg             text    := 'procedure completed successfully';
BEGIN
    ----------------------------------------------------------------
    -- Audit log: procedure start
    ----------------------------------------------------------------
    v_proc_start_ts := NOW();

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,        -- start_ts
        v_proc_start_ts,        -- end_ts (same as start at this point)
        NULL,                   -- rows_loaded (not known yet)
        'STARTED',              -- status
        'sp_refresh_fct execution started', -- msg
        0                       -- duration_sec so far
    );

    ----------------------------------------------------------------
    -- Refresh fct_sales_data
    -- Goal:
    --   1. Keep only the newest version of each salesorderlinekey.
    --   2. Convert date keys (YYYYMMDD numeric) to DATE.
    --   3. Truncate the fact table and reload it.
    ----------------------------------------------------------------

    -- optimistic defaults for this refresh block
    v_status := 'OK';
    v_msg := 'fct_sales_data refreshed successfully';
    v_rows_loaded := 0;

    BEGIN
        -- Clear the destination fact table
        TRUNCATE adventure_works_test.fct_sales_data;

        -- Build the latest version per line into a temp table
        DROP TABLE IF EXISTS tmp_sales_data;

        CREATE TEMP TABLE tmp_sales_data
        ON COMMIT DROP
        AS
        SELECT DISTINCT ON (s.salesorderlinekey)
               s.salesorderlinekey,
               s.resellerkey,
               s.customerkey,
               s.productkey,
               TO_DATE(s.orderdatekey::text, 'YYYYMMDD') AS orderdatekey,
               TO_DATE(s.duedatekey::text, 'YYYYMMDD')   AS duedatekey,
               TO_DATE(s.shipdatekey::text, 'YYYYMMDD')  AS shipdatekey,
               s.salesterritorykey,
               s.order_quantity,
               s.unit_price,
               s.extended_amount,
               s.unit_price_discount_pct,
               s.product_standard_cost,
               s.total_product_cost,
               s.sales_amount,
               s.update_ts
        FROM adventure_works_test.src_sales_data s
        ORDER BY
            s.salesorderlinekey,
            s.update_ts DESC;

        -- Row count after deduplication
        SELECT COUNT(*) INTO v_rows_loaded
        FROM tmp_sales_data;

        -- Load into the fact table
        INSERT INTO adventure_works_test.fct_sales_data (
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

    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg    := 'fct_sales_data refresh failed: ' || SQLERRM;
            v_proc_status := 'ERROR';
            v_proc_msg    := 'one or more steps failed';
    END;

    ----------------------------------------------------------------
    -- Audit log: procedure end
    ----------------------------------------------------------------
    v_proc_end_ts := NOW();
    v_proc_duration_sec := EXTRACT(EPOCH FROM (v_proc_end_ts - v_proc_start_ts));

    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_proc_start_ts,          -- original start
        v_proc_end_ts,            -- final end
        v_rows_loaded,            -- total rows inserted into fact
        v_proc_status,            -- 'OK' or 'ERROR'
        LEFT(v_proc_msg, 250),    -- status message
        v_proc_duration_sec
    );

END;
$$;
