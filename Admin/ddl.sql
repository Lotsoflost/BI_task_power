/*===============================================================================
URL..................: admin/tables/etl_log
Activity.............: ETL - Centralized execution log table
Description..........:
    Stores step- and run-level audit entries produced by ETL components
    (Python loaders, stored procedures). Each row is an immutable record with
    timestamps, status, message, and optional row count + duration.

Owner................: Olga Pankova
Retention............: As per platform policy (no automatic purge here)
Change History.......:
    2025-10-29  OP  Initial create with duration_sec and identity PK
===============================================================================*/

CREATE TABLE IF NOT EXISTS admin.etl_log (
    -- Surrogate key
    order_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Emitter / scope (e.g., 'adventure_works_test')
    schema_name     varchar(250),

    -- Operation name (procedure/step identifier)
    procedure_name  varchar(250),

    -- Timing
    start_ts        timestamp,
    end_ts          timestamp,

    -- Outcome details
    msg             varchar(250),
    rows            integer,          -- affected rows (nullable)
    status          varchar(50),      -- e.g., STARTED | OK | ERROR
    duration_sec    numeric           -- elapsed time in seconds
);

ALTER TABLE admin.etl_log OWNER TO postgres;

-- Optional, but useful: inline documentation
COMMENT ON TABLE admin.etl_log                 IS 'Centralized ETL audit log (immutable append-only).';
COMMENT ON COLUMN admin.etl_log.order_id       IS 'Surrogate identity primary key.';
COMMENT ON COLUMN admin.etl_log.schema_name    IS 'Logical schema/area that emitted the log entry.';
COMMENT ON COLUMN admin.etl_log.procedure_name IS 'Procedure or step name that produced the entry.';
COMMENT ON COLUMN admin.etl_log.start_ts       IS 'Operation start timestamp.';
COMMENT ON COLUMN admin.etl_log.end_ts         IS 'Operation end timestamp.';
COMMENT ON COLUMN admin.etl_log.msg            IS 'Short status message (<=250 chars).';
COMMENT ON COLUMN admin.etl_log.rows           IS 'Rows affected; NULL when not applicable.';
COMMENT ON COLUMN admin.etl_log.status         IS 'Status label, e.g., STARTED/OK/ERROR.';
COMMENT ON COLUMN admin.etl_log.duration_sec   IS 'Elapsed time in seconds.';


create sequence admin.etl_log_order_id_seq;

alter sequence admin.etl_log_order_id_seq owner to postgres;

alter sequence admin.etl_log_order_id_seq owned by admin.etl_log.order_id;

