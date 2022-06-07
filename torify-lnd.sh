#!/usr/bin/env bash
set -e
LND_DIR_PATH="${PWD}/lnd"
if [[ "$1" == setup ]];
then
  # Generate random password for tor control port
  TOR_PASSWORD="$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c32;echo;)"

  apt install -y tor

  TOR_HASHED_PASSWORD="$(tor --hash-password "$TOR_PASSWORD" | tail -1)"
echo -ne "SocksPort 9050 127.0.0.1:9050

HiddenServiceDir /var/lib/tor/lnd-8080/
HiddenServicePort 8080 127.0.0.1:8080

HiddenServiceDir /var/lib/tor/lnd-10009/
HiddenServicePort 10009 127.0.0.1:10009

ControlPort 9051 127.0.0.1:9051
HashedControlPassword $TOR_HASHED_PASSWORD

" > /etc/tor/torrc

  TOR_USER="debian-tor"

  install --owner="$TOR_USER" --mode=700 --directory /var/lib/tor/lnd-{10009,8080}
  systemctl enable --now tor

  sleep 1
  LND_TOR_HOSTNAME=$(cat /var/lib/tor/lnd-8080/hostname)
  LND_SOCKET_TOR_HOSTNAME=$(cat /var/lib/tor/lnd-10009/hostname)

  if grep -q '\[tor\]' "${LND_DIR_PATH}/lnd.conf";
  then
    echo "There's already [tor] section in lnd.conf. Not modifying."
  else
    echo "
[tor]
tor.skip-proxy-for-clearnet-targets=true
tor.active=true
tor.socks=127.0.0.1:9050
tor.control=127.0.0.1:9051
tor.v3=true
tor.password=${TOR_PASSWORD}
tor.streamisolation=false
  " >> "${LND_DIR_PATH}/lnd.conf"
  fi
fi

if [[ "$1" == show_secret ]]; then
  if [[ ! -f "${LND_DIR_PATH}/secret.json" ]]; then
    echo "Not found ${LND_DIR_PATH}/secret.json: you have to launch node first"
    exit 1
  fi
  LND_TOR_HOSTNAME=$(cat /var/lib/tor/lnd-8080/hostname)
  LND_SOCKET_TOR_HOSTNAME=$(cat /var/lib/tor/lnd-10009/hostname)
  cat "${LND_DIR_PATH}/secret.json" | sed -r "s,lndconnect://.*:[0-9]+,lndconnect://${LND_TOR_HOSTNAME}:8080,g" > "${LND_DIR_PATH}/secret_tor.json.tmp"
  sed -i -r "s,\"socket\": \".*\",\"socket\": \"$LND_SOCKET_TOR_HOSTNAME:10009\",g" "${LND_DIR_PATH}/secret_tor.json.tmp"
  mv "${LND_DIR_PATH}/secret_tor.json.tmp" "${LND_DIR_PATH}/secret_tor.json"
  cat "${LND_DIR_PATH}/secret_tor.json"

  echo "Secret is saved in: ${LND_DIR_PATH}/secret_tor.json"
fi

if [[ "$1" == "" ]]; then
  echo "Usage: $0 setup | show_secret"
fi
