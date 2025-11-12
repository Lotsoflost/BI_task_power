from sqlalchemy import text
import pandas as pd
import re
from datetime import datetime

import utils
from utils import ENGINE


def record_log(
        proc_name: str,
        start_ts: datetime,
        end_ts: datetime,
        rows_loaded: int,
        status: str,
        message: str,
        duration_sec: int
):
    # Write a single ETL log entry via admin.sp_log_etl
    with ENGINE.begin() as conn:
        conn.execute(
            text("""
                CALL admin.sp_log_etl(
                    :schema_name,
                    :proc_name,
                    :start_ts,
                    :end_ts,
                    :rows_loaded,
                    :status,
                    :msg,
                    :duration_sec
                )
            """),
            {
                "schema_name": utils.DB_SCHEMA,
                "proc_name": proc_name,
                "start_ts": start_ts,
                "end_ts": end_ts,
                "rows_loaded": rows_loaded,
                "status": status,
                "msg": message,
                "duration_sec": duration_sec,
            }
        )


if __name__ == '__main__':
    # -------------------------------------------------
    # GLOBAL RUN CONTEXT
    # -------------------------------------------------
    global_start_ts = datetime.now()
    global_status = "OK"
    global_msg = "initial temp load completed successfully"
    total_rows_loaded = 0

    print("=== BEGIN initial temp load ===")

    # Iterate over all source sheets defined in utils.SheetNames
    for sheet_name, unique_key in utils.SheetNames.get_all():

        # ---------- Read input ----------
        df = pd.read_excel(
            open(utils.SRC_FILE, mode='rb'),
            sheet_name=sheet_name,
        )
        print(f'Load data for {sheet_name}')

        # ---------- Normalize column names ----------
        df.columns = [
            re.sub(r'[^a-z0-9]+', '_', col.lower()).strip('_')
            for col in df.columns
        ]

        # Technical column (ingestion timestamp)
        df['update_ts'] = datetime.now()

        # Resolve destination table names
        src_table = "src_" + re.sub(r'[^a-z0-9]+', '_', sheet_name.lower()).strip('_')
        t_table = src_table + "_temp"

        # Per-sheet logging context
        start_ts = datetime.now()
        status = "OK"
        message = f"{t_table} loaded successfully"
        rows_loaded = 0

        try:
            # ---------- Write DataFrame into *_temp ----------
            df.to_sql(
                name=t_table,
                con=ENGINE,
                schema=utils.DB_SCHEMA,
                if_exists='replace',
                index=False
            )

            rows_loaded = len(df)
            total_rows_loaded += rows_loaded

            print(f"Data successfully written to {utils.DB_SCHEMA}.{t_table} ({rows_loaded} rows).")

        except Exception as e:
            status = "ERROR"
            message = f"Failed to load {t_table}: {e}"
            global_status = "ERROR"
            global_msg = "one or more temp tables failed to load"
            print(message)

        finally:
            end_ts = datetime.now()
            duration_sec = (end_ts - start_ts).total_seconds()
            record_log(f'load {t_table}', start_ts, end_ts, rows_loaded, status, message[:250], duration_sec)

    # -------------------------------------------------
    # AFTER ALL TEMP TABLES ARE LOADED
    # -------------------------------------------------
    mid_ts = datetime.now()

    record_log(
        f'initial_temp_load_all_sheets',
        global_start_ts,
        mid_ts,
        total_rows_loaded,
        global_status,
        global_msg[:250],
        (mid_ts - global_start_ts).total_seconds()
    )

    # -------------------------------------------------
    # NOW CALL fn_upload_src (only if temp load OK)
    # -------------------------------------------------
    if global_status == "OK":
        print("Calling fn_upload_src() to push temp -> SRC...")

        upload_start_ts = datetime.now()
        upload_status = "OK"
        upload_msg = "fn_upload_src completed successfully"

        updated_tables = ''
        try:
            with ENGINE.begin() as conn:
                result = conn.execute(
                    text(f"SELECT {utils.DB_SCHEMA}.fn_upload_src() as record;")
                ).fetchone()
                updated_tables = result.record
            print("fn_upload_src() finished.")

        except Exception as e:
            upload_status = "ERROR"
            upload_msg = f"fn_upload_src failed: {e}"
            global_status = "ERROR"
            global_msg = "temp load ok, but fn_upload_src failed"
            print(upload_msg)

        finally:
            upload_end_ts = datetime.now()
            upload_duration_sec = (upload_end_ts - upload_start_ts).total_seconds()
            record_log(
                f'fn_upload_src',
                upload_start_ts,
                upload_end_ts,
                None,
                upload_status,
                upload_msg[:250],
                upload_duration_sec
            )

        # Trigger downstream refreshes based on fn_upload_src result
        if updated_tables:
            tables = [table for table, value in updated_tables.items() if value > 1]
            with ENGINE.begin() as conn:
                for upd_table in tables:
                    if upd_table == "fct_sales_data":
                        conn.execute(text(f"CALL {utils.DB_SCHEMA}.sp_refresh_fct();"))
                    else:
                        conn.execute(text(f"CALL {utils.DB_SCHEMA}.sp_refresh_dims('{upd_table}');"))
                    print(f"{upd_table} is refreshed.")

    # -------------------------------------------------
    # Datamart refresh (Materialized View)  ⬅️ SEPARATE CONTEXT
    # -------------------------------------------------
    try:
        dm_start = datetime.now()
        with ENGINE.begin() as conn:
            conn.execute(text(f"CALL {utils.DB_SCHEMA}.sp_refresh_sales_datamart();"))
        print("Materialized view mv_sales_datamart_all_joint refreshed.")
        dm_status = "OK"
        dm_msg = "sp_refresh_sales_datamart completed"
    except Exception as e:
        dm_status = "ERROR"
        dm_msg = f"sp_refresh_sales_datamart failed: {e}"
    finally:
        dm_end = datetime.now()
        record_log(
            f"{utils.DB_SCHEMA}.sp_refresh_sales_datamart",
            dm_start,
            dm_end,
            None,
            dm_status,
            dm_msg[:250],
            (dm_end - dm_start).total_seconds()
        )

    # -------------------------------------------------
    # FINAL GLOBAL LOG (whole end-to-end run)
    # -------------------------------------------------
    global_end_ts = datetime.now()
    final_duration_sec = (global_end_ts - global_start_ts).total_seconds()

    final_msg = (
        "initial load + upload_src completed successfully"
        if global_status == "OK"
        else "one or more steps failed during initial load or upload_src"
    )

    record_log(
        f'initial_full_load_pipeline',
        global_start_ts,
        global_end_ts,
        total_rows_loaded,
        global_status,
        final_msg[:250],
        final_duration_sec
    )

    print("=== END initial temp load pipeline ===")
