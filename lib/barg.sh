#!/usr/bin/env bash

bgen:import butl/vars
bgen:import butl/arrays
bgen:import butl/ansi
bgen:import butl/log

bgen:import barg/_parse.sh
bgen:import barg/_usage.sh

# shellcheck disable=SC2034
: "${__barg_style_title:="${BUTL_ANSI_RESET}${BUTL_ANSI_YELLOW}"}"
# shellcheck disable=SC2034
: "${__barg_style_arg:="${BUTL_ANSI_RESET}${BUTL_ANSI_GREEN}"}"
# shellcheck disable=SC2034
: "${__barg_style_info:="${BUTL_ANSI_RESET}${BUTL_ANSI_DIM}"}"
# shellcheck disable=SC2034
: "${__barg_style_info_var:="${__barg_style_info}${BUTL_ANSI_UNDERLINE}"}"
# shellcheck disable=SC2034
: "${__barg_style_info_equals:="${__barg_style_info}"}"
# shellcheck disable=SC2034
: "${__barg_style_info_value:="${BUTL_ANSI_RESET}${BUTL_ANSI_CYAN}"}"
# shellcheck disable=SC2034
: "${__barg_style_reset:="${BUTL_ANSI_RESET}"}"

# shellcheck disable=SC2034
: "${__barg_usage_arg_desc_length_threshold:=0}"
# shellcheck disable=SC2034
: "${__barg_usage_flag_desc_length_threshold:=0}"
# shellcheck disable=SC2034
: "${__barg_usage_option_desc_length_threshold:=0}"

# Declare a subcommand
# @param subcommand         name of the subcommand
# @param subcommand_func    command to call for this subcommand
# shellcheck disable=2059
barg.subcommand() {
    local subcommand=$1
    local subcommand_func=$2
    local subcommand_desc=$3

    if ! butl.is_array __barg_subcommands; then
        __barg_subcommands=()
    fi

    __barg_subcommands+=("$subcommand")

    printf -v "__barg_subcommand_${subcommand//-/_}_func" "$subcommand_func"
    printf -v "__barg_subcommand_${subcommand//-/_}_desc" "$subcommand_desc"
}

# When called, barg doesn't append its help command/flag
barg.disable_help() {
    # shellcheck disable=SC2034
    __barg_disable_help=1
}

