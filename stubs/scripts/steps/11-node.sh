#!/usr/bin/env bash
# @id: node
# @title: Install Node.js and npm
# @group: none
# @required: false
# @default: false
# @order: 20

step_node() {
    if [[ "$METATOR_OPERATION" == prepare-server ]]; then
        require_commands dpkg-query apt-get || return 1
        local missing_packages=() package
        for package in nodejs npm; do
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ||
                missing_packages+=("$package")
        done
        if [[ "${#missing_packages[@]}" -gt 0 ]]; then
            sudo apt-get update || return 1
            sudo apt-get install -y "${missing_packages[@]}" || return 1
        else
            ok 'Node.js and npm are unchanged and ready'
        fi
    fi

    require_commands node npm || return 1
    ok 'Node.js and npm are ready'
}
