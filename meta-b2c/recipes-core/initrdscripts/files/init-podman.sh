#!/bin/sh

# Copyright (c) 2021-2022 Valve Corporation
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice (including the next
# paragraph) shall be included in all copies or substantial portions of the
# Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Author: Martin Roukala <martin.roukala@mupuf.org>
#

MODULES_PATH=/usr_mods
CONTAINER_MOUNTPOINT=/storage
CONTAINER_MOUNTPOINT_LEGACY=/container
CONTAINER_ROOTFS="$CONTAINER_MOUNTPOINT/rootfs"
CONTAINER_CACHE="$CONTAINER_MOUNTPOINT/cache"
CONTAINER_CACHE_SWAPFILE="$CONTAINER_MOUNTPOINT/swapfile"
CACHE_PARTITION_LABEL="B2C_CACHE"

RED="\e[0;31m"
CYAN="\e[0;36m"
ENDCOLOR="\e[0m"

# initial section is given from outside of our script
current_section="b2c_kernel_boot"

function log {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    echo -e "\n[$(busybox cut -d ' ' -f1 /proc/uptime)]: $*\n"
    set "-$prev_shell_config"
}

function error {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null

    # we force the following to be not in a section
    section_end $current_section

    echo -e "\n${RED}[$(busybox cut -d ' ' -f1 /proc/uptime)]: ERROR: $*${ENDCOLOR}\n"
    set "-$prev_shell_config"
}

function build_section_start {
    local section_params=$1
    shift
    local section_name=$1
    current_section=$section_name
    shift
    [ "${UNITTEST:-0}" -eq 1 ] && section_params=""
    echo -e "\n\e[0Ksection_start:`busybox date +%s`:$section_name$section_params\r\e[0K${CYAN}[$(busybox cut -d ' ' -f1 /proc/uptime)]: $*${ENDCOLOR}\n"
}

function section_start {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    build_section_start "[collapsed=true]" $*
    set "-$prev_shell_config"
}

function build_section_end {
    echo -e "\e[0Ksection_end:`busybox date +%s`:$1\r\e[0K"
    current_section=""
}

function section_end {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    build_section_end $*
    set "-$prev_shell_config"
}

function section_switch {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    if [ ! -z "$current_section" ]
    then
        build_section_end $current_section
    fi
    build_section_start "[collapsed=true]" $*
    set "-$prev_shell_config"
}

function uncollapsed_section_switch {
    # To reduce the noise related to logging, we make sure that the
    # `set -x` option is reverted before going on, but we also save what
    # was the current state so we can just restore it at the end
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    if [ ! -z "$current_section" ]
    then
        build_section_end $current_section
    fi
    build_section_start "" $*
    set "-$prev_shell_config"
}

function setup_busybox {
    for cmd in `busybox --list`; do
        [ -f "/bbin/$cmd" ] || [ -f "/bin/$cmd" ] || busybox ln -s /bin/busybox /bin/$cmd
    done
    log "Busybox setup: DONE"
}

function setup_mounts {
    mount -t proc none /proc
    mount -t sysfs none /sys
    mount -t devtmpfs none /dev
    mkdir -p /dev/pts
    mount -t devpts devpts /dev/pts

    # Mount cgroups
    mount -t cgroup2 none /sys/fs/cgroup
    cd /sys/fs/cgroup/
    for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
        mkdir -p $sys
        if ! mount -n -t cgroup -o $sys cgroup $sys; then
            rmdir $sys || true
        fi
    done

    log "Mounts setup: DONE"
}

function setup_env {
    export HOME=/root
    export PATH=/bbin:$PATH
}

# Execute a list of newline-separated list of commands
function execute_hooks {
    { local prev_shell_config=$-; set +x; } 2>/dev/null

    section_switch "execute_hooks" "$1"

    local status=0
    local OLDIFS=$IFS IFS=$'\n'
    for hook_cmd in $(echo -e "$2"); do
        IFS=$OLDIFS
        set "-$prev_shell_config"

        $hook_cmd || { log "The command failed with error code $?"; status=1; break; }

        { set +x; } 2> /dev/null
        IFS=$'\n'
    done
    IFS=$OLDIFS

    set "-$prev_shell_config"
    return $status
}

ARG_CACHE_DEVICE="none"
ARG_SWAP=""
ARG_CONTAINER=""
ARG_MODULES=""
ARG_IP_PRESENT="0"
ARG_NTP_PEER="none"
ARG_PIPEFAIL="0"
ARG_POST_CONTAINER=""
ARG_SERVICE=""
ARG_SHUTDOWN_CMD="poweroff -f"
ARG_REBOOT_CMD="reboot -f"
ARG_POWEROFF_DELAY="0"
ARG_VOLUME=""
ARG_MINIO=""
ARG_EXTRA_ARGS_URL=""
ARG_HOSTNAME="boot2container"
ARG_KEYMAP=""
ARG_FILESYSTEM=""
ARG_IFACE=""

function parse_cmdline {
    local cmdline=$1

    # Go through the list of options in the commandline, but remove the quotes
    # around multi-words arguments. Awk seems to be doing that best.
    local OLDIFS=$IFS IFS=$'\n'
    for param in $(echo "$cmdline" | awk -F\" 'BEGIN { OFS = "" } {
        for (i = 1; i <= NF; i += 2) {
            gsub(/[ \t]+/, "\n", $i)
        }
        print
    }'); do
        IFS=$OLDIFS

        value="${param#*=}"
        case $param in
            b2c.insmods=*)
                ARG_MODULES=$value
                ;;
            b2c.cache_device=*)
                ARG_CACHE_DEVICE=$value
                ;;
            b2c.swap=*)
                ARG_SWAP=$value
                ;;
            b2c.container=*)
                ARG_CONTAINER="$ARG_CONTAINER$value\n"
                ;;
            b2c.post_container=*)
                ARG_POST_CONTAINER="$ARG_POST_CONTAINER$value\n"
                ;;
            b2c.service=*)
                ARG_SERVICE="$ARG_SERVICE$value\n"
                ;;
            b2c.poweroff_delay=*)
                ARG_POWEROFF_DELAY="$value"
                ;;
            b2c.pipefail)
                ARG_PIPEFAIL="1"
                ;;
            b2c.ntp_peer=*)
                ARG_NTP_PEER=$value
                ;;
            b2c.shutdown_cmd=*)
                ARG_SHUTDOWN_CMD="$value"
                ;;
            b2c.reboot_cmd=*)
                ARG_REBOOT_CMD="$value"
                ;;
            b2c.volume=*)
                ARG_VOLUME="$ARG_VOLUME$value\n"
                ;;
            b2c.minio=*)
                ARG_MINIO="$ARG_MINIO$value\n"
                ;;
            b2c.extra_args_url=*)
                ARG_EXTRA_ARGS_URL="$value"
                ;;
            b2c.hostname=*)
                ARG_HOSTNAME="$value"
                ;;
            b2c.keymap=*)
                ARG_KEYMAP="$value"
                ;;
            b2c.iface=*)
                ARG_IFACE="$ARG_IFACE$value\n"
                ;;
            ip=*)
                ARG_IP_PRESENT=1
                ;;
            b2c.filesystem=*)
                ARG_FILESYSTEM="$ARG_FILESYSTEM$value\n"
                ;;
        esac

        IFS=$'\n'
    done
    IFS=$OLDIFS
    # TODO: add a parameter to download a volume with firmwares and modules
}