# Declare an argument
# shellcheck disable=2059
barg.arg() {
    local second_pass_args=()
    local arg_values=()
    local arg_defaults=()
    local arg_implies=()
    local arg_multi=

    local arg=
    local arg_desc=
    local arg_short=
    local arg_long=
    local arg_env=
    local arg_hidden=
    local arg_allow_dash=
    local arg_required=

    while (($#)); do
        case "$1" in
        --value)
            arg_values+=("$2")
            shift 2
            ;;
        --value=*)
            arg_values+=("${1#--value=}")
            shift
            ;;
        *)
            second_pass_args+=("$1")
            shift
            ;;
        esac
    done
    if ((${#second_pass_args[@]})); then
        set -- "${second_pass_args[@]}"
    fi

    while (($#)); do
        case "$1" in
        --short)
            arg_short=$2
            shift 2
            ;;
        --short=*)
            arg_short=${1#--short=}
            shift
            ;;
        --long)
            arg_long=$2
            shift 2
            ;;
        --long=*)
            arg_long=${1#--long=}
            shift
            ;;
        --desc)
            arg_desc=$2
            shift 2
            ;;
        --desc=*)
            arg_desc=${1#--desc=}
            shift
            ;;
        --env)
            arg_env=$2
            shift 2
            ;;
        --env=*)
            arg_env=${1#--env=}
            shift
            ;;
        --default)
            arg_defaults+=("$2")
            shift 2
            ;;
        --default=*)
            arg_defaults+=("${1#--default=}")
            shift
            ;;
        --defaults)
            local value_count=${#arg_values[@]}
            arg_defaults=("${@:1:$value_count}")
            shift "$value_count"
            ;;
        --multi)
            arg_multi=1
            shift
            ;;
        --implies)
            arg_implies+=("$2")
            shift 2
            ;;
        --implies=*)
            arg_implies+=("${1#--implies=}")
            shift
            ;;
        --hidden)
            arg_hidden=1
            shift
            ;;
        --allow-dash)
            local arg_allow_dash=1
            shift
            ;;
        --required)
            local arg_required=1
            shift
            ;;
        *)
            if [[ "$arg" ]]; then
                butl.fail "barg.arg: expected 1 argument ($arg), but another one was given: $1"
                return
            fi

            local arg="$1"
            shift
            ;;
        esac
    done

    if ((${#arg_values[@]})) && [[ "$arg_short" || "$arg_long" ]]; then
        # handle options
        butl.is_array __barg_options || __barg_options=()

        butl.set_var "__barg_option_${arg}_desc" "${arg_desc:-}"
        butl.set_var "__barg_option_${arg}_short" "${arg_short:-}"
        butl.set_var "__barg_option_${arg}_long" "${arg_long:-}"
        butl.set_var "__barg_option_${arg}_env" "${arg_env:-}"
        butl.set_var "__barg_option_${arg}_multi" "${arg_multi:-}"
        butl.set_var "__barg_option_${arg}_hidden" "${arg_hidden:-}"
        butl.set_var "__barg_option_${arg}_required" "${arg_required:-}"
        butl.copy_array arg_values "__barg_option_${arg}_values"
        butl.copy_array arg_defaults "__barg_option_${arg}_defaults"
        butl.copy_array arg_implies "__barg_option_${arg}_implies"

        if [[ "${arg_short:-}" ]]; then
            butl.set_var "__barg_options_have_short" 1
        fi

        if [[ "${arg_long:-}" ]]; then
            butl.set_var "__barg_options_have_long" 1
        fi

        __barg_options+=("$arg")
    elif [[ "$arg_short" || "$arg_long" ]]; then
        # handle flags
        butl.is_array __barg_flags || __barg_flags=()

        butl.set_var "__barg_flag_${arg}_desc" "${arg_desc:-}"
        butl.set_var "__barg_flag_${arg}_short" "${arg_short:-}"
        butl.set_var "__barg_flag_${arg}_long" "${arg_long:-}"
        butl.set_var "__barg_flag_${arg}_env" "${arg_env:-}"
        butl.set_var "__barg_flag_${arg}_hidden" "${arg_hidden:-}"
        butl.copy_array arg_implies "__barg_flag_${arg}_implies"

        if [[ "${arg_short:-}" ]]; then
            butl.set_var "__barg_flags_have_short" 1
        fi

        if [[ "${arg_long:-}" ]]; then
            butl.set_var "__barg_flags_have_long" 1
        fi

        __barg_flags+=("$arg")
    elif ((${#arg_values[@]})); then
        if ((arg_multi)); then
            if [[ "${__barg_catchall_arg:-}" ]]; then
                butl.fail "cannot define more than one catchall argument"
                return
            fi

            __barg_catchall_arg=$arg
        fi

        # handle arguments
        butl.is_array __barg_args || __barg_args=()

        butl.set_var "__barg_arg_${arg}_desc" "${arg_desc:-}"
        butl.set_var "__barg_arg_${arg}_env" "${arg_env:-}"
        butl.set_var "__barg_arg_${arg}_hidden" "${arg_hidden:-}"
        butl.set_var "__barg_arg_${arg}_allow_dash" "${arg_allow_dash:-}"
        butl.set_var "__barg_arg_${arg}_required" "${arg_required:-}"
        butl.copy_array arg_values "__barg_arg_${arg}_values"
        butl.copy_array arg_defaults "__barg_arg_${arg}_defaults"

        __barg_args+=("$arg")
    else
        butl.fail "Argument should either have a --long/-short form, a value name, or both."
    fi
}

# Resets internal variables to their clean state
# shellcheck disable=SC2154
barg.reset() {
    unset __barg_disable_help

    unset __barg_subcommands
    unset "${!__barg_subcommand_@}"

    unset __barg_flags
    unset "${!__barg_flag_@}"
    unset "${!__barg_flags_@}"

    unset __barg_options
    unset "${!__barg_option_@}"
    unset "${!__barg_options_@}"

    unset __barg_args
    unset "${!__barg_arg_@}"
    unset "${!__barg_args_@}"

    unset __barg_catchall_arg
}

# Checks if there are any subcommands
__barg_has_subcommands() {
    if ! butl.is_array __barg_subcommands || ((${#__barg_subcommands[@]} == 0)); then
        return 1
    fi

    local count_hidden=${1:-0}
    if ((count_hidden)); then
        return 0
    fi

    local count=0
    for subcommand in "${__barg_subcommands[@]}"; do
        local var_subcommand_hidden="__barg_subcommand_${subcommand}_hidden"
        local subcommand_hidden=${!var_subcommand_hidden:-}

        if ! ((subcommand_hidden)); then
            count=$((count += 1))
        fi
    done

    ((count > 0))
}

# Checks if there are any options
__barg_has_options() {
    if ! butl.is_array __barg_options || ((${#__barg_options[@]} == 0)); then
        return 1
    fi

    local count_hidden=${1:-0}
    if ((count_hidden)); then
        return 0
    fi

    local count=0
    for option in "${__barg_options[@]}"; do
        local var_option_hidden="__barg_option_${option}_hidden"
        local option_hidden=${!var_option_hidden:-}

        if ! ((option_hidden)); then
            count=$((count += 1))
        fi
    done

    ((count > 0))
}

# Checks if there are any flags
__barg_has_flags() {
    if ! butl.is_array __barg_flags || ((${#__barg_flags[@]} == 0)); then
        return 1
    fi

    local count_hidden=${1:-0}
    if ((count_hidden)); then
        return 0
    fi

    local count=0
    for flag in "${__barg_flags[@]}"; do
        local var_flag_hidden="__barg_flag_${flag}_hidden"
        local flag_hidden=${!var_flag_hidden:-}

        if ! ((flag_hidden)); then
            count=$((count += 1))
        fi
    done

    ((count > 0))
}

# Checks if there are any args
__barg_has_args() {
    if ! butl.is_array __barg_args || ((${#__barg_args[@]} == 0)); then
        return 1
    fi

    local count_hidden=${1:-0}
    if ((count_hidden)); then
        return 0
    fi

    local count=0
    for arg in "${__barg_args[@]}"; do
        local var_arg_hidden="__barg_arg_${arg}_hidden"
        local arg_hidden=${!var_arg_hidden:-}

        if ! ((arg_hidden)); then
            count=$((count += 1))
        fi
    done

    ((count > 0))
}
