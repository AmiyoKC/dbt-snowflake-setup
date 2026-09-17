select id as customer_id,
name as customer_name,
email,
signup_date,
current_timestamp() as as_at 
from {{ ref('raw_customers') }}