function load_modules {
    section_switch "load_modules" "Load the kernel modules wanted by the user"
    if [ -n "$@" ]; then
        for mod_name in `echo "$@" | busybox tr ',' '\n'`; do
            path="$MODULES_PATH/$mod_name"
            echo "Load the module: $path"
            insmod "$path"
        done

        log "Loading requested modules: DONE"
    fi
}

function list_candidate_network_interfaces {
    find /sys/class/net/ -type l -exec basename {} \; | grep -E '^(eth|en)' || return 0
}

function set_iface_dhcp {
    for i in $(seq 0 0.5 10); do
        for iface_name in $@; do
            if ip link set $iface_name up; then
                udhcpc -i $iface_name -s /etc/uhdcp-default.sh -T 1 -n || continue
                log "Getting IP for network interface $iface_name: $(ip address show dev $iface_name |grep "inet" |grep "$iface_name" |head -n1 |xargs |cut -d ' ' -f 2)"
                return 0
            fi
        done
        sleep 0.5 2> /dev/null
    done

    error "cannot auto-configure following network interfaces: $@"
    return 1
}

function set_iface {
    { local prev_shell_config=$-; set +x; } 2>/dev/null

    local iface_name=${@%%,*}
    local iface_address=''
    local iface_gateway=''
    local iface_route_list=''
    local iface_nameserver_list=''
    local iface_forward=0
    local iface_auto=0

    log "Set up the network interface $iface_name"

    # Parse the coma-separated list of arguments.
    # NOTICE: We add a coma at the end of the command line so as to be able to
    # remove the iface name in case there would be no parameters
    iface_params="$@,"
    local OLDIFS=$IFS IFS=,
    for spec in ${iface_params#*,}; do
        IFS=$OLDIFS
        case $spec in
            address=*)
                iface_address="${spec#address=}"
                ;;
            gateway=*)
                iface_gateway="${spec#gateway=}"
                ;;
            nameserver=*)
                iface_nameserver_list="$iface_nameserver_list ${spec#nameserver=}"
                ;;
            route=*)
                iface_route_list="$iface_route_list ${spec#route=}"
                ;;
            forward)
                iface_forward=1
                ;;
            auto|dhcp)
                iface_auto=1
                ;;
            *)
                log "WARNING: The parameter $spec is unknown for b2c.iface"
                ;;
        esac
        IFS=,
    done
    IFS=$OLDIFS

    set "-$prev_shell_config"

    [ -z "$iface_name" ] && {
        log "ERROR: b2c.iface requires a network interface name"
        return 1
    }

    if [ "$iface_auto" -eq 1 ]; then
        set_iface_dhcp $iface_name || {
            return 1
        }
    fi

    if [ -n "$iface_address" ]; then
        ip link set $iface_name up && ip address add $iface_address dev $iface_name || {
            log "ERROR: cannot configure network interface $iface_name with address $iface_address"
            return 1
        }
    fi

    [ "$iface_forward" -eq 1 ] && sysctl -w /proc/sys/net/ipv4/ip_forward=1

    [ -n "$iface_gateway" ] && {
        ip route replace default via $iface_gateway dev $iface_name || {
            log "ERROR: cannot add default gateway $iface_gateway with network interface $iface_name"
            return 1
        }
    }

    for iface_route in $iface_route_list; do
        echo "$iface_route" |grep ':' && {
            ip route replace $(echo "$iface_route" |cut -d ':' -f 1) via $(echo "$iface_route" |cut -d ':' -f 2) dev $iface_name || {
            log "ERROR: cannot add route $iface_route with network interface $iface_name"
            return 1
            }
        }
    done

    [ -n "$iface_nameserver_list" ] && {
        local prev_resolv_conf="$(cat /etc/resolv.conf)"
        echo -n > /etc/resolv.conf
        for iface_nameserver in $iface_nameserver_list; do
            echo "nameserver $iface_nameserver" >> /etc/resolv.conf
        done
        echo "$prev_resolv_conf" >> /etc/resolv.conf
    }

    return 0
}

function set_ifaces {
    log "Configuring network interfaces"
    local OLDIFS=$IFS IFS=$'\n'
    for iface in $(echo -e "$ARG_IFACE"); do
        IFS=$OLDIFS
        set_iface $iface || {
          return 1
        }
        IFS=$'\n'
    done
    IFS=$OLDIFS
}

