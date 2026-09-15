select id as customer_id,
name as customer_name,
email,
signup_date
from {{ source('raw', 'raw_customers') }}
