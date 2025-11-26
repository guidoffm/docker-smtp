#!/bin/bash
set -e

# Initialize localmacros as an empty file
echo -n "" > /etc/exim4/exim4.conf.localmacros

if [ "$MAILNAME" ]; then
	echo "MAIN_HARDCODE_PRIMARY_HOSTNAME = $MAILNAME" > /etc/exim4/exim4.conf.localmacros
	echo $MAILNAME > /etc/mailname
fi

# Check for TLS paths and enable TLS if found
if [ "$KEY_PATH" -a "$CERTIFICATE_PATH" ]; then
	if [ "$MAILNAME" ]; then
	  echo "MAIN_TLS_ENABLE = yes" >>  /etc/exim4/exim4.conf.localmacros
	else
	  echo "MAIN_TLS_ENABLE = yes" >>  /etc/exim4/exim4.conf.localmacros
	fi
	
	# ⭐ CRITICAL FIX FOR "Certificate is bad" ERROR
    # This disables the requirement for a valid client certificate (Mutual TLS),
    # which is likely causing the Dapr connection failure.
    echo "tls_verify_clients = " >> /etc/exim4/exim4.conf.localmacros
    echo "tls_crl_file = " >> /etc/exim4/exim4.conf.localmacros
    echo "tls_try_verify_clients = false" >> /etc/exim4/exim4.conf.localmacros

	# Copy certificate and key files
	cp "$KEY_PATH" /etc/exim4/exim.key
	cp "$CERTIFICATE_PATH" /etc/exim4/exim.crt
	
	# Set permissions
	chgrp Debian-exim /etc/exim4/exim.key
	chgrp Debian-exim /etc/exim4/exim.crt
	chmod 640 /etc/exim4/exim.key
	chmod 640 /etc/exim4/exim.crt
fi

# Build options for update-exim4.conf
opts=(
	# Configure listening interfaces and port (e.g., [0.0.0.0]:1025)
	dc_local_interfaces "[${BIND_IP:-0.0.0.0}]:${PORT:-25} ; [${BIND_IP6:-::0}]:${PORT:-25}"
	dc_other_hostnames "${OTHER_HOSTNAMES}"
	# Determine internal IP address for relay networks and append custom RELAY_NETWORKS
	dc_relay_nets "$(ip addr show dev eth0 | awk '$1 == "inet" { print $2 }' | xargs | sed 's/ /:/g')${RELAY_NETWORKS}"
)

if [ "$DISABLE_IPV6" ]; then
        echo 'disable_ipv6=true' >> /etc/exim4/exim4.conf.localmacros
fi

# Smarthost configurations
if [ "$GMAIL_USER" -a "$GMAIL_PASSWORD" ]; then
	opts+=(
		dc_eximconfig_configtype 'smarthost'
		dc_smarthost 'smtp.gmail.com::587'
		dc_relay_domains "${RELAY_DOMAINS}"
	)
	echo "*.gmail.com:$GMAIL_USER:$GMAIL_PASSWORD" > /etc/exim4/passwd.client
elif [ "$SES_USER" -a "$SES_PASSWORD" ]; then
	opts+=(
		dc_eximconfig_configtype 'smarthost'
		dc_smarthost "email-smtp.${SES_REGION:=us-east-1}.amazonaws.com::${SES_PORT:=587}"
		dc_relay_domains "${RELAY_DOMAINS}"
	)
	echo "*.amazonaws.com:$SES_USER:$SES_PASSWORD" > /etc/exim4/passwd.client
# Allow to specify an arbitrary smarthost (e.g., SendGrid, as per your config)
elif [ "$SMARTHOST_ADDRESS" ] ; then
	opts+=(
		dc_eximconfig_configtype 'smarthost'
		dc_smarthost "${SMARTHOST_ADDRESS}::${SMARTHOST_PORT-25}"
		dc_relay_domains "${RELAY_DOMAINS}"
	)
	rm -f /etc/exim4/passwd.client
	if [ "$SMARTHOST_ALIASES" -a "$SMARTHOST_USER" -a "$SMARTHOST_PASSWORD" ] ; then
		echo "$SMARTHOST_ALIASES;" | while read -d ";" alias; do
			echo "${alias}:$SMARTHOST_USER:$SMARTHOST_PASSWORD" >> /etc/exim4/passwd.client
		done
	fi
elif [ "$RELAY_DOMAINS" ]; then
	opts+=(
		dc_relay_domains "${RELAY_DOMAINS}"
		dc_eximconfig_configtype 'internet'
	)
else
	opts+=(
		dc_eximconfig_configtype 'internet'
	)
fi

# Allow to add additional macros by bind-mounting a file
if [ -f /etc/exim4/_docker_additional_macros ]; then
	cat /etc/exim4/_docker_additional_macros >> /etc/exim4/exim4.conf.localmacros
fi

# Run the configuration update script
/bin/set-exim4-update-conf "${opts[@]}"

# Execute the main command (which is usually 'exim -bd -q15m -v')
exec "$@"