function connect {
    section_switch "connect" "Connect to the network"

    # Reset the default DNS server configuration given by uroot
    echo -n > /etc/resolv.conf

    # Set the DNS servers according to what `ip=` set
    [ "$ARG_IP_PRESENT" -eq 1 ] && {
        grep -E '(domain|nameserver)' /proc/net/pnp > /etc/resolv.conf || /bin/true
    }

    # Prioritize b2c.iface, then ip=, then default to just running DHCP
    if [ -n "$ARG_IFACE" ]; then
        set_ifaces
        local ret=$?
        return $ret
    elif [ "$ARG_IP_PRESENT" -eq 1 ]; then
        log "Getting IP: SKIPPED (IP already set using ip=...)"
        return 0
    else
        [ -z "$(list_candidate_network_interfaces)" ] && {
            error "No suitable network interface found"
            return 1
        }

        set_iface_dhcp $(list_candidate_network_interfaces) && return $?
    fi
}

function ntp_set {
    section_switch "ntp_set" "Synchronize the clock"

    case $1 in
        none)
            log "WARNING: Did not reset the time, use b2c.ntp_peer=auto to set it on boot"
            return 0
            ;;
        auto)
            peer_addr="pool.ntp.org"
            ;;
        *)
            peer_addr=$1
    esac

    # Limit the maximum execution time to prevent the boot sequence to be stuck
    # for too long
    local status="FAILED"
    for i in $(seq 1 3)}; do
        timeout 5 ntpd -dnq -p "$peer_addr" && {
            status="DONE"
            break
        }
    done

    log "Getting the time from the NTP server $peer_addr: $status"
}

function set_keymap {
    section_switch "set_keymap" "Setting the keymap"
    if [ -n "$ARG_KEYMAP" ]; then
        path_keymap=$(find /usr/share/keymaps -type f -name "${ARG_KEYMAP}.kmap" |head -n1)
        if [ -n "$path_keymap" ]; then
            status="DONE"
            loadkmap < $path_keymap || status="FAILED"
            log "Loading keymap file $path_keymap: $status"
        else
            error "Cannot find any keymap file named ${ARG_KEYMAP}.kmap!"
        fi
    fi

    return 0
}

function parse_extra_cmdline {
    section_switch "parse_extra_cmdline" "Download and parse the extra command line"

    success=0
    if [ -n "$ARG_EXTRA_ARGS_URL" ]; then
        if wget -O /tmp/extra_args "$ARG_EXTRA_ARGS_URL"; then
            log "Parse the extra command line"
            if ! parse_cmdline "$(cat /tmp/extra_args)"; then
                success=1
                error "Failed to parse the extra command line, shutting down!"
            fi
        else
            success=1
            error "Could not download the extra command line, shutting down!"
        fi
    fi

    return $success
}

function find_container_partition {
    dev_name=`blkid | grep "LABEL=\"$CACHE_PARTITION_LABEL\"" | head -n 1 | cut -d ':' -f 1`
    if [ -n "$dev_name" ]; then
        echo $dev_name
        return 0
    else
        return 1
    fi
}

function format_cache_partition {
    log "Formatting the partition $CONTAINER_PART_DEV"

    # Enable unconditionally the encryption
    mkfs.ext4 -O encrypt -F -L "$CACHE_PARTITION_LABEL" "$CONTAINER_PART_DEV"
}

function format_disk {
    if [ -n "$1" ]; then
        parted --script $1 mklabel gpt
        parted --script $1 mkpart primary ext4 2048s 100%

        CONTAINER_PART_DEV=`lsblk -no PATH $1 | tail -n -1`
        format_cache_partition

        return $?
    fi

    return 1
}

function find_or_create_cache_partition {
    for i in $(seq 0 0.5 9.5); do
        # See if we have an existing block device that would work
        CONTAINER_PART_DEV=`find_container_partition` && return 0

        # Find a suitable disk
        sr_disks_majors=`grep ' sr' /proc/devices | sed "s/^[ \t]*//" | cut -d ' ' -f 1 | tr '\n' ',' | sed 's/,$//'`
        disk=`lsblk -ndlfp -e "$sr_disks_majors" | head -n 1`

        if [ -n "$disk" ]; then
            log "No existing cache partition found on this machine, create one from the disk $disk"

            # Find a disk, partition it, then format it as ext4
            format_disk $disk || return 1
            return 0
        fi

        sleep 0.5
    done

    log "No disks founds, continue without a cache"
    return 1
}

function reset_cache_partition {
    log "Reset the cache partition"

    # Find the cache partition, and if missing, default to
    # the same behaviour as "auto".
    CONTAINER_PART_DEV=`find_container_partition` || {
        find_or_create_cache_partition
        return $?
    }

    # Found the partition, reformat it!
    format_cache_partition || return 1

    return 0
}

function try_to_use_cache_device {
    # $ARG_CACHE_DEVICE has to be a path to a drive
    # NOTE: Pay attention to the space after $ARG_CACHE_DEVICE, as it
    # makes sure that we don't accidentally match /dev/sda1 when asking
    # for /dev/sda.
    blk_dev=`lsblk -rpno PATH,TYPE,LABEL | grep "$ARG_CACHE_DEVICE "`
    if [ -z "$blk_dev" ]; then
        error "The device '$ARG_CACHE_DEVICE' is neither a block device, nor a partition. Defaulting to no caching."
        return 1
    fi

    path=$(echo "$blk_dev" | cut -d ' ' -f 1)
    type=$(echo "$blk_dev" | cut -d ' ' -f 2)
    label=$(echo "$blk_dev" | cut -d ' ' -f 3)
    case $type in
        part)
            CONTAINER_PART_DEV="$path"
            if [ -z "$label" ]; then
                format_cache_partition
                return $?
            fi
            ;;

        disk)
            # Look for the first partition from the drive $1, that has the right cache
            CONTAINER_PART_DEV=`lsblk -no PATH,LABEL $path | grep "$CACHE_PARTITION_LABEL" | cut -d ' ' -f 1 | head -n 1`
            if [ -n "$CONTAINER_PART_DEV" ]; then
                return 0
            else
                log "No existing cache partition on the drive $path, recreate the partition table and format a partition"
                format_disk $path
                return $?
            fi
            ;;
    esac

    return 0
}

