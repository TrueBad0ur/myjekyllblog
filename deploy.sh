#!/bin/bash

jekyll build --source /root/mywebsite/jekyll --destination /var/www/ブログ.きく.コム
nginx -s reload

chown -R www-data:www-data /var/www/ブログ.きく.コム
