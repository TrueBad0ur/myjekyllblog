#!/bin/bash

jekyll build --source ./jekyll --destination ./static/
docker compose restart
