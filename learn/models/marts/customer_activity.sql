{{
    config(
        materialized='incremental',
        unique_key='customer_id'
    )
}}

select
    customer_id,
    customer_name,
    email,
    signup_date,
    current_timestamp() as as_at
from {{ ref('stg_customers') }}

{% if is_incremental() %}
where signup_date > (select max(signup_date) from {{ this }})
{% endif %}