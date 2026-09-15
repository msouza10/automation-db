#!/bin/bash

set -x 

mkdir csv

folders=(
  "configs"
  "logs"
  "results"
  "packed"
)

envs=(
  "manager-users"
  "manager-mdm"
  "business-mdm"
  "business-users"
)

for create_env in ${envs[@]}; do
  for folder in ${folders[@]}; do 
    mkdir -p "$folder/$create_env/debug"
  done
done

