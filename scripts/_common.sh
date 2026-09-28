#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

# YaCy keeps its whole state (settings, index, logs) in a DATA folder.
# It lives in $data_dir/DATA so that upgrades, which fully replace $install_dir, never touch it.

# Set a key in yacy.conf, replacing any existing "key=value" or "key = value" line.
# YaCy must be stopped, otherwise it overwrites the file with its in-memory settings.
_yacy_set_conf() {
    local key="$1"
    local value="$2"
    local conf_file="$data_dir/DATA/SETTINGS/yacy.conf"
    local tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" '
        BEGIN { done = 0; prefix = k }
        {
            line = $0
            sub(/[ \t]*=.*/, "", line)
            if (line == prefix && index($0, "=") > 0) {
                if (!done) print k "=" v
                done = 1
                next
            }
            print
        }
        END { if (!done) print k "=" v }
    ' "$conf_file" > "$tmp"
    cat "$tmp" > "$conf_file"
    rm -f "$tmp"
}

# Settings YunoHost owns: listening port, public URL, and no attempt to open a desktop browser.
_yacy_apply_ynh_settings() {
    _yacy_set_conf "port" "$port"
    _yacy_set_conf "promoteSearchPageGreeting.homepage" "https://$domain${path%/}"
    _yacy_set_conf "browserPopUpTrigger" "false"
}

# Wait until YaCy answers HTTP requests on its port.
# Recent YaCy versions no longer log the old "Started httpd:" line, so poll the port instead.
_yacy_wait_ready() {
    local timeout=300
    local i
    for ((i = 0; i < timeout; i += 5)); do
        if curl --silent --output /dev/null --max-time 5 "http://127.0.0.1:$port/"; then
            return 0
        fi
        if ! systemctl is-active --quiet "$app"; then
            ynh_print_warn "YaCy service stopped while starting. Last log lines:"
            tail --lines=30 "$data_dir/DATA/LOG/yacy00.log" >&2 || true
            journalctl --unit="$app" --no-pager --lines=30 >&2 || true
            ynh_die "YaCy failed to start"
        fi
        sleep 5
    done
    tail --lines=30 "$data_dir/DATA/LOG/yacy00.log" >&2 || true
    ynh_die "YaCy did not answer on port $port within $timeout seconds"
}

_yacy_start() {
    ynh_systemctl --service="$app" --action="start"
    _yacy_wait_ready
}
