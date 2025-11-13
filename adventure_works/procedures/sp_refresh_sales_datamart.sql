/*===============================================================================
URL..................: adventure_works_test/procedures/sp_refresh_sales_datamart
Activity.............: ETL - Refresh materialized BI datamart view
Description..........:
    Refreshes the materialized view mv_sales_datamart_all_joint that aggregates
    fact and dimension tables into a pre-joined BI snapshot. The procedure also
    logs execution details to admin.etl_log via admin.sp_log_etl.

Owner................: Olga Pankova
Role in ETL..........: Final stage after all DIM/FCT refreshes
Execution Example....: CALL adventure_works_test.sp_refresh_sales_datamart();
Change History.......:
    2025-10-30  OP  Initial version with ETL logging
===============================================================================*/
CREATE OR REPLACE PROCEDURE adventure_works_test.sp_refresh_sales_datamart()
LANGUAGE plpgsql
AS $$
DECLARE
    v_proc_name      text := 'sp_refresh_sales_datamart';
    v_schema_name    text := 'adventure_works_test';
    v_start_ts       timestamp := now();
    v_end_ts         timestamp;
    v_status         text := 'OK';
    v_msg            text := 'Sales datamart refreshed successfully';
    v_duration_sec   numeric;
BEGIN
    BEGIN
        -- Refresh the materialized view (concurrently if possible)
        REFRESH MATERIALIZED VIEW CONCURRENTLY adventure_works_test.mv_sales_datamart_all_joint;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_msg := 'Refresh failed: ' || SQLERRM;
    END;

    v_end_ts := now();
    v_duration_sec := extract(epoch FROM (v_end_ts - v_start_ts));

    -- Write audit log
    CALL admin.sp_log_etl(
        v_schema_name,
        v_proc_name,
        v_start_ts,
        v_end_ts,
        NULL,
        v_status,
        LEFT(v_msg, 250),
        v_duration_sec
    );

    RAISE NOTICE '%', v_msg;
END;
$$;
