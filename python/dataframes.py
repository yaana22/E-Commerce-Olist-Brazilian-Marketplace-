from sqlalchemy import create_engine
from dotenv import load_dotenv
import pandas as pd
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")

if not SUPABASE_URL:
    raise ValueError("SUPABASE_URL is not set in the environment variables.")

engine = create_engine(SUPABASE_URL)

print("✅ Connected to Supabase")

customers_df = pd.read_sql(
    "SELECT * FROM gold.dim_customers;",
    engine
)

products_df = pd.read_sql(
    "SELECT * FROM gold.dim_products;",
    engine
)

sellers_df = pd.read_sql(
    "SELECT * FROM gold.dim_sellers;",
    engine
)

date_df = pd.read_sql(
    "SELECT * FROM gold.dim_date;",
    engine
)

orders_df = pd.read_sql(
    "SELECT * FROM gold.fact_orders;",
    engine
)

order_items_df = pd.read_sql(
    "SELECT * FROM gold.fact_order_items;",
    engine
)

payments_df = pd.read_sql(
    "SELECT * FROM gold.fact_payments;",
    engine
)

reviews_df = pd.read_sql(
    "SELECT * FROM gold.fact_reviews;",
    engine
)