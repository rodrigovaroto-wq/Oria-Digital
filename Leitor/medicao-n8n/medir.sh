#!/bin/bash
# uso: medir.sh <url do webhook> ; amostra RSS do n8n principal e do task runner
URL=$1
pico_main=0; pico_run=0
( while true; do
  m=$(ps -eo rss,args | grep "n8n start" | grep -v grep | awk '{s+=$1} END{print s+0}')
  r=$(ps -eo rss,args | grep "disallow-code-generation" | grep -v grep | awk '{s+=$1} END{print s+0}')
  echo "$m $r"; sleep 0.5; done ) > /tmp/amostras.$$ &
SP=$!
t0=$(date +%s.%N)
resp=$(curl -s -m 1800 "$URL")
t1=$(date +%s.%N)
kill $SP
echo "resposta: $resp" | cut -c1-600
awk -v t="$(echo "$t1 - $t0" | bc)" '{if($1>a)a=$1; if($2>b)b=$2} END{printf "tempo total %.1f s | pico RSS principal %d MB | pico RSS runner %d MB | soma dos picos %d MB\n", t, a/1024, b/1024, (a+b)/1024}' /tmp/amostras.$$
rm /tmp/amostras.$$
