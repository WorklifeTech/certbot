#!/bin/bash

domains=( worklifebarometer.com worklifebarometer.se worklifebarometer.dk) # subdomain www. is included
rsa_key_size=4096
data_path="./data/certbot"
email="tech@worklifebarometer.com" # Adding a valid address is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits
domain_args="" # Additional arguments for certbot available at https://certbot.eff.org/docs/using.html#certbot-command-line-options

if [ -d "$data_path" ]; then
    read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
    if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
        exit
    fi
fi


if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "### Downloading recommended TLS parameters ..."
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
    echo
fi

for domain in "${domains[@]}"; do
    for (( n=1; n<=2; n++ )); do
        if [ $n -ge 2 ]; then
            domain="www.$domain"
        fi
        echo "### Creating dummy certificate for [$domain]"
        path="/etc/letsencrypt/live/$domain"
        mkdir -p "$data_path/conf/live/$domain"
        docker-compose run --rm --log-level ERROR --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:1024 -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot > /dev/null 2>&1
    done
done
echo

echo "### Starting nginx ..."
docker-compose up --force-recreate -d nginx
echo

for domain in "${domains[@]}"; do
    for (( n=1; n<=2; n++ )); do
        if [ $n -ge 2 ]; then
            domain="www.$domain"
        fi
        echo "### Deleting dummy certificate for [$domain]"
        docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot > /dev/null 2>&1
    done
done


domain_args="$domain_args -d"
echo "### Requesting Let's Encrypt certificate for [${domains[*]}]"
for domain in "${domains[@]}"; do
    for (( n=1; n<=2; n++ )); do
        if [ $n -le 1 ]; then
            domain_args="$domain_args $domain,"
        else
            domain_args="${domain_args}www.$domain -d"
        fi
    done
done
domain_args=${domain_args%-*} # removes the last -d
echo $domain_args # for debug only

# Select appropriate email arg
case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo


echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
