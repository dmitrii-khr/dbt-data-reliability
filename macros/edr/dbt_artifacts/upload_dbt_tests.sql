{%- macro upload_dbt_tests() -%}
    {% set edr_cli_run = elementary.get_config_var('edr_cli_run') %}
    {% if execute and not edr_cli_run %}
        {% set tests = graph.nodes.values() | selectattr('resource_type', '==', 'test') %}
        {% do elementary.upload_artifacts_to_table(this, tests, elementary.get_flatten_test_callback()) %}
    {%- endif -%}
    {{- return('') -}}
{%- endmacro -%}




{% macro get_dbt_tests_empty_table_query() %}
    {% set dbt_tests_empty_table_query = elementary.empty_table([('unique_id', 'string'),
                                                                 ('database_name', 'string'),
                                                                 ('schema_name', 'string'),
                                                                 ('name', 'string'),
                                                                 ('short_name', 'string'),
                                                                 ('alias', 'string'),
                                                                 ('test_column_name', 'string'),
                                                                 ('severity', 'string'),
                                                                 ('warn_if', 'string'),
                                                                 ('error_if', 'string'),
                                                                 ('test_params', 'long_string'),
                                                                 ('test_namespace', 'string'),
                                                                 ('tags', 'long_string'),
                                                                 ('model_tags', 'long_string'),
                                                                 ('model_owners', 'long_string'),
                                                                 ('meta', 'long_string'),
                                                                 ('depends_on_macros', 'long_string'),
                                                                 ('depends_on_nodes', 'long_string'),
                                                                 ('parent_model_unique_id', 'string'),
                                                                 ('description', 'long_string'),
                                                                 ('package_name', 'string'),
                                                                 ('original_path', 'long_string'),
                                                                 ('compiled_sql', 'long_string'),
                                                                 ('path', 'string'),
                                                                 ('generated_at', 'string')]) %}
    {{ return(dbt_tests_empty_table_query) }}
{% endmacro %}

{%- macro get_flatten_test_callback() -%}
    {{- return(adapter.dispatch('flatten_test', 'elementary')) -}}
{%- endmacro -%}

{%- macro flatten_test(node_dict) -%}
    {{- return(adapter.dispatch('flatten_test', 'elementary')(node_dict)) -}}
{%- endmacro -%}

{% macro default__flatten_test(node_dict) %}
    {% set config_dict = elementary.safe_get_with_default(node_dict, 'config', {}) %}
    {% set depends_on_dict = elementary.safe_get_with_default(node_dict, 'depends_on', {}) %}

    {% set config_meta_dict = elementary.safe_get_with_default(config_dict, 'meta', {}) %}
    {% set meta_dict = elementary.safe_get_with_default(node_dict, 'meta', {}) %}
    {% do meta_dict.update(config_meta_dict) %}

    {% set config_tags = elementary.safe_get_with_default(config_dict, 'tags', []) %}
    {% set global_tags = elementary.safe_get_with_default(node_dict, 'tags', []) %}
    {% set meta_tags = elementary.safe_get_with_default(meta_dict, 'tags', []) %}
    {% set tags = elementary.union_lists(config_tags, global_tags) %}
    {% set tags = elementary.union_lists(tags, meta_tags) %}

    {% set parent_model_unique_ids = elementary.get_parent_model_unique_ids_from_test_node(node_dict) %}
    {% set parent_model_nodes = elementary.get_nodes_by_unique_ids(parent_model_unique_ids) %}
    {% set parent_models_owners = [] %}
    {% set parent_models_tags = [] %}
    {% for parent_model_node in parent_model_nodes %}
        {% set flatten_parent_model_node = elementary.flatten_model(parent_model_node) %}
        {% set parent_model_owner = flatten_parent_model_node.get('owner') %}
        {% set parent_model_tags = flatten_parent_model_node.get('tags') %}
        {% if parent_model_owner %}
            {% do parent_models_owners.append(parent_model_owner) %}
        {% endif %}
        {% if parent_model_tags and parent_model_tags is sequence %}
            {% do parent_models_tags.extend(parent_model_tags) %}
        {% endif %}
    {% endfor %}

    {% set primary_parent_model_database, primary_parent_model_schema = elementary.get_model_database_and_schema_from_test_node(node_dict) %}
    {% set test_metadata = elementary.safe_get_with_default(node_dict, 'test_metadata', {}) %}
    {% set test_kwargs = elementary.safe_get_with_default(test_metadata, 'kwargs', {}) %}
    {% set test_model_jinja = test_kwargs.get('model') %}
    {% set primary_parent_model_id = none %}
    {% if test_model_jinja %}
        {% set primary_parent_model_candidates = [] %}
        {% for parent_model_unique_id in parent_model_unique_ids %}
            {% set split_parent_model_unique_id = parent_model_unique_id.split('.') %}
            {% if split_parent_model_unique_id and split_parent_model_unique_id | length > 0 %}
                {% set parent_model_name = split_parent_model_unique_id[-1] %}
                {% if parent_model_name and parent_model_name in test_model_jinja %}
                    {% do primary_parent_model_candidates.append(parent_model_unique_id) %}
                {% endif %}
            {% endif %}
        {% endfor %}
        {% if primary_parent_model_candidates | length == 1 %}
            {% set primary_parent_model_id = primary_parent_model_candidates[0] %}
        {% endif %}
    {% endif %}

    {% set flatten_test_metadata_dict = {
        'unique_id': node_dict.get('unique_id'),
        'short_name': test_metadata.get('name'),
        'alias': node_dict.get('alias'),
        'test_column_name': node_dict.get('column_name'),
        'severity': config_dict.get('severity'),
        'warn_if': config_dict.get('warn_if'),
        'error_if': config_dict.get('error_if'),
        'test_params': test_kwargs,
        'test_namespace': test_metadata.get('namespace'),
        'tags': tags,
        'model_tags': parent_models_tags,
        'model_owners': parent_models_owners,
        'meta': meta_dict,
        'database_name': primary_parent_model_database,
        'schema_name': primary_parent_model_schema,
        'depends_on_macros': depends_on_dict.get('macros', []),
        'depends_on_nodes': depends_on_dict.get('nodes', []),
        'parent_model_unique_id': primary_parent_model_id,
        'description': node_dict.get('description'),
        'name': node_dict.get('name'),
        'package_name': node_dict.get('package_name'),
        'original_path': node_dict.get('original_file_path'),
        'compiled_sql': node_dict.get('compiled_sql'),
        'path': node_dict.get('path'),
        'generated_at': run_started_at.strftime('%Y-%m-%d %H:%M:%S')
    }%}
    {{ return(flatten_test_metadata_dict) }}
{% endmacro %}