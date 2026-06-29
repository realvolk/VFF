#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Dependency resolver (topological sort)

# @brief Resolve build order from a list of packages
resolve_deps() {
    local -a pkgs=("$@")
    local -A in_degree=()
    local -A edges=()
    local -A providers=()
    local pkg dep

    # Build provider map from all recipes
    for pkg in "${pkgs[@]}"; do
        load_recipe "${pkg}"
        for provided in "${provides[@]}"; do
            providers["${provided}"]="${pkg}"
        done
    done

    for pkg in "${pkgs[@]}"; do
        in_degree["${pkg}"]=0
        edges["${pkg}"]=''
    done

    for pkg in "${pkgs[@]}"; do
        load_recipe "${pkg}"
        for dep in "${depends[@]}" "${makedepends[@]}"; do
            local resolved="${dep}"
            # Resolve virtuals to concrete packages
            local provider="${providers["${dep}"]:-}"
            if [[ -n "${provider}" ]]; then
                resolved="${provider}"
            fi
            if [[ " ${pkgs[*]} " =~ " ${resolved} " ]]; then
                edges["${resolved}"]+="${pkg} "
                in_degree["${pkg}"]=$((in_degree["${pkg}"] + 1))
            fi
        done
    done

    local -a queue=() ordered=()
    for pkg in "${pkgs[@]}"; do
        [[ "${in_degree["${pkg}"]}" -eq 0 ]] && queue+=("${pkg}")
    done

    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        ordered+=("${current}")

        for next in ${edges["${current}"]}; do
            in_degree["${next}"]=$((in_degree["${next}"] - 1))
            [[ "${in_degree["${next}"]}" -eq 0 ]] && queue+=("${next}")
        done
    done

    if [[ ${#ordered[@]} -ne ${#pkgs[@]} ]]; then
        die "Circular dependency detected among: ${pkgs[*]}"
    fi

    printf '%s\n' "${ordered[@]}"
}