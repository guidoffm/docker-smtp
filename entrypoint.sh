#!/bin/bash
set -e

# Always start with a clean localmacros
echo -n "" > /etc/exim4/exim4.conf.localmacros

### ---------------------------------------------------------
### 1. Hostname / Mailname
### ---------------------------------------------------------
if [ -n "$MAILNAME" ]; then
    echo "MAIN_HARDCODE_PRIMARY_HOSTNAME = $MAILNAME" >> /etc/exim4/exim4.conf.localmacros
    echo "$MAILNAME" > /etc/mailname
fi


### ---------------------------------------------------------
### 2. TLS configuration (only enabled if key & cert provided)
### ---------------------------------------------------------
TLS_ENABLED=false
if [[ -n "$KEY_PATH" && -n "$CERTIFICATE_PATH" ]]; then
    TLS_ENABLED=true
    echo "MAIN_TLS_ENABLE = yes" >> /etc/exim4/exim4.conf.localmacros

    cp "$KEY_PATH" /etc/exim4/exim.key
    cp "$CERTIFICATE_PATH" /etc/exim4/exim.crt

    chgrp Debian-exim /etc/exim4/exim.key /etc/exim4/exim.crt
    chmod 640 /etc/exim4/exim.key /etc/exim4/exim.crt

    # No client verification unless user explicitly enables it
    echo "tls_verify_clients = " >> /etc/exim4/exim4.conf.localmacros
    echo "tls_try_verify_clients = false" >> /etc/exim4/exim4.conf.localmacros
fi


### ---------------------------------------------------------
### 3. Optional TLS disable patterns (DAPR fix)
### ---------------------------------------------------------
# Variable: TLS_DISABLE_ADVERTISE_HOSTS
# Format examples:
#   "smtp-relay-service.smtp"
#   "smtp-relay-service.smtp:*.svc.cluster.local"
#   "!127.0.0.1:!*.internal"

if [ -n "$TLS_DISABLE_ADVERTISE_HOSTS" ]; then
    echo "tls_advertise_hosts = ${TLS_DISABLE_ADVERTISE_HOSTS}" \
        >> /etc/exim4/exim4.conf.localmacros
fi


### ---------------------------------------------------------
### 4. Base exim4 configuration via update-exim4.conf
### ---------------------------------------------------------
opts=(
    dc_local_interfaces "[${BIND_IP:-0.0.0.0}]:${PORT:-25} ; [${BIND_IP6:-::0}]:${PORT:-25}"
    dc_other_hostnames "${OTHER_HOSTNAMES}"
    POD_IP_CIDR=$(ip -o -f inet addr show dev eth0 | awk '{print $4}' | head -n1)
    RELAY_NETS_COMBINED="$POD_IP_CIDR"
    [ -n "$RELAY_NETWORKS" ] && RELAY_NETS_COMBINED="$RELAY_NETS_COMBINED:$RELAY_NETWORKS"

    dc_relay_nets "$RELAY_NETS_COMBINED"

)


### ---------------------------------------------------------
### 5. SmartHost or Internet Mode
### ---------------------------------------------------------
if [[ -n "$SMARTHOST_ADDRESS" ]]; then
    opts+=(
        dc_eximconfig_configtype 'smarthost'
        dc_smarthost "${SMARTHOST_ADDRESS}::${SMARTHOST_PORT:-25}"
    )
else
    opts+=(
        dc_eximconfig_configtype 'internet'
    )
fi


### ---------------------------------------------------------
### 6. Extra config injection
### ---------------------------------------------------------
if [ -f /etc/exim4/_docker_additional_macros ]; then
    cat /etc/exim4/_docker_additional_macros >> /etc/exim4/exim4.conf.localmacros
fi


### ---------------------------------------------------------
### 7. Apply configuration
### ---------------------------------------------------------
/bin/set-exim4-update-conf "${opts[@]}"

exec "$@"
