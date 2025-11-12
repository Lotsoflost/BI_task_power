# 🧩 Adventure Works ETL Pipeline

**Author:** Olga Pankova  
**Environment:** PostgreSQL + SQLAlchemy + Pandas  
**Schema:** dynamically set via `utils.DB_SCHEMA`  
**Purpose:** End-to-end automated ETL pipeline for the *Adventure Works* analytical model.

---

## 📘 Overview

This project implements a fully automated ETL pipeline that:
1. Loads Excel source sheets into staging `_temp` tables.  
2. Invokes a database-side function `fn_upload_src()` to merge staging into persistent `SRC` tables.  
3. Refreshes all dependent dimension (`DIM`) and fact (`FCT`) tables.  
4. Rebuilds the final **materialized datamart view** used by Power BI and reporting tools.  
5. Writes detailed execution logs to the centralized table `admin.etl_log`.

All schema references are dynamic and based on `utils.DB_SCHEMA`, so the same code can run in any environment (e.g. `adventure_works_dev`, `adventure_works_test`, `adventure_works_prod`).

---

## ⚙️ Components

| Layer | Object / Script | Description |
|-------|------------------|--------------|
| **Python ETL** | `loader_pipeline.py` | Main runner: reads Excel, writes temp tables, calls DB procedures, logs steps. |
| **Logging** | `admin.sp_log_etl` | Central procedure for ETL logging (`admin.etl_log`). |
| **Database Procedures** | `sp_refresh_dims`, `sp_refresh_fct`, `sp_refresh_sales_datamart` | Handle incremental or full rebuilds of model layers. |
| **Database Function** | `fn_upload_src` | Merges data from `_temp` staging tables into persistent `SRC` tables. |
| **Datamart View** | `mv_sales_datamart_all_joint` | Materialized BI view joining all dimension and fact data. |

---

## 🧠 Pipeline Flow

```mermaid
flowchart TD
    A[Excel Source Sheets] --> B[Python Loader<br>loader_pipeline.py]
    B --> C[Temp Tables<br>src_*_temp]
    C --> D[fn_upload_src()<br>→ SRC Tables]
    D --> E[sp_refresh_dims / sp_refresh_fct]
    E --> F[sp_refresh_sales_datamart]
    F --> G[Materialized View<br>mv_sales_datamart_all_joint]
    G --> H[Power BI / Reporting]
    B --> I[admin.etl_log<br>via sp_log_etl]
