#!/usr/bin/env  bash

# Parses arguments looking for a subcommand
# @param        args...         the arguments to parse
# @required_var subcommand      will be set to the called subcommand
# @required_var subcommand_args will be set to an array of the args that came after the subcommand
# @optional_var global_args     will be set to an array of the args that came before the subcommand
barg.parse() {
    # add the help subcommand if there are other subcommands
    if ! ((${__barg_disable_help:-})); then
        if butl.is_array __barg_subcommands && (("${#__barg_subcommands[@]}")); then
            barg.subcommand help barg.print_usage \
                "Prints this message or the help of the given subcommand"
        fi

        if ! butl.is_declared barg_help; then
            local barg_help=
        fi

        if __barg_has_flags; then
            barg.arg barg_help --short=h --long=help --desc "Prints help information"
        else
            barg.arg barg_help --short=h --long=help --desc "Prints help information" --hidden
        fi
    fi

    butl.is_array __barg_subcommands || __barg_subcommands=()
    butl.is_array __barg_options || __barg_options=()
    butl.is_array __barg_flags || __barg_flags=()
    # shellcheck disable=SC2034 # TODO: Implement arg parsing
    butl.is_array __barg_args || __barg_args=()

    local catchall_array=()
    local process_args_only=0
    local next_arg_index=0

    # Variable to track whether or not the checks were failed
    local failed=0

    # Reset set flags for options
    for option in "${__barg_options[@]-}"; do
        if [[ ! "$option" ]]; then
            continue
        fi

        butl.set_var "__barg_option_${option}_set" 0
    done

    # Reset filled flags for normal arguments
    for arg in "${__barg_args[@]-}"; do
        if [[ ! "$arg" ]]; then
            continue
        fi

        butl.set_var "__barg_arg_${arg}_filled" 0
    done

    # Parse the rest of the arguments
    while (($#)); do
        local arg="$1"
        shift

        local processed_arg=
        if ! ((process_args_only)); then
            if [[ "$arg" == "--" ]]; then
                process_args_only=1
                continue
            fi

            # Check if there's a subcommand
            if [[ "$arg" && " ${__barg_subcommands[*]-} " == *" $arg "* ]]; then
                local var_subcommand_func="__barg_subcommand_${arg//[-]/_}_func"

                if ! butl.is_declared subcommand; then
                    local subcommand=
                fi

                if ! butl.is_declared subcommand_args; then
                    local subcommand_args=()
                fi

                if (($#)); then
                    subcommand="${!var_subcommand_func}"
                    subcommand_args=("$@")
                else
                    subcommand="${!var_subcommand_func}"
                    subcommand_args=()
                fi

                # run help command in this context to access other barg variables
                if [[ "$arg" == "help" ]]; then
                    "$subcommand" "${subcommand_args[@]}"

                    if butl.is_declared should_exit; then
                        butl.set_var should_exit 1
                        return 0
                    else
                        exit 0
                    fi
                fi

                __barg_postprocess_options
                __barg_postprocess_flags
                __barg_postprocess_args
                barg.reset

                return 0
            fi

            # Check options
            for option in "${__barg_options[@]-}"; do
                local shift_count=0

                if [[ "$arg" == --* ]]; then
                    local var_option_long="__barg_option_${option}_long"
                    local option_long="${!var_option_long:-}"
                    if [[ ! "$option_long" ]]; then
                        continue
                    fi

                    if [[ "$arg" == --"$option_long" ]]; then
                        local option_arg="--$option_long"
                        __barg_parse_option "$@"
                        shift "$shift_count"
                    elif [[ "$arg" == --"$option_long"=* ]]; then
                        local param=${arg#--"$option_long"=}
                        local option_arg="--$option_long=$param"
                        __barg_parse_option "$param"
                    fi
                elif [[ "$arg" == -* ]]; then
                    local var_option_short="__barg_option_${option}_short"
                    local option_short="${!var_option_short:-}"
                    if [[ ! "$option_short" ]]; then
                        continue
                    fi

                    if [[ "$arg" == -*"$option_short" ]]; then
                        local option_arg="-$option_short"
                        __barg_parse_option "$@"
                        shift "$shift_count"
                    elif [[ "$arg" == -*"$option_short"=* ]]; then
                        local param=${arg#-*"$option_short"=}
                        local option_arg="-$option_short=$param"
                        __barg_parse_option "$param"
                    fi
                fi

                if ((processed_arg)); then
                    break
                fi
            done

            if ((processed_arg)); then
                continue
            fi

            # Check flags
            for flag in "${__barg_flags[@]-}"; do
                if [[ "$arg" == --* ]]; then
                    local var_flag_long="__barg_flag_${flag}_long"
                    local flag_long="${!var_flag_long:-}"
                    if [[ ! "$flag_long" ]]; then
                        continue
                    fi

                    if [[ "$arg" == "--$flag_long" ]]; then
                        local flag_arg="--$flag_long"
                        __barg_parse_flag
                    fi
                elif [[ "$arg" == -* ]]; then
                    local var_flag_short="__barg_flag_${flag}_short"
                    local flag_short="${!var_flag_short:-}"
                    if [[ ! "$flag_short" ]]; then
                        continue
                    fi

                    if [[ "$arg" == -*"$flag_short"* ]]; then
                        local flag_arg="-$flag_short"
                        __barg_parse_flag
                    fi
                fi

                if ((processed_arg)); then
                    break
                fi
            done

            if ((processed_arg)); then
                continue
            fi
        fi

        if ((next_arg_index < ${#__barg_args[@]})); then
            local arg_name="${__barg_args[$next_arg_index]}"
            if [[ "${__barg_catchall_arg:-}" == "$arg_name" ]]; then
                next_arg_index=$((next_arg_index + 1))
            fi
        fi

        if ((next_arg_index < ${#__barg_args[@]})); then
            local arg_name=${__barg_args[$next_arg_index]}

            local process_arg=1
            if [[ "$arg" == -?* ]]; then
                local var_arg_allow_dash="__barg_arg_${arg_name}_allow_dash"
                local arg_allow_dash=${!var_arg_allow_dash:-}

                if ! ((arg_allow_dash)); then
                    process_arg=0
                fi
            fi

            if ((process_arg)); then
                local arg_values=()
                butl.copy_array "__barg_arg_${arg_name}_values" arg_values

                if ((${#arg_values[@]} <= 1)); then
                    if butl.is_declared "$arg_name"; then
                        butl.set_var "$arg_name" "$arg"
                    fi

                    butl.set_var "__barg_arg_${arg_name}_filled" 1
                    next_arg_index=$((next_arg_index + 1))
                else
                    if butl.is_declared "$arg_name"; then
                        local current_values=()
                        if butl.is_array "$arg_name"; then
                            butl.copy_array "$arg_name" current_values
                        fi

                        current_values+=("$arg")
                        butl.copy_array current_values "$arg_name"
                    fi

                    local filled_var="__barg_arg_${arg_name}_filled"
                    local filled=${!filled_var:-0}
                    filled=$((filled + 1))
                    butl.set_var "$filled_var" "$filled"

                    if ((filled >= ${#arg_values[@]})); then
                        next_arg_index=$((next_arg_index + 1))
                    fi
                fi

                processed_arg=1
            fi
        fi

        if ((processed_arg)); then
            continue
        fi

        if [[ "${__barg_catchall_arg:-}" ]]; then
            local var_arg_allow_dash="__barg_arg_${__barg_catchall_arg}_allow_dash"
            local arg_allow_dash=${!var_arg_allow_dash}

            if [[ "$arg" == -?* ]]; then
                if ((process_args_only || arg_allow_dash)); then
                    catchall_array+=("$arg")
                    continue
                fi
            else
                catchall_array+=("$arg")
                continue
            fi
        fi

        butl.log_error "Unknown argument: ${BUTL_ANSI_UNDERLINE}${arg}${BUTL_ANSI_RESET_UNDERLINE}."
        failed=1
    done

    if ! ((${__barg_disable_help:-0})) && ((${barg_help:-0})); then
        if ((failed)); then
            # Leave an empty line after the error messages
            echo
        fi

        barg.print_usage
        barg.reset
        if butl.is_declared should_exit; then
            butl.set_var should_exit 1
            if ((failed)); then
                if butl.is_declared should_exit_err; then
                    butl.set_var should_exit_err 1
                fi
                return 1
            else
                return 0
            fi
        elif ((failed)); then
            exit 1
        else
            exit 0
        fi
    fi

    # Set the catchall flag if any
    if [[ "${__barg_catchall_arg:-}" ]]; then
        butl.copy_array "catchall_array" "$__barg_catchall_arg"
    fi

    __barg_postprocess_options
    __barg_postprocess_flags
    __barg_postprocess_args

    if ((${#catchall_array[@]} == 0)) && [[ "${__barg_catchall_arg:-}" ]]; then
        local var_catchall_required="__barg_arg_${__barg_catchall_arg}_required"
        local catchall_required=${!var_catchall_required}

        if ((catchall_required)); then
            butl.log_error "Argument ${BUTL_ANSI_UNDERLINE}$arg${BUTL_ANSI_RESET_UNDERLINE} is required."
            failed=1
        fi
    fi

    if ((failed)) || __barg_has_subcommands 1; then
        if ((failed)); then
            # Leave an empty line after the error messages
            echo
        fi

        barg.print_usage
        barg.reset
        if butl.is_declared should_exit; then
            butl.set_var should_exit 1
            if butl.is_declared should_exit_err; then
                butl.set_var should_exit_err 1
            fi
            return 1
        else
            exit 1
        fi
    fi

    barg.reset
}

__barg_parse_option() {
    processed_arg=1
    if ! butl.is_declared "$option"; then
        return
    fi

    local option_values=()
    butl.copy_array "__barg_option_${option}_values" option_values

    local value_count=${#option_values[@]}
    if ((value_count > $#)); then
        : "Option ${BUTL_ANSI_UNDERLINE}${option_arg}${BUTL_ANSI_RESET_UNDERLINE}"
        butl.log_error "$_ requires ${BUTL_ANSI_UNDERLINE}${value_count}${BUTL_ANSI_RESET_UNDERLINE} values."
        failed=1
        return
    fi

    local var_option_multi="__barg_option_${option}_multi"
    local option_multi="${!var_option_multi}"

    if ((option_multi)); then
        local values=()
        butl.copy_array "$option" "values"
        values+=("${@:1:$value_count}")
        butl.set_array "$option" "${values[@]}"
    else
        if ((value_count > 1)); then
            butl.set_array "$option" "${@:1:$value_count}"
        else
            butl.set_var "$option" "$1"
        fi
    fi

    # set implied flags to 1
    local option_implies=()
    butl.copy_array "__barg_option_${option}_implies" "option_implies"
    for implied_flag in "${option_implies[@]-}"; do
        if [[ ! "$implied_flag" ]]; then
            continue
        fi

        if [[ " ${__barg_flags[*]} " != *" $implied_flag "* ]]; then
            : "Option ${BUTL_ANSI_UNDERLINE}${option_arg}${BUTL_ANSI_RESET_UNDERLINE}"
            : "$_ implies ${BUTL_ANSI_UNDERLINE}${implied_flag}${BUTL_ANSI_RESET_UNDERLINE},"
            : "$_ but ${BUTL_ANSI_UNDERLINE}${implied_flag}${BUTL_ANSI_RESET_UNDERLINE}"
            butl.log_error "$_ is not a flag."
            failed=1
            return
        fi

        butl.set_var "$implied_flag" 1
    done

    shift_count=$value_count

    # mark the option as set
    butl.set_var "__barg_option_${option}_set" 1
}

__barg_parse_flag() {
    processed_arg=1
    if ! butl.is_declared "$flag"; then
        return
    fi

    butl.set_var "$flag" 1

    # set implied flags to 1
    local flag_implies=()
    butl.copy_array "__barg_flag_${flag}_implies" "flag_implies"
    for implied_flag in "${flag_implies[@]-}"; do
        if [[ ! "$implied_flag" ]]; then
            continue
        fi

        if [[ " ${__barg_flags[*]} " != *" $implied_flag "* ]]; then
            butl.log_error "Flag $flag_arg implies '$implied_flag', but $implied_flag is not a flag."
            failed=1
            return
        fi

        butl.set_var "$implied_flag" 1
    done
}

__barg_postprocess_options() {
    # Fill from env or set default values for unset options
    for option in "${__barg_options[@]-}"; do
        if [[ ! "$option" ]]; then
            continue
        fi

        # Make sure required options are set
        local var_option_required="__barg_option_${option}_required"
        local option_required=${!var_option_required}

        local var_option_set="__barg_option_${option}_set"
        local option_set=${!var_option_set}

        local var_option_env="__barg_option_${option}_env"
        local option_env=${!var_option_env-}

        local option_defaults=()
        butl.copy_array "__barg_option_${option}_defaults" option_defaults

        # Skip if variable is not declared, or if an array; not empty.
        if ! butl.is_declared "$option"; then
            continue
        fi

        if ((option_set)); then
            continue
        fi

        local option_is_updated=

        # Set default value from enviornment
        if [[ "$option_env" && "${!option_env+x}" ]]; then
            # shellcheck disable=SC2059
            butl.set_var "$option" "${!option_env}"

            option_is_updated=1
        elif ((${#option_defaults[@]})); then
            if butl.is_array "$option"; then
                butl.copy_array "$option" option_defaults
                option_is_updated=1
            else
                # shellcheck disable=SC2059
                butl.set_var "$option" "${option_defaults[0]}"

                option_is_updated=1
            fi
        fi

        if ((option_required)) && ! ((option_set || option_is_updated)) \
            && ! { [[ "$option_env" && "${!option_env+x}" ]] || ((${#option_defaults[@]})); }; then
            local var_option_long="__barg_option_${option}_long"
            local option_param=${!var_option_long}
            if [[ ! "$option_param" ]]; then # long form is not set, fall back to short form
                local var_option_short="__barg_option_${option}_short"
                local option_param=${var_option_short}
            fi

            butl.log_error "Option ${BUTL_ANSI_UNDERLINE}$option_param${BUTL_ANSI_RESET_UNDERLINE} is required."
            failed=1
            continue
        fi

        # Update implied flags
        if ((option_is_updated)); then
            # mark the option as set
            butl.set_var "$var_option_set" 1

            local option_implies=()
            butl.copy_array "__barg_option_${option}_implies" "option_implies"
            for implied_flag in "${option_implies[@]-}"; do
                if [[ ! "$implied_flag" ]]; then
                    continue
                fi

                if [[ " ${__barg_flags[*]} " != *" $implied_flag "* ]]; then
                    butl.log_error "Option $option implies '$implied_flag', but $implied_flag is not a flag."
                    failed=1
                    return
                fi

                butl.set_var "$implied_flag" 1
            done
        fi
    done
}

__barg_postprocess_flags() {
    # Fill from env or set default values for unset flags
    for flag in "${__barg_flags[@]-}"; do
        if [[ ! "$flag" ]]; then
            continue
        fi

        # Skip if variable is not declared or not empty
        if ! butl.is_declared "$flag" || [[ "${!flag:-}" ]]; then
            continue
        fi

        # Set default value from environment
        local var_flag_env="__barg_flag_${flag}_env"
        local flag_env=${!var_flag_env-}
        if [[ ! "$flag_env" ]] || ! ((${!flag_env:-})); then
            butl.set_var "$flag" ''
            continue
        fi

        butl.set_var "$flag" 1

        # Update implied flags
        local flag_implies=()
        butl.copy_array "__barg_flag_${flag}_implies" "flag_implies"
        for implied_flag in "${flag_implies[@]-}"; do
            if [[ ! "$implied_flag" ]]; then
                continue
            fi

            if [[ " ${__barg_flags[*]} " != *" $implied_flag "* ]]; then
                : "Flag ${BUTL_ANSI_UNDERLINE}${flag}${BUTL_ANSI_RESET_UNDERLINE}"
                : "$_ implies ${BUTL_ANSI_UNDERLINE}${implied_flag}${BUTL_ANSI_RESET_UNDERLINE},"
                : "$_ but ${BUTL_ANSI_UNDERLINE}${implied_flag}${BUTL_ANSI_RESET_UNDERLINE}"
                butl.log_error "$_ is not a flag."
                failed=1
                continue
            fi

            butl.set_var "$implied_flag" 1
        done
    done
}

__barg_postprocess_args() {
    # Check the values of normal arguments
    for arg in "${__barg_args[@]-}"; do
        if [[ ! "$arg" ]] || [[ "$arg" == "${__barg_catchall_arg:-}" ]]; then
            continue
        fi

        local var_arg_filled="__barg_arg_${arg}_filled"
        local arg_filled=${!var_arg_filled:-}

        local arg_defaults=()
        butl.copy_array "__barg_arg_${arg}_defaults" arg_defaults

        # Make sure required args are set
        local var_arg_required="__barg_arg_${arg}_required"
        local arg_required=${!var_arg_required}
        if ((arg_required)) && ! ((arg_filled)) && ! ((${#arg_defaults[@]})); then
            butl.log_error "Argument ${BUTL_ANSI_UNDERLINE}$arg${BUTL_ANSI_RESET_UNDERLINE} is required."
            failed=1
            continue
        fi

        if ! butl.is_declared "$arg"; then
            continue
        fi

        local arg_values=()
        butl.copy_array "__barg_arg_${arg}_values" arg_values

        if ((arg_filled == ${#arg_values[@]})); then
            continue
        fi

        if ((arg_filled)); then
            : "Argument ${BUTL_ANSI_UNDERLINE}$arg${BUTL_ANSI_RESET_UNDERLINE}"
            butl.log_error "$_ requires ${#arg_values[@]} values, but only ${arg_filled} were given."
            failed=1
            continue
        fi

        # Set defaults
        if butl.is_array "$arg"; then
            butl.copy_array arg_defaults "$arg"
            butl.set_var "$var_arg_filled" "${#arg_defaults[@]}"
            arg_filled=${#arg_defaults[@]}
        elif ((${#arg_defaults[@]} > 0)); then
            butl.set_var "$arg" "${arg_defaults[0]}"
            butl.set_var "$var_arg_filled" 1
            arg_filled=1
        fi
    done
}
