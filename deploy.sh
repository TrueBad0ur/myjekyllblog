#!/bin/bash

jekyll build --source /root/myjekyllblog/jekyll --destination /var/www/ブログ.きく.コム
nginx -s reload

chown -R www-data:www-data /var/www/ブログ.きく.コム
