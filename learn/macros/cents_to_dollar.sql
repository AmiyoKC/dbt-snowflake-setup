{% macro cents_to_dollar(column_name) %}
    ({{ column_name }}/100)::numeric(16,2)
{% endmacro %}
