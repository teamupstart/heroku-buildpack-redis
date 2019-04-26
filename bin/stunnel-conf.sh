#!/usr/bin/env bash
URLS=${REDIS_STUNNEL_URLS:-REDIS_URL `compgen -v HEROKU_REDIS`}
port=6379

CONF=/app/vendor/stunnel/stunnel.conf

mkdir -p /app/vendor/stunnel/var/run/stunnel/

cat > $CONF  << EOFEOF
foreground = yes

pid = /app/vendor/stunnel/stunnel4.pid

socket = r:TCP_NODELAY=1
options = NO_SSLv3
TIMEOUTidle = 86400
ciphers = HIGH:!ADH:!AECDH:!LOW:!EXP:!MD5:!3DES:!SRP:!PSK:@STRENGTH
debug = ${STUNNEL_LOGLEVEL:-notice}

EOFEOF

# If we want to use the same client certificates as pgbouncer
if [[ "$STUNNEL_USE_PGBOUNCER_SSL" == "yes" || "$STUNNEL_USE_PGBOUNCER_SSL" == "true" ]]; then
  echo "# SSL certificates" >> $CONF
  VENDORED_STUNNEL="vendor/stunnel"
  SSLDIR="/app/$VENDORED_STUNNEL/ssl"
  mkdir -p $SSLDIR
  if [ "x$PGBOUNCER_SERVER_CAFILE" != "x" ]; then
      echo "-----> SSL: Moving the server CA file into app/vendor/stunnel/ssl"
      echo -e "$PGBOUNCER_SERVER_CAFILE" > $SSLDIR/ca.crt
      echo "CAfile = /app/$VENDORED_STUNNEL/ssl/ca.crt" >> $CONF
      chmod 600 $SSLDIR/ca.crt
  fi
  if [ "x$PGBOUNCER_SERVER_CERTFILE" != "x" ]; then
      echo "-----> SSL: Moving the server certificate file into app/vendor/stunnel/ssl"
      echo -e "$PGBOUNCER_SERVER_CERTFILE" >  $SSLDIR/client.crt
      echo "cert = /app/$VENDORED_STUNNEL/ssl/client.crt" >> $CONF
      chmod 600 $SSLDIR/client.crt
  fi
  if [ "x$PGBOUNCER_SERVER_KEYFILE" != "x" ]; then
      echo "-----> SSL: Moving the server certificate key file into app/vendor/stunnel/ssl"
      echo -e "$PGBOUNCER_SERVER_KEYFILE" >  $SSLDIR/client.key
      echo "key = /app/$VENDORED_STUNNEL/ssl/client.key" >> $CONF
      chmod 600 $SSLDIR/client.key
  fi
  echo "" >> $CONF
fi

for URL in $URLS
do
  eval URL_VALUE=\$$URL
  PARTS=$(echo $URL_VALUE | perl -lne 'print "$1 $2 $3 $4 $5 $6 $7" if /^([^:]+):\/\/([^:]+):([^@]+)@(.*?):(.*?)(\/(.*?)(\\?.*))?$/')
  URI=( $PARTS )
  URI_SCHEME=${URI[0]}
  URI_USER=${URI[1]}
  URI_PASS=${URI[2]}
  URI_HOST=${URI[3]}
  URI_PORT=${URI[4]}
  URI_PATH=${URI[5]}

  echo "Setting ${URL}_STUNNEL config var"
  export ${URL}_STUNNEL=$URI_SCHEME://$URI_USER:$URI_PASS@127.0.0.1:${port}${URI_PATH}

  cat >> $CONF << EOFEOF
[$URL]
client = yes
accept = 127.0.0.1:${port}
connect = $URI_HOST:$URI_PORT
retry = ${STUNNEL_CONNECTION_RETRY:-"no"}
EOFEOF
  if [ "x$STUNNEL_SSL_VERIFY_LEVEL" != "x" ]; then
      echo "verify = ${STUNNEL_SSL_VERIFY_LEVEL:-default}" >> $CONF
  fi
  let "port += 1"
done

chmod go-rwx /app/vendor/stunnel/*
