with date_spine as 

(
    
    {{ dbt_utils.date_spine(
    datepart="day",
    start_date="cast('2026-01-01' as date)",
    end_date="cast('2026-04-01' as date)")
}}
),

sign_ups as (

select 
signup_date,
count(*) as num_signups
from {{ ref('stg_customers') }}
group by 1

)

select 

date_day, coalesce(num_signups,0) as num_signups


from date_spine
left outer join sign_ups on date_spine.date_day = sign_ups.signup_date