function mount_swap_file {
    [ -f "$CONTAINER_CACHE_SWAPFILE" ] && rm "$CONTAINER_CACHE_SWAPFILE"

    fallocate -l "$ARG_SWAP" "$CONTAINER_CACHE_SWAPFILE" || return 1
    mkswap "$CONTAINER_CACHE_SWAPFILE"  || return 1
    swapon "$CONTAINER_CACHE_SWAPFILE"  || return 1

    return 0
}

function unmount_swap_file {
    # Remove the swap file, if present
    if [ -f "$CONTAINER_CACHE_SWAPFILE" ]; then
        swapoff $CONTAINER_CACHE_SWAPFILE
        rm $CONTAINER_CACHE_SWAPFILE
    fi
}

function mount_filesystem {
    # Disable logging for filesystem parsing
    { local prev_shell_config=$-; set +x; } 2>/dev/null

    local fs_name=$1
    local mount_point=$2
    local src=""
    local type=""
    local opts=""

    local OLDIFS=$IFS IFS=$'\n'
    for filesystem in $(echo -e "$ARG_FILESYSTEM"); do
        local filesystem_name=${filesystem%%,*}

        # Don't parse the filesystem definition if the names don't match
        if [[ "$fs_name" != "$filesystem_name" ]]; then
            IFS=$'\n'
            continue
        fi

        # Parse the coma-separated list of arguments.
        # NOTICE: We add a coma at the end of the command line so as to be able to
        # remove the filesystem name in case there would be no parameters
        filesystem_params="$filesystem,"
        local IFS=,
        for spec in ${filesystem_params#*,}; do
            IFS=$OLDIFS

            case $spec in
                type=*)
                    type="-t ${spec#type=}"
                    ;;
                src=*)
                    src="${spec#src=}"
                    ;;
                opts=*)
                    local opts="-o $(echo ${spec#opts=} | tr '|', ',')"
                    ;;
                *)
                    echo "B2C_WARNING: The filesystem parameter $spec is unknown"
                    ;;
            esac
        done

        # Parsing is over, re-enable logging
        set "-$prev_shell_config"

        # Check that all the mandatory arguments are specified
        if [ -z "$src" ]; then
            error "The $filesystem_name b2c.filesystem definition is missing the mandatory parameter src"
            return 1
        fi

        # Mount the filesystem
        mount $type $opts $src $mount_point || return 1

        return 0
    done
    IFS=$OLDIFS

    # Parsing is over, re-enable logging
    set "-$prev_shell_config"

    return 1
}

CONTAINER_PART_DEV=""
function mount_cache_partition {
    [ -d "$CONTAINER_MOUNTPOINT" ] || mkdir "$CONTAINER_MOUNTPOINT"
    [ -L "$CONTAINER_MOUNTPOINT_LEGACY" ] || ln -s "$CONTAINER_MOUNTPOINT" "$CONTAINER_MOUNTPOINT_LEGACY"

    # Find a suitable cache partition
    local status=""
    case $ARG_CACHE_DEVICE in
        none)
            log "Do not use a partition cache"
            return 0
            ;;
        auto)
            find_or_create_cache_partition || return 0
            ;;
        reset)
            reset_cache_partition || return 0
            ;;
        *)
            if mount_filesystem "$ARG_CACHE_DEVICE" "$CONTAINER_MOUNTPOINT"; then
                log "Mounted the $ARG_CACHE_DEVICE b2c.filesystem as a cache device"
                status="DONE"
            elif [[ "$ARG_CACHE_DEVICE" == "/dev/*" ]]; then
                if [ -e "$ARG_CACHE_DEVICE" ]; then
                    try_to_use_cache_device "$ARG_CACHE_DEVICE" || return 0
                else
                    log "The device node ${ARG_CACHE_DEVICE} is missing... waiting up to 10 seconds for it to appear"

                    for i in $(seq 0 0.5 9.5); do
                        sleep 0.5

                        if [ -e "$ARG_CACHE_DEVICE" ]; then
                            try_to_use_cache_device "$ARG_CACHE_DEVICE" || return 0
                            break
                        fi
                    done

                    if [ -z "$CONTAINER_PART_DEV" ]; then
                        log "The device node '$ARG_CACHE_DEVICE' did not appear. Defaulting to 'none'"
                        return 0
                    fi
                fi
            else
                log "The caching parameter '$ARG_CACHE_DEVICE' is neither 'none', 'auto', a path to a block device, or a valid b2c.filesystem name. Defaulting to 'none'"
                return 0
            fi
            ;;
    esac

    if [ "$status" != 'DONE' ]; then
        log "Selected the partition $CONTAINER_PART_DEV as a cache"
        status="DONE"
        mount "$CONTAINER_PART_DEV" "$CONTAINER_MOUNTPOINT" || status="FAILED"
        log "Mounting the partition $CONTAINER_PART_DEV to $CONTAINER_MOUNTPOINT: $status"
    fi

    # If the partition has been mounted
    if [ $status == 'DONE' ]; then
        log "Checking the available space in the cache partition"

        # Check how much disk space is available in it
        df -h $CONTAINER_PART_DEV

        # Mount the swap file, if asked
        if [ -n "$ARG_SWAP" ]; then
            log "Mounting a swap file"

            status="DONE"
            mount_swap_file || status="FAILED"

            log "Mounting a swap file of $ARG_SWAP: $status"
        fi
    fi

    return 0
}

function unmount_cache_partition {
    section_switch "unmount_cache_partition" "Unmount the cache partition"
    if [ -n "$CONTAINER_PART_DEV" ]; then
        sync

        status="DONE"
        unmount_swap_file || status="FAILED"
        log "Unmounting the swap file: $status"

        status="DONE"
        umount $CONTAINER_PART_DEV || status="FAILED"
        log "Remounting the partition $CONTAINER_PART_DEV read-only: $status"
    fi
}

