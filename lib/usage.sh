#!/usr/bin/env bash

bgen:import butl/columns
bgen:import butl/strip_ansi

# Prints help/usage text base on the declared commands, arguments and options
# shellcheck disable=SC2120
barg.print_usage() {
    local subcommand_name=${1:-}
    if [[ "$subcommand_name" ]]; then
        barg.print_subcommand_usage "$subcommand_name"
        return
    fi

    # check whether script is source or directly executed
    local process process_dir process_file process_base
    if [[ "${__BGEN_PIPE_SOURCE__:-}" ]]; then
        process="$__BGEN_PIPE_SOURCE__"
    elif [[ "${BASH_SOURCE+x}" ]]; then
        process="${BASH_SOURCE[0]}"
    else
        process="$0"
    fi

    # Set magic variables for current file, directory, os, etc.
    process_dir="$(cd "$(dirname "${process}")" && pwd)"
    process_file="${process_dir}/$(basename "${process}")"
    # shellcheck disable=SC2034,SC2015
    process_base="$(basename "${process_file}" .sh)"

    local process_base=${process_base:-$0}
    local arg_list=()
    local section_break=

    # shellcheck disable=SC2154
    if ((${#__barg_subcommands[@]})); then
        arg_list+=("SUBCOMMAND")
    fi

    # shellcheck disable=SC2154
    if ((${#__barg_flags[@]})); then
        arg_list+=("[FLAGS...]")
    fi

    # shellcheck disable=SC2154
    if ((${#__barg_options[@]})); then
        arg_list+=("[OPTIONS...]")
    fi

    # shellcheck disable=SC2154
    local arg_count=${#__barg_args[@]}
    if ((arg_count)); then
        for arg in "${__barg_args[@]}"; do
            # shellcheck disable=SC2154
            if [[ "$arg" == "${__barg_catchall_arg:-}" ]]; then
                continue
            fi

            local var_arg_values="__barg_arg_${arg}_values"
            local arg_values=()
            butl.copy_array "$var_arg_values" "arg_values"

            local value="${arg_values[0]:-ARGS}"
            arg_list+=("${value}")
        done

        # add the catch all at the end
        if [[ "${__barg_catchall_arg:-}" ]]; then
            local var_arg_values="__barg_arg_${__barg_catchall_arg}_values"
            local arg_values=()
            butl.copy_array "$var_arg_values" "arg_values"

            local value="${arg_values[0]:-ARGS}"
            arg_list+=("[${value}...]")
        fi
    fi

    # Print usage
    # shellcheck disable=SC2154
    printf '%bUSAGE:%b\n' "$__barg_style_title" "$__barg_style_reset"
    printf '    %s%s\n' "$process_base" "$(printf ' %s' "${arg_list[@]-}")"
    section_break=1

    # shellcheck disable=SC2154
    local flag_desc_cr_threshold=$__barg_usage_flag_desc_length_threshold
    # shellcheck disable=SC2154
    local option_desc_cr_threshold=$__barg_usage_option_desc_length_threshold
    # shellcheck disable=SC2154
    local arg_desc_cr_threschold=$__barg_usage_arg_desc_length_threshold

    __barg_print_usage_section "SUBCOMMANDS" "$(__barg_print_subcommands)"
    __barg_print_usage_section "FLAGS" "$(__barg_print_flags)"
    __barg_print_usage_section "OPTIONS" "$(__barg_print_options)"
    __barg_print_usage_section "ARGUMENTS" "$(__barg_print_args)"
}

# Print usage text for a given subcommand
barg.print_subcommand_usage() {
    local subcommand="$1"

    if butl.is_array __barg_subcommands && [[ " ${__barg_subcommands[*]-} " == *" $subcommand "* ]]; then
        command_func_var="__barg_subcommand_${subcommand//-/_}_func"
        command_func="${!command_func_var}"
        barg.reset
        "$command_func" --help
        return
    fi

    local msg="There's no help subject on: ${BUTL_ANSI_UNDERLINE}${subcommand}${BUTL_ANSI_RESET_UNDERLINE}\n"
    butl.log_error "$msg"
    barg.print_usage
    return 1
}

__barg_is_lastline_too_long() {
    local size_threshold=$1
    if ((size_threshold == 0)); then
        return 1
    fi

    : "${2##*$'\n'}"
    : "$(butl.strip_ansi_style "$_")"
    ((${#_} > size_threshold))
}

__barg_print_usage_section() {
    local title=$1
    local text=$2

    if [[ "$text" ]]; then
        if ((section_break)); then
            echo
        fi

        printf '%b%s:%b\n' "$__barg_style_title" "$title" "$__barg_style_reset"
        butl.columns ' ' <<<"$text"

        section_break=1
    fi
}

__barg_print_subcommands() {
    for subcommand in "${__barg_subcommands[@]-}"; do
        [[ "$subcommand" ]] || continue
        local subcommand_desc_var="__barg_subcommand_${subcommand//-/_}_desc"
        local subcommand_desc="${!subcommand_desc_var:-}"
        # shellcheck disable=SC2154
        printf '    %b%s%b\t %s\n' "$__barg_style_arg" "$subcommand" \
            "$__barg_style_reset" "$subcommand_desc"
    done
}

__barg_print_flags() {
    for flag in "${__barg_flags[@]-}"; do
        if [[ ! "$flag" ]]; then
            continue
        fi

        local flag_desc_var="__barg_flag_${flag}_desc"
        local flag_desc="${!flag_desc_var:-}"

        local flag_short_var="__barg_flag_${flag}_short"
        local flag_short="${!flag_short_var:-}"

        local flag_long_var="__barg_flag_${flag}_long"
        local flag_long="${!flag_long_var:-}"

        local flag_env_var="__barg_flag_${flag}_env"
        local flag_env="${!flag_env_var:-}"

        if [[ ! "${flag_short:-}${flag_long:-}" ]]; then
            continue
        fi

        if [[ "${flag_short:-}" ]]; then
            printf '    %b-%s%b' "$__barg_style_arg" "$flag_short" "$__barg_style_reset"
        else
            printf '    %b  %b' "$__barg_style_arg" "$__barg_style_reset"
        fi

        if [[ "${flag_short:-}" && "${flag_long:-}" ]]; then
            printf ',\t'
        else
            printf '\t'
        fi

        if [[ "${flag_long:-}" ]]; then
            printf '%b--%s%b' "$__barg_style_arg" "$flag_long" "$__barg_style_reset"
        else
            printf '%b%b' "$__barg_style_arg" "$__barg_style_reset"
        fi

        local desc=" $flag_desc"

        if [[ "${flag_env}" ]]; then
            if __barg_is_lastline_too_long "$flag_desc_cr_threshold" "$desc"; then
                desc+=$'\n'
            fi

            # shellcheck disable=SC2154
            desc+=$(printf ' %b[env: %b%s%b=%b%s%b]%b' "$__barg_style_info" \
                "$__barg_style_info_var" "$flag_env" "$__barg_style_info_equals" \
                "$__barg_style_info_value" "${!flag_env:-}" \
                "$__barg_style_info" "$__barg_style_reset")
        fi

        : "${desc//$'\n'/$'\n\t\t '}"
        printf '\t %s\n' "$_"
    done
}

__barg_print_options() {
    for option in "${__barg_options[@]-}"; do
        if [[ ! "$option" ]]; then
            continue
        fi

        local option_desc_var="__barg_option_${option}_desc"
        local option_desc=${!option_desc_var:-}

        local option_short_var="__barg_option_${option}_short"
        local option_short=${!option_short_var:-}

        local option_long_var="__barg_option_${option}_long"
        local option_long=${!option_long_var:-}

        local option_env_var="__barg_option_${option}_env"
        local option_env=${!option_env_var:-}

        local option_values
        butl.copy_array "__barg_option_${option}_values" option_values

        local option_defaults
        butl.copy_array "__barg_option_${option}_defaults" option_defaults

        if [[ ! "${option_short:-}${option_long:-}" ]]; then
            continue
        fi

        printf '    '

        if [[ "${__barg_options_have_short:-}" ]]; then
            if [[ "${option_short:-}" ]]; then
                printf '%b-%s%b' "$__barg_style_arg" "$option_short" "$__barg_style_reset"
            else
                printf '%b  %b' "$__barg_style_arg" "$__barg_style_reset"
            fi

            if [[ "${option_short:-}" && "${option_long:-}" ]]; then
                printf ',\t'
            else
                printf '\t'
            fi
        fi

        if [[ "${__barg_options_have_long:-}" ]]; then
            if [[ "${option_long:-}" ]]; then
                printf '%b--%s%b' "$__barg_style_arg" "$option_long" "$__barg_style_reset"
            else
                printf '%b%b' "$__barg_style_arg" "$__barg_style_reset"
            fi
        fi

        if [[ "${option_values[0]-}" ]]; then
            local values_str
            values_str=$(printf ' <%s>' "${option_values[@]}")
            if [[ ! "${option_long:-}" ]]; then
                values_str=${values_str:1}
            fi
            printf '%b%s%b' "$__barg_style_arg" "$values_str" "$__barg_style_reset"
        fi

        local desc="$option_desc"

        if [[ "${option_defaults[0]-}" ]]; then
            if __barg_is_lastline_too_long "$option_desc_cr_threshold" "$desc"; then
                desc+=$'\n'
            fi

            local join_separator="$__barg_style_reset, $__barg_style_info_value"
            desc+=$(printf ' %b[default: %b%b%b]%b' "$__barg_style_info" "$__barg_style_info_value" \
                "$(butl.join_by "$join_separator" "${option_defaults[@]}")" \
                "$__barg_style_info" "$__barg_style_reset")
        fi

        if [[ "${option_env}" ]]; then
            if __barg_is_lastline_too_long "$option_desc_cr_threshold" "$desc"; then
                desc+=$'\n'
            fi

            desc+=$(printf ' %b[env: %b%s%b=%b%s%b]%b' "$__barg_style_info" \
                "$__barg_style_info_var" "$option_env" "$__barg_style_info_equals" \
                "$__barg_style_info_value" "${!option_env:-}" \
                "$__barg_style_info" "$__barg_style_reset")
        fi

        : "${desc//$'\n'/$'\n\t\t'}"
        printf '\t %s\n' "$_"
    done
}

__barg_print_args() {
    for arg in "${__barg_args[@]-}"; do
        if [[ ! "$arg" ]]; then
            continue
        fi

        local arg_desc_var="__barg_arg_${arg}_desc"
        local arg_desc=${!arg_desc_var:-}

        local arg_env_var="__barg_arg_${arg}_env"
        local arg_env=${!arg_env_var:-}

        local arg_values
        butl.copy_array "__barg_arg_${arg}_values" arg_values

        local arg_defaults
        butl.copy_array "__barg_arg_${arg}_defaults" arg_defaults

        if [[ "${arg_values[0]-}" ]]; then
            printf '   %b%s%b' "$__barg_style_arg" \
                "$(printf ' <%s>' "${arg_values[@]}")" "$__barg_style_reset"
        fi

        local desc=" $arg_desc"

        if [[ "${arg_defaults[0]-}" ]]; then
            if __barg_is_lastline_too_long "$arg_desc_cr_threschold" "$desc"; then
                desc+=$'\n'
            fi

            local join_separator="$__barg_style_reset, $__barg_style_info_value"
            desc+=$(printf ' %b[default: %b%b%b]%b' \
                "$__barg_style_info" "$__barg_style_info_value" \
                "$(butl.join_by "$join_separator" "${arg_defaults[@]}")" \
                "$__barg_style_info" "$__barg_style_reset")
        fi

        if [[ "${arg_env}" ]]; then
            if __barg_is_lastline_too_long "$arg_desc_cr_threschold" "$desc"; then
                desc+=$'\n'
            fi

            desc+=$(printf ' %b[env: %b%s%b=%b%s%b]%b' \
                "$__barg_style_info" "$__barg_style_info_var" \
                "$arg_env" "$__barg_style_info_equals" "$__barg_style_info_value" \
                "${!arg_env:-}" "$__barg_style_info" "$__barg_style_reset")
        fi

        : "${desc//$'\n'/$'\n\t'}"
        printf '\t %s\n' "$_"
    done
}
