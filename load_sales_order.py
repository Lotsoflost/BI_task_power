from datetime import datetime

import pandas as pd
from sqlalchemy import text
from sqlalchemy.orm import Session

import utils
from utils import ENGINE

if __name__ == '__main__':
    for sheet_name, unique_key in utils.SheetNames.get_all():
        df = pd.read_excel(
            open(utils.SRC_FILE, mode='rb'),
            sheet_name=sheet_name,
        )
        print(f'Load data for {sheet_name}')

        df = df.rename(
            columns={name: name.lower().replace(" ", "_") for name in df.columns}
        )
        # for col in df.columns:
        #     c = df[col]
        #     print(col, 'overall', len(c), 'uniques:', c.nunique())
        # continue
        df['update_ts'] = datetime.now()

        df.info()
        # Write DataFrame to PostgreSQL table
        src_table = sheet_name.lower().replace(" ", "_")
        t_table = src_table+"_temp"
        df.to_sql(
            name=t_table,  # Table name
            con=ENGINE,  # Database connection
            schema=utils.DB_SCHEMA,  # Schema name (optional)
            if_exists='replace',  # Options: 'fail', 'replace', 'append'
            index=False  # Don't write DataFrame index as a column
        )
        print("Data successfully written to PostgreSQL!")

        session = Session(ENGINE)
        columns = list(map(str, df.columns))
        insert_sql = f"""
            WITH cte as (
                SELECT {','.join([f't.{c}' for c in columns])} 
                FROM {utils.DB_SCHEMA}.{t_table} t
                LEFT JOIN {utils.DB_SCHEMA}.{src_table} src ON src.{unique_key} = t.{unique_key}
                WHERE src.{unique_key} IS NULL 
            )
            INSERT INTO {utils.DB_SCHEMA}.{src_table} ({','.join(columns)})
            SELECT {','.join(columns)} FROM cte
        """
        print(insert_sql)
        result = session.execute(text(insert_sql))
        print(f'Was inserted {result.rowcount} records')

        insert_sql = f"""
            WITH cte as (
                SELECT {','.join([f't.c' for c in columns])} 
                FROM {t_table} t
                LEFT JOIN {src_table} src ON src.{unique_key} = t.{unique_key}
                WHERE src.{unique_key} IS NULL 
            )
            INSERT INTO {src_table} ({','.join(columns)})
            SELECT {','.join(columns)} FROM cte
        """
        print(insert_sql)
        session.execute(text(insert_sql))