function setup_container_runtime {
    # HACK: I could not find a way to change the right parameter in podman's
    # config, so make a symlink for now
    [ -d "$CONTAINER_CACHE" ] || mkdir "$CONTAINER_CACHE"
    [ -f "/var/tmp" ] || ln -s "$CONTAINER_CACHE" /var/tmp

    # Squash a kernel warning
    echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy

    # Set some configuration files
    touch /etc/hosts
    echo "root:x:0:0:root:/root:/bin/sh" > /etc/passwd
    echo "containers:165536:65537" > /etc/subuid
    echo "containers:165536:65537" > /etc/subgid

    log "Container runtime setup: DONE"
}

function start_daemon_cmd {
    myunshare -Ufp --kill-child -- /bin/run_cmd_in_loop.sh $@ &

    # Hide the rest of the execution
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local pid=$!

    # Give the shell some time to write the previous command
    sleep 0.01

    # Make sure to kill the service at the end of the pipeline
    B2C_HOOK_PIPELINE_END="${B2C_HOOK_PIPELINE_END}pkill -9 -P $pid\n"
    set "-$prev_shell_config"
}

function queue_pipeline_end_cmd {
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    B2C_HOOK_PIPELINE_END="${B2C_HOOK_PIPELINE_END}$@\n"
    set "-$prev_shell_config"
}

function call_mcli_mirror_on_hook_conditions {
    local conditions=$1
    local mcli_args=$2

    local has_non_changes_cond=0
    local has_changes_cond=0

    local cmd="mcli mirror $mcli_args"
    local watch_cmd="mcli mirror --watch $mcli_args"

    # If "changes" is set, we need to handle that and ignore the rest
    local OLDIFS=$IFS IFS='|'
    for condition in ${conditions}; do
        IFS=$OLDIFS
        case "${condition}" in
            pipeline_start|container_start|container_end|pipeline_end)
                has_non_changes_cond=1
                ;;
            changes)
                # Start the --watch command in the background
                B2C_HOOK_PIPELINE_START="${B2C_HOOK_PIPELINE_START}start_daemon_cmd $watch_cmd\n"

                # Since we want to make sure that all the changes made by the container have been pushed
                # back to minio before shutting down the machine, and since we can't signal to mcli's
                # mirror operation we want to exit as soon as all the currently-pending transfers are over,
                # we first need to kill the 'mcli mirror --watch' process before starting the final sync.
                # The start_daemon_cmd function already set up the killing of the background process
                # at pipeline_end, so all we have to do is queue the final mirroring command. To do so,
                # just add a pipeline_start hook that will run right after the start_daemon_cmd,
                # and will add the command to the pipeline_end hook list. Sorry for the mess!
                B2C_HOOK_PIPELINE_START="${B2C_HOOK_PIPELINE_START}queue_pipeline_end_cmd $cmd\n"

                has_changes_cond=1
                ;;
            *)
                echo "B2C_WARNING: The hook condition '$condition' is unknown"
                ;;
        esac
        IFS='|'
    done

    if [ "$has_changes_cond" -eq 0 ]; then
        local OLDIFS=$IFS IFS='|'
        for condition in ${conditions}; do
            IFS=$OLDIFS
            case "${condition}" in
                pipeline_start)
                    B2C_HOOK_PIPELINE_START="${B2C_HOOK_PIPELINE_START}${cmd}\n"
                    ;;
                container_start)
                    B2C_HOOK_CONTAINER_START="${B2C_HOOK_CONTAINER_START}${cmd}\n"
                    ;;
                container_end)
                    B2C_HOOK_CONTAINER_END="${B2C_HOOK_CONTAINER_END}${cmd}\n"
                    ;;
                pipeline_end)
                    B2C_HOOK_PIPELINE_END="${B2C_HOOK_PIPELINE_END}${cmd}\n"
                    ;;
            esac
            IFS='|'
        done
    elif [ "$has_non_changes_cond" -eq 1 ]; then
        # Friendly reminder to distracted users
        echo "B2C_WARNING: When the 'changes' condition is set, all other conditions are ignored"
    fi
}

