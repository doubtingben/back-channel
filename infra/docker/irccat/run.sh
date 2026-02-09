#!/bin/sh
set -e

# Default values
: "${IRC_CHANNELS:='["#analyze-this"]'}"
: "${IRC_NICK:=irccat}"
: "${IRC_SERVER:=chat.interestedparticipant.org:6697}"

# Check for required variables
if [ -z "$IRC_PASSWORD" ]; then
    echo "Error: IRC_PASSWORD environment variable is required"
    exit 1
fi

if [ -z "$PORT" ]; then
    export PORT=8080
fi

# Substitute variables
sed -e "s|\$PORT|$PORT|g" \
    -e "s|\$IRC_PASSWORD|$IRC_PASSWORD|g" \
    -e "s|\$IRC_SERVER|$IRC_SERVER|g" \
    -e "s|\$IRC_NICK|$IRC_NICK|g" \
    -e "s|\$IRC_CHANNELS_JSON|$IRC_CHANNELS|g" \
    /app/config.json.template > /etc/irccat.json

echo "Starting irccat with config:"
cat /etc/irccat.json | grep -v "password\|secret" 

exec /app/irccat -config /etc/irccat.json
