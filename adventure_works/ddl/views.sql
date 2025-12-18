CREATE  OR REPLACE VIEW V_SALES_DATAMART as

(select f.salesorderlinekey,
       f.resellerkey,
       f.customerkey,
       f.productkey,
       f.orderdatekey,
       f.duedatekey,
       f.shipdatekey,
       f.salesterritorykey,
       f.order_quantity,
       f.unit_price,
       f.extended_amount,
       f.unit_price_discount_pct,
       f.product_standard_cost,
       f.total_product_cost,
       f.sales_amount,
      -- c.customer customer_name,
       case when c.city  != '[Not Applicable]' then c.city  else r.city end as city_combined,
       case when c.state_province  != '[Not Applicable]' then c.state_province  else r.state_province end as state_province_combined,
       case when c.country_region  != '[Not Applicable]' then c.country_region  else r.country_region end as country_region_combined,
      -- case when c.postal_code  != '[Not Applicable]' then c.postal_code  else r.postal_code end as postal_code_combined,
       p.sku sku_product,
       p.product product_name,
       --p.color color_product,
       list_price list_price_product,
       p.model model_product,
       p.subcategory subcategory_product,
       p.category category_product,
       r.business_type business_type_reseller,
       r.reseller reseller_name,
       so.channel channel_sales_order,
       so.sales_order,
       --so.sales_order_line,
       st.region region_territory,
       st.country country_territory,
       st.group_region group_region_territory


from fct_sales_data f
join dim_customer_data c
    on f.customerkey = c.customerkey
    and f.orderdatekey between c.valid_from and c.valid_to
join dim_product_data p
    on p.productkey = f.productkey and f.orderdatekey between p.valid_from and p.valid_to
join dim_reseller_data r
    on r.resellerkey = f.resellerkey and f.orderdatekey between r.valid_from and r.valid_to
join dim_date_data d
    on d.date = f.orderdatekey
join dim_sales_order_data so
    on so.salesorderlinekey = f.salesorderlinekey
join dim_sales_territory_data st
    on st.salesterritorykey = f.salesterritorykey and f.orderdatekey between st.valid_from and st.valid_to);



create or replace view V_customer_cohors as(

select customerkey,
       min(fiscal_quarter) cohor_y_q,
       cast(substring(min(d.fiscal_quarter) from 3 for 4) as int) * 4
      + cast(right(min(d.fiscal_quarter), 1) as int)
      as cohort_quarter_index


from v_sales_datamart v
JOIN dim_date_data d on v.orderdatekey = d.date
where customerkey != -1
group by customerkey

order by 2);