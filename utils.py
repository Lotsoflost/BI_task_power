from enum import Enum
import pandas as pd
from sqlalchemy import create_engine

# Database connection parameters
db_config = {
    'host': 'localhost',
    'port': 5432,
    'database': 'NewDB',
    'user': 'postgres',
    'password': '***'
}

# Create connection string
connection_string = f"postgresql://{db_config['user']}:{db_config['password']}@{db_config['host']}:{db_config['port']}/{db_config['database']}"

# Create SQLAlchemy engine
ENGINE = create_engine(connection_string)

SRC_FILE = 'C:\\Users\\henry\\PycharmProjects\\BI_task\\AdventureWorks Sales.xlsx'
DB_SCHEMA = 'adventure_works_test'

class SheetNames:
    SALES_ORDER = 'Sales Order_data'
    SALES_TERRITORY = 'Sales Territory_data'
    SALES = 'Sales_data'
    RESELLER = 'Reseller_data'
    DATE = 'Date_data'
    PRODUCT = 'Product_data'
    CUSTOMER = 'Customer_data'

    @classmethod
    def get_all(cls):
        return [
            (cls.SALES_ORDER, 'salesorderlinekey'),
            (cls.SALES_TERRITORY, 'salesterritorykey'),
            (cls.SALES, 'salesorderlinekey'),
            (cls.RESELLER, 'resellerkey'),
            (cls.DATE, 'datekey'),
            (cls.PRODUCT, 'productkey'),
            (cls.CUSTOMER, 'customerkey')
        ]