function setup_volume {
    # Disable logging for volume parsing
    { local prev_shell_config=$-; set +x; } 2>/dev/null

    local volume_name=${@%%,*}
    local filesystem=''
    local pull_url=''
    local push_url=''
    local pull_on=''
    local push_on=''
    local expiration='never'
    local mirror_extra_args=''
    local fscrypt_key=''
    local fscrypt_reset_key="0"

    log "Set up the $volume_name volume"

    # Parse the coma-separated list of arguments.
    # NOTICE: We add a coma at the end of the command line so as to be able to
    # remove the volume name in case there would be no parameters
    volume_params="$@,"
    local OLDIFS=$IFS IFS=,
    for spec in ${volume_params#*,}; do
        IFS=$OLDIFS

        case $spec in
            filesystem=*)
                filesystem="${spec#filesystem=}"
                ;;
            mirror=*)
                pull_url="${spec#mirror=}"
                push_url="${spec#mirror=}"
                ;;
            pull_from=*)
                pull_url="${spec#pull_from=}"
                ;;
            push_to=*)
                push_url="${spec#push_to=}"
                ;;
            pull_on=*)
                pull_on="${spec#pull_on=}"
                ;;
            push_on=*)
                push_on="${spec#push_on=}"
                ;;
            expiration=*)
                expiration="${spec#expiration=}"
                ;;
            overwrite)
                mirror_extra_args="$mirror_extra_args --overwrite"
                ;;
            remove)
                mirror_extra_args="$mirror_extra_args --remove"
                ;;
            exclude=*)
                mirror_extra_args="$mirror_extra_args --exclude ${spec#exclude=}"
                ;;
            encrypt_key=*)
                mirror_extra_args="$mirror_extra_args --encrypt-key ${spec#encrypt_key=}"
                ;;
            preserve)
                mirror_extra_args="$mirror_extra_args -a"
                ;;
            fscrypt_key=*)
                fscrypt_key="${spec#fscrypt_key=}"
                ;;
            fscrypt_reset_key)
                fscrypt_reset_key="1"
                ;;
            *)
                echo "B2C_WARNING: The parameter $spec is unknown"
                ;;
        esac
        IFS=,
    done
    IFS=$OLDIFS

    # Parse the expiration policy
    # TODO: Allow setting expiration dates with a format compatible with `date "+1 day"
    if [ -n "$expiration" ]; then
        case $expiration in
            never|pipeline_end)
                # Nothing to do, as these are valid
                ;;
            *)
                error "Unknown value for expiration: $expiration"
                return 1
                ;;
        esac
    fi

    # Parsing is over, re-enable logging
    set "-$prev_shell_config"

    # Create the volume, if it does not exist
    if ! podman volume exists "$volume_name" ; then
        podman volume create --label "expiration=$expiration" "$volume_name" || return 1
    fi

    # Get the volume's mount point, and make sure the volume exists
    local local_dir=$(podman volume inspect --format "{{.Mountpoint}}" $volume_name)
    [ -d "$local_dir" ] || {
        mkdir -p "$local_dir" || return 1
    }

    # Mount the wanted filesystem, if asked to
    if [ -n "$filesystem" ]; then
        mount_filesystem "$filesystem" "$local_dir" || {
            error "Could not mount the b2c.filesystem named '$filesystem'."
            return 1
        }
    fi

    # Check if the volume was already encrypted
    fscryptctl get_policy "$local_dir" &> /dev/null && volume_already_encrypted=1 || volume_already_encrypted=0

    # Enable the encryption, if wanted
    if [ -n "$fscrypt_key" ]; then
        local key_id=""

        echo "Enabling encryption:"
        echo "  - Current status: volume_encrypted=$volume_already_encrypted"
        echo "  - Adding the fscrypt key to the volume mount point"
        key_id=$(echo "$fscrypt_key" | base64 -d | fscryptctl add_key "$local_dir") || {
            # If this fails, this means the kernel/filesystem does not support encryption, or the
            # partition has not been created with "-O encrypt".
            error "You may need to reset the cache using 'b2c.cache_device=reset' to enable encryption if it was created with boot2container <= 0.9"
            return 1
        }

        echo "  - Setting the policy on the volume mount point"
        if ! fscryptctl set_policy "$key_id" "$local_dir"; then
            # Setting the policy failed. This can be due to a kernel with missing config, a
            # non-empty folder, or simply trying to use the wrong key.

            # If the directory is not encrypted, or if we asked to reset the key
            if [ "$volume_already_encrypted" -eq "0" ] || [ "$fscrypt_reset_key" -eq "1" ]; then
                echo "Re-try applying the policy after resetting the volume"

                # Remove the volume then re-create it
                rm -rf "$local_dir" || return 1
                mkdir "$local_dir" || return 1

                # Try setting the policy again
                fscryptctl set_policy "$key_id" "$local_dir" || return 1
            elif [ "$volume_already_encrypted" -eq "1" ]; then
                error "Missing kernel config options, or wrong fscrypt key provided"
                return 1
            fi
        fi

        # Make sure the volume is encrypted
        fscryptctl get_policy "$local_dir" || return 1
    elif [ "$volume_already_encrypted" -eq 1 ]; then
        error "Trying to use an already-encrypted volume without providing a key"
        return 1
    fi

    # Mirror setup
    if [ -n "$pull_url" ] && [ -n "$push_url" ] ; then
        # Set up the mirroring operations
        local mcli_mirror_args="-r $local_dir -q --no-color $mirror_extra_args"
        call_mcli_mirror_on_hook_conditions "$pull_on" "$mcli_mirror_args $pull_url ."
        call_mcli_mirror_on_hook_conditions "$push_on" "$mcli_mirror_args . $push_url"
    fi
}

function remove_expired_volumes {
    volumes=$(podman volume list --noheading --format {{.Name}} --filter label=expiration=pipeline_end) || return $?

    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for volume_name in $volumes; do
        IFS=$OLDIFS
        set "-$prev_shell_config"

        podman volume rm --force "$volume_name" || /bin/true

        { set +x; } 2>/dev/null
        IFS='\n'
    done
    IFS=$OLDIFS
    set "-$prev_shell_config"
}

function setup_volumes {
    # Remove all the expired volumes, before setting up the new ones
    log "Remove expired volumes"
    remove_expired_volumes || /bin/true

    # Set all the minio aliases before we potentially try using them
    log "Set up the minio aliases"
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for minio in $(echo -e "$ARG_MINIO"); do
        IFS=$OLDIFS
        minio_cmd=$(echo $minio | tr ',' ' ')
        set "-$prev_shell_config"

        mcli --no-color alias set $minio_cmd || return 1

        { set +x; } 2>/dev/null
        IFS=$'\n'
    done
    IFS=$OLDIFS

    log "Create the volumes"
    local OLDIFS=$IFS IFS=$'\n'
    for volume in $(echo -e "$ARG_VOLUME"); do
        IFS=$OLDIFS

        set "-$prev_shell_config"
        setup_volume $volume || {
            set "-$prev_shell_config"
            return 1
        }
        { set +x; } 2>/dev/null

        IFS=$'\n'
    done
    IFS=$OLDIFS

    log "Setting up volumes: DONE"

    # Now that the early boot is over, let's log every command executed
    set "-$prev_shell_config"
}

