{% macro pprint_partition_field(partition_by_dict, alias = '') %}
    {%- set partition_col_exp -%}
        {%- if alias -%} {{alias}}.{{partition_by_dict.field}}
        {%- else -%} {{partition_by_dict.field}}
        {%- endif -%}
    {%- endset -%}
    {%- if partition_by_dict.data_type in ('timestamp','datetime') -%}
        date({{partition_col_exp}})
    {%- else -%}
        {{partition_col_exp}}
    {%- endif -%}
{% endmacro %}

{% macro partition_by(partition_by_dict) %}
    {%- if partition_by_dict is not none -%}
        {%- set partition_by_type = partition_by_dict.data_type|trim|lower -%}
        {%- if partition_by_type in ('date','timestamp','datetime') -%}
            partition by {{pprint_partition_field(partition_by_dict)}}
        {%- elif partition_by_type in ('int64') -%}
            {%- set pbr = partition_by_dict.range -%}
            partition by range_bucket(
                {{partition_by_dict.field}},
                generate_array({{pbr.start}}, {{pbr.end}}, {{pbr.interval}})
            )
        {%- endif -%}
    {%- endif -%}
{%- endmacro -%}

{% macro cluster_by(raw_cluster_by) %}
  {%- if raw_cluster_by is not none -%}
  cluster by {% if raw_cluster_by is string -%}
    {% set raw_cluster_by = [raw_cluster_by] %}
  {%- endif -%}
  {%- for cluster in raw_cluster_by -%}
    {{ cluster }}
    {%- if not loop.last -%}, {% endif -%}
  {%- endfor -%}

  {% endif %}

{%- endmacro -%}

{% macro bigquery_table_options(persist_docs, temporary, kms_key_name, labels) %}
  {% set opts = {} -%}

  {%- set description = get_relation_comment(persist_docs, model) -%}
  {%- if description is not none -%}
    {%- do opts.update({'description': "'" ~ description ~ "'"}) -%}
  {%- endif -%}
  {%- if kms_key_name -%}
    {%- do opts.update({'kms_key_name': "'" ~ kms_key_name ~ "'"}) -%}
  {%- endif -%}
  {%- if labels -%}
    {%- set label_list = [] -%}
    {%- for label, value in labels.items() -%}
      {%- do label_list.append((label, value)) -%}
    {%- endfor -%}
    {%- do opts.update({'labels': label_list}) -%}
  {%- endif -%}

  {% set options -%}
    OPTIONS({% for opt_key, opt_val in opts.items() %}
      {{ opt_key }}={{ opt_val }}{{ "," if not loop.last }}
    {% endfor %})
  {%- endset %}
  {%- do return(options) -%}
{%- endmacro -%}

{% macro bigquery__create_table_as(temporary, relation, sql) -%}
  {%- set raw_partition_by = config.get('partition_by', none) -%}
  {%- set raw_cluster_by = config.get('cluster_by', none) -%}
  {%- set raw_persist_docs = config.get('persist_docs', {}) -%}
  {%- set raw_kms_key_name = config.get('kms_key_name', none) -%}
  {%- set raw_labels = config.get('labels', []) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {%- set partition_by_dict = adapter.parse_partition_by(raw_partition_by) -%}

  {{ sql_header if sql_header is not none }}

  create or replace {% if temporary -%}temp{%- endif %} table
      {{ relation.include(database=(not is_scripting), schema=(not is_scripting)) }}
  {{ partition_by(partition_by_dict) }}
  {{ cluster_by(raw_cluster_by) }}
  {%- if not temporary -%}
    {{ bigquery_table_options(
        persist_docs=raw_persist_docs,
        kms_key_name=raw_kms_key_name,
        labels=raw_labels) }}
    {%- endif %}
  as (
    {{ sql }}
  );

{%- endmacro -%}


{% macro bigquery__create_view_as(relation, sql) -%}
  {%- set raw_persist_docs = config.get('persist_docs', {}) -%}
  {%- set raw_labels = config.get('labels', []) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {{ sql_header if sql_header is not none }}

  create or replace view {{ relation }}
  {{ bigquery_table_options(persist_docs=raw_persist_docs, temporary=false, labels=raw_labels) }}
  as (
    {{ sql }}
  );
{% endmacro %}

{% macro bigquery__create_schema(database_name, schema_name) -%}
  {{ adapter.create_schema(database_name, schema_name) }}
{% endmacro %}

{% macro bigquery__drop_schema(database_name, schema_name) -%}
  {{ adapter.drop_schema(database_name, schema_name) }}
{% endmacro %}

{% macro bigquery__drop_relation(relation) -%}
  {% call statement('drop_relation') -%}
    drop {{ relation.type }} if exists {{ relation }}
  {%- endcall %}
{% endmacro %}

{% macro bigquery__get_columns_in_relation(relation) -%}
  {{ return(adapter.get_columns_in_relation(relation)) }}
{% endmacro %}


{% macro bigquery__list_relations_without_caching(information_schema, schema) -%}
  {{ return(adapter.list_relations_without_caching(information_schema, schema)) }}
{%- endmacro %}


{% macro bigquery__current_timestamp() -%}
  CURRENT_TIMESTAMP()
{%- endmacro %}


{% macro bigquery__snapshot_string_as_time(timestamp) -%}
    {%- set result = 'TIMESTAMP("' ~ timestamp ~ '")' -%}
    {{ return(result) }}
{%- endmacro %}


{% macro bigquery__list_schemas(database) -%}
  {{ return(adapter.list_schemas()) }}
{% endmacro %}


{% macro bigquery__check_schema_exists(information_schema, schema) %}
  {{ return(adapter.check_schema_exists(information_schema.database, schema)) }}
{% endmacro %}


{% macro bigquery__make_temp_relation(base_relation, suffix) %}
    {% set tmp_identifier = base_relation.identifier ~ suffix %}
    {% set tmp_relation = api.Relation.create(identifier=tmp_identifier) -%}
    {% do return(tmp_relation) %}
{% endmacro %}
