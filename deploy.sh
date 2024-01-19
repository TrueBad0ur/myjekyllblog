#!/bin/bash

jekyll build --source /root/myjekyllblog/jekyll --destination /var/www/きく.コム
nginx -s reload

chown -R www-data:www-data /var/www/きく.コム