function create_container {
    # Podman is not super good at explaining what went wrong when creating a
    # container, so just try multiple times, each time increasing the size of
    # the hammer!
    for i in 0 1 2 3 4; do
        { cmdline="podman create --rm --privileged --pull=always --network=host \
--runtime /bin/crun-no-pivot -e B2C_PIPELINE_STATUS=$B2C_PIPELINE_STATUS \
-e B2C_PIPELINE_FAILED_BY=\"$B2C_PIPELINE_FAILED_BY\" \
-e B2C_PIPELINE_PREV_CONTAINER=\"$B2C_PIPELINE_PREV_CONTAINER\" \
-e B2C_PIPELINE_PREV_CONTAINER_EXIT_CODE=$B2C_PIPELINE_PREV_CONTAINER_EXIT_CODE \
-e B2C_PIPELINE_SHUTDOWN_MODE=$B2C_PIPELINE_SHUTDOWN_MODE"; } 2> /dev/null

        # Set up the wanted container
        container_id=`eval "$cmdline $@"` && podman init "$container_id" && {
            # Make sure that the layers and volumes got pushed to the drive before
            # running the container
            sync

            # HACK: Figure out how to use "podman wait" to wait for the container to be
            # ready for execution. Without this sleep, we sometimes fail to attach the
            # stdout/err to the container. Even a one ms sleep is sufficient in my
            # testing, but let's add a bit more just to be sure
            sleep .1

            return 0
        }

        # The command failed... Ignore the first 3 times, as we want to check it
        # is not a shortlived-network error
        if [ $i -eq 3 ]; then
            # Try removing all our container images before trying again!
            # TODO: keep track of the cache usage, and as a way to specify how much
            # storage we want to keep available at all time.
            podman rmi -a -f
        fi

        sleep 1
    done

    return 1
}

function start_container {
    execute_hooks "Execute the container_start hooks" "$B2C_HOOK_CONTAINER_START" || return 1

    section_switch "create_container" "Pull, create, and init the container"
    { container_id=""; } 2> /dev/null
    create_container $@ || return 1

    uncollapsed_section_switch "container_run" "About to start executing a container"
    podman start -a "$container_id" || exit_code=$?

    # Drop the 'set -x' for the next command until we get back in a section
    { section_switch "b2c_post_container" "gathering container results"; } 2>/dev/null

    # Store the results of the execution
    B2C_PIPELINE_PREV_CONTAINER="$@"
    B2C_PIPELINE_PREV_CONTAINER_EXIT_CODE="$exit_code"

    # When a container calls the reboot syscall (also used to shutdown),
    # the kernel will kill the pid 1 of the container, and make it look like
    # the process died because of the SIGHUP/SIGINT signals, for reboot and
    # shutdown respectively. See 'man 2 reboot' for more information.
    # Podman's exit code when the pid 1 process dies due to a signal will be
    # 128 + signal number. On all supported architectures, 129 means reboot
    # while 130 means poweroff.
    case "$exit_code" in
        129)
            B2C_PIPELINE_SHUTDOWN_MODE="reboot"
            ;;
        130)
            B2C_PIPELINE_SHUTDOWN_MODE="poweroff"
            ;;
    esac

    execute_hooks "Execute the container_end hooks" "$B2C_HOOK_CONTAINER_END" || return 1

    return $exit_code
}

function start_service_containers {
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for container_params in $(echo -e "$@"); do
        IFS=$OLDIFS
        set "-$prev_shell_config"

        exit_code=0
        section_switch "start_service_container" "Pull, create, init, and start the service container"
        create_container "$container_params" || return 1
        podman start "$container_id" || exit_code=$?
        section_end "start_service_container"

        { set +x; } 2>/dev/null
        IFS=$'\n'
    done
    IFS=$OLDIFS

    set "-$prev_shell_config"
    { return 0; } 2> /dev/null
}

function start_containers {
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for container_params in $(echo -e "$@"); do
        IFS=$OLDIFS

        exit_code=0
        set "-$prev_shell_config"
        start_container "$container_params" || exit_code=$?

        { set +x; } 2> /dev/null
        if [ $exit_code -eq 0 ] ; then
            log "The container run successfully, load the next one!"
        else
            # If this is the first container that failed, store that information
            if [ $B2C_PIPELINE_STATUS -eq 0 ]; then
                B2C_PIPELINE_STATUS="$exit_code"
                B2C_PIPELINE_FAILED_BY="$container_params"
            fi

            if [ $ARG_PIPEFAIL -eq 1 ]; then
                log "The container exited with error code $exit_code, aborting the pipeline..."
                set "-$prev_shell_config"
                { return 0; } 2> /dev/null
            else
                log "The container exited with error code $exit_code, continuing..."
            fi
        fi

        IFS=$'\n'
    done
    IFS=$OLDIFS

    set "-$prev_shell_config"
    { return 0; } 2> /dev/null
}

function start_post_containers {
    log "Running the post containers"

    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for container_params in $(echo -e "$@"); do
        IFS=$OLDIFS
        set "-$prev_shell_config"

        start_container "$container_params" || /bin/true

        { set +x; } 2>/dev/null
        IFS=$'\n'
    done
    IFS=$OLDIFS

    set "-$prev_shell_config"
    { return 0; } 2> /dev/null
}

function container_cleanup {
    # Stop and delete all the containers that may still be running.
    # This should be a noop, but I would rather be safe than sorry :)

    # There is a race in podman https://github.com/containers/podman/issues/4314
    # Copy a similar dance done in the upstream CI for podman push
    podman container stop -a || { sleep 2; podman container stop -a; } || /bin/true

    timeout 20 podman umount -a -f || /bin/true
    timeout 20 podman container rm -fa || /bin/true

    # Remove all the dangling images
    timeout 20 podman image prune -f || /bin/true
}

function unmount_all_volumes {
    local volumes=$(podman volume list --noheading --format {{.Name}}) || return $?

    { local prev_shell_config=$-; set +x; } 2>/dev/null
    local OLDIFS=$IFS IFS=$'\n'
    for volume_name in $volumes; do
        IFS=$OLDIFS
        set "-$prev_shell_config"

        # Unmount the volume if it is backed by a filesystem
        local local_dir=$(podman volume inspect --format "{{.Mountpoint}}" $volume_name)
        if mountpoint -q "$local_dir"; then
            umount "$local_dir"
        fi

        { set +x; } 2>/dev/null
        IFS='\n'
    done
    IFS=$OLDIFS
    set "-$prev_shell_config"
}

