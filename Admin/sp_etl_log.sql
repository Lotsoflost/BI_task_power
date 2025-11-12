CREATE OR REPLACE PROCEDURE admin.sp_log_etl(
    in_schema_name    text,
    in_procedure_name text,
    in_start_ts       timestamp,
    in_end_ts         timestamp,
    in_rows_loaded    integer,
    in_status         text,
    in_message        text,
    in_duration_sec   numeric
)
LANGUAGE plpgsql
AS $$
/*===============================================================================
URL..................: admin/procedures/sp_log_etl
Activity.............: ETL - Centralized execution logging
Description..........:
    Writes a single audit record into admin.etl_log. Designed to be called
    by ETL jobs (Python loaders, stored procedures) to persist step-level and
    run-level metadata: start/end timestamps, number of rows, status, message,
    and duration in seconds.

Owner................: Olga Pankova
Role in ETL..........: Cross-cutting audit / telemetry sink
Idempotency..........: Non-idempotent (always inserts a new row)
Concurrency..........: Safe; no locks beyond the single-row INSERT
Execution Example....:
    CALL admin.sp_log_etl(
        'adventure_works_test',
        'sp_refresh_dims(dim_product_data)',
        NOW(), NOW(), 1234, 'OK',
        'product dimension refreshed', 2.31
    );

Inputs................:
    in_schema_name     — schema or logical area emitting the log (e.g. 'adventure_works_test')
    in_procedure_name  — operation name (proc/step identifier)
    in_start_ts        — operation start timestamp
    in_end_ts          — operation end timestamp
    in_rows_loaded     — affected row count (nullable if N/A)
    in_status          — status label, e.g. 'OK' | 'ERROR' | 'STARTED'
    in_message         — short message (<= 250 chars recommended)
    in_duration_sec    — elapsed seconds (numeric)

Change History.......:
    2025-10-29  OP  Initial documented version (comments/header only)
===============================================================================*/

BEGIN
    -- Persist a single audit row into the centralized ETL log.
    INSERT INTO admin.etl_log (
        schema_name,
        procedure_name,
        start_ts,
        end_ts,
        rows,
        status,
        msg,
        duration_sec
    )
    VALUES (
        in_schema_name,
        in_procedure_name,
        in_start_ts,
        in_end_ts,
        in_rows_loaded,
        in_status,
        in_message,
        in_duration_sec
    );
END;
$$;
