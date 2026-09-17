#!/usr/bin/env bash
# @id: node
# @title: Install Node.js and npm
# @group: none
# @required: false
# @default: false
# @order: 20

step_node() {
    if [[ "$METATOR_OPERATION" == prepare-server ]]; then
        sudo apt-get install -y nodejs npm || return 1
    fi

    require_commands node npm || return 1
    ok 'Node.js and npm are ready'
}