function run_containers {
    section_switch "start_pipeline" "Run all the cmdline-specified containers"
    # Hide all the default values
    { local prev_shell_config=$-; set +x; } 2>/dev/null
    B2C_PIPELINE_STATUS="0"
    B2C_PIPELINE_FAILED_BY=""
    B2C_PIPELINE_PREV_CONTAINER=""
    B2C_PIPELINE_PREV_CONTAINER_EXIT_CODE=""
    B2C_HOOK_PIPELINE_START=""
    B2C_HOOK_CONTAINER_START=""
    B2C_HOOK_CONTAINER_END=""
    B2C_HOOK_PIPELINE_END=""
    log "Run the containers"
    set "-$prev_shell_config"

    if [ -n "$ARG_CONTAINER$ARG_POST_CONTAINER" ]; then
        setup_container_runtime  # TODO: Add tests for this
        if setup_volumes; then
            if execute_hooks "Execute the pipeline_start hooks" "$B2C_HOOK_PIPELINE_START"; then
                log "Start the background services"
                if start_service_containers "$ARG_SERVICE"; then
                    log "Start the containers pipeline"

                    start_containers "$ARG_CONTAINER"
                    start_post_containers "$ARG_POST_CONTAINER"
                fi

                execute_hooks "Execute the pipeline_end hooks" "$B2C_HOOK_PIPELINE_END" || {
                    if [ "$B2C_PIPELINE_STATUS" -eq 0 ]; then
                        B2C_PIPELINE_STATUS=1
                        B2C_PIPELINE_FAILED_BY="Pipeline-end hooks"
                    fi
                }
            else
                B2C_PIPELINE_STATUS=1
                B2C_PIPELINE_FAILED_BY="Pipeline-start hooks"
            fi
        else
            B2C_PIPELINE_STATUS=1
            B2C_PIPELINE_FAILED_BY="Volume setup"
        fi

        log "Execution is over, pipeline status: ${B2C_PIPELINE_STATUS}"

        section_switch "cleanup" "Done executing the pipeline, clean up time!"
        container_cleanup
        unmount_all_volumes
        remove_expired_volumes
    fi
}

function print_runtime_info {
    section_switch "runtime_info" "Runtime information"
    echo -e "Linux version: $(cat /proc/sys/kernel/osrelease)\n\
Boot2container version: $(cat /etc/b2c.version)\n\
Architecture: $(uname -m)\n\
CPU: $(cat /proc/cpuinfo | grep "model name" | head -n 1 | cut -d ':' -f 2- | cut -d ' ' -f 2-)\n\
RAM: $(cat /proc/meminfo | grep "MemTotal" | head -n 1 | rev | cut -d ' ' -f 1-2 | rev)\n\
Block devices: $(lsblk -rdno NAME,SIZE | tr ' ' '=' | tr '\n' ' ')"
}

function set_hostname {
    section_switch "set_hostname" "Set the hostname"
    echo "$ARG_HOSTNAME\n" > /etc/hostname
    hostname "$ARG_HOSTNAME" || /bin/true
}

do_mount_fs() {
  grep -q "$1" /proc/filesystems || return
  test -d "$2" || mkdir -p "$2"
  mount -t "$1" "$1" "$2"
}

do_mknod() {
  test -e "$1" || mknod "$1" "$2" "$3" "$4"
}

function main {
    set -eu

    PATH=/sbin:/bin:/usr/sbin:/usr/bin


    mkdir -p /proc
    mount -t proc proc /proc

    do_mount_fs sysfs /sys
    do_mount_fs debugfs /sys/kernel/debug
    do_mount_fs devtmpfs /dev
    do_mount_fs devpts /dev/pts
    do_mount_fs tmpfs /dev/shm
    # Mount cgroups
    mount -t cgroup2 none /sys/fs/cgroup
    cd /sys/fs/cgroup/
        for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
            mkdir -p $sys
            if ! mount -n -t cgroup -o $sys cgroup $sys; then
                rmdir $sys || true
            fi
        done



    mkdir -p /run
    mkdir -p /var/run

    do_mknod /dev/console c 5 1
    do_mknod /dev/null c 1 3
    do_mknod /dev/zero c 1 5

    set > /tmp/envfile
    exec sh </dev/console >/dev/console 2>/dev/console 
}

function main2 {
    section_switch "b2c_setup" "Setting up boot2container"

    # Initial setup
    B2C_PIPELINE_SHUTDOWN_MODE="default"
    setup_busybox
    #setup_mounts  # To be continued to so we could boot without any go commands
    setup_env

    # Parse the kernel command line, in search of the b2c parameters
    parse_cmdline "$(busybox cat /proc/cmdline)"

    # Initial information about the machine
    print_runtime_info

    # Now that the early boot is over, let's log every command executed
    set -x

    set > /tmp/envfile
    sh

    # Load the user-requested modules
    load_modules $ARG_MODULES

    # Mount the cache partition
    section_switch "mount_cache_partition" "Mount the cache partition"
    mount_cache_partition

    # Connect to the network, now that the modules are loaded
    if connect; then
        # Set the time
        ntp_set $ARG_NTP_PEER

        # Download the extra arguments
        if parse_extra_cmdline; then
            set_hostname
            set_keymap

            # Start the containers
            run_containers
        fi
    else
        log "ERROR: Could not connect to the network, shutting down!"
    fi

    # Prepare for the shutdown
    unmount_cache_partition

    # Tearing down the machine, turn down the verbosity and close the section
    { set +x; } 2> /dev/null
    section_end "$current_section"

    # Shutdown/reboot the machine
    case "$B2C_PIPELINE_SHUTDOWN_MODE" in
        reboot)
            log "Rebooting the computer"
            SHUTDOWN_CMD="$ARG_REBOOT_CMD"
            ;;
        default|poweroff)
            log "It's now safe to turn off your computer"  # I feel old...
            if [ "$ARG_POWEROFF_DELAY" != "0" ]; then
                echo sleep $ARG_POWEROFF_DELAY
                sleep $ARG_POWEROFF_DELAY || /bin/true
            fi
            SHUTDOWN_CMD="$ARG_SHUTDOWN_CMD"
            ;;
    esac

    eval $SHUTDOWN_CMD
}

# Call the main function, unless the entire file is being unit-tested
[ "${UNITTEST:-0}" -eq 0 ] && main