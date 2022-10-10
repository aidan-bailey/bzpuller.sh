#!/bin/bash

set -b

if [ $# -lt 2 ]; then
  echo "----------------------------------------------------------------"
  echo "                       BINANCE ZIP PULLER"
  echo "----------------------------------------------------------------"
  echo " USAGE:"
  echo -e "\t   bzpuller.sh <AGGREGATION> <MARKET> <INTERVAL>"
  echo ""
  echo " ARGUMENTS:"
  echo ""
  echo "   AGGREGATION"
  echo "       the level of aggregation per zip"
  echo "       options: monthly daily"
  echo "   MARKET"
  echo "       market to pull"
  echo "       options: um cm spot"
  echo "   INTERVAL"
  echo "       kline interval"
  echo "       options: 12h 15m 1d 1h 1m 1mo 1w 2h 30m 3d 3m 4h 5m 6h 8h"
  echo ""
  echo " ENV VARS:"
  echo ""
  echo "   OUTDIR"
  echo "       output directory for the csvs"
  echo "       default: current directory"
  echo "   SYMBOLS"
  echo "       symbols to fetch zips for"
  echo "       default: fetched from exchange based on market"
  echo "   QUOTE"
  echo "       skip symbols that don't have this as their quoted currency"
  echo "       default: none"
  echo "   YEARS"
  echo "       years to fetch"
  echo "       default: (2017 2018 2019 2020 2021 2022)"
  echo "   MONTHS"
  echo "       months to fetch"
  echo "       default: (01 02 03 04 05 06 07 08 09 10 11 12)"
  echo "   DAYS"
  echo "       days to fetch"
  echo "       default: (01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16"
  echo "                   17 18 19 20 21 22 23 24 25 26 27 28 29 30 31)"
  echo "   SWORKERS"
  echo "       number of symbols to fetch concurrently"
  echo "       default: half available cores"
  echo "   ZWORKERS"
  echo "       number of zips to fetch concurrently (per symbol)"
  echo "       default: half available cores"
  echo "----------------------------------------------------------------"
  exit 0
fi

aggregation=$1
if [ $aggregation != "monthly" ] && [ $aggregation != "daily" ]; then
  echo >&2 "aggregation must be monthly or daily"
  exit 1
fi

market=$2
if [ "$market" = "spot" ]; then
  base_url="https://data.binance.vision/data/spot/$aggregation/klines"
elif [ "$market" = "cm" ] || [ "$market" == "um" ]; then
  base_url="https://data.binance.vision/data/futures/$market/$aggregation/klines"
else
  echo >&2 "market must be spot, cm or um"
  exit 1
fi

interval=$3
intervals="12h 15m 1d 1h 1m 1mo 1w 2h 30m 3d 3m 4h 5m 6h 8h"
if ! [[ $intervals =~ (^|[[:space:]])$interval($|[[:space:]]) ]]; then
  echo >&2 "interval must be in {${intervals[@]}}"
  exit 1
fi

corecount=$(grep -c '^processor' /proc/cpuinfo)

if ! [[ -z "$OUTDIR" ]]; then
  cd "$OUTDIR"
fi
if [[ -z "$YEARS" ]]; then
  YEARS=("2017" "2018" "2019" "2020" "2021" "2022")
fi
if [[ -z "$MONTHS" ]]; then
  MONTHS=("01" "02" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12")
fi
if [[ -z "$DAYS" ]]; then
  DAYS=("01" "02" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31")
fi
if [[ -z "$SWORKERS" ]]; then
  SWORKERS=$((($corecount + 1) / 2))
fi
if [[ -z "$ZWORKERS" ]]; then
  ZWORKERS=$((($corecount + 1) / 2))
fi
if [[ -z "$SYMBOLS" ]]; then
  if [ $market = "spot" ]; then
    SYMBOLS=$(curl -s -H 'Content-Type: application/json' https://api.binance.com/api/v1/exchangeInfo | jq -r '.symbols | sort_by(.symbol) | .[] | .symbol')
  else
    SYMBOLS=$(curl -s -H 'Content-Type: application/json' https://fapi.binance.com/fapi/v1/exchangeInfo | jq -r '.symbols | sort_by(.symbol) | .[] | .symbol')
  fi
fi

sc=$(((${#YEARS[@]} * ${#MONTHS[@]} * ${#DAYS[@]} + 1) / $ZWORKERS))

echo "--------------------------"
echo "        bzpuller"
echo "--------------------------"
echo "aggregation: $aggregation"
echo "market: $market"
echo "interval: $interval"
echo "out dir: $OUTDIR"
echo "symbol workers: $SWORKERS"
echo "zip workers: $ZWORKERS"
echo "n symbols: ${#SYMBOLS[@]}"
echo "--------------------------"

download_url() {
  url=$1
  filename="$(basename -- $url)"

  if [ -e "$filename" ]; then
    if [ ! -e "$filename.CHECKSUM" ]; then
      wget "$url.CHECKSUM" >/dev/null 2>/dev/null
    fi
    if sha256sum -c "$filename.CHECKSUM" >/dev/null 2>/dev/null; then
      echo "already validated: $filename"
      return
    else
      rm -rf "$filename" "$filename.CHECKSUM" >/dev/null 2>/dev/null
    fi
  fi

  while :; do
    wget "$url" >/dev/null 2>/dev/null
    if [ -e "$filename" ]; then
      wget "$url.CHECKSUM" >/dev/null 2>/dev/null
      if sha256sum -c "$filename.CHECKSUM" >/dev/null 2>/dev/null; then
        echo "validated: $filename"
        return
      else
        echo "CHECKSUM FAILED FOR $url"
        rm -rf "$filename" "$filename.CHECKSUM" >/dev/null 2>/dev/null
      fi
    else
      break
    fi
  done
}

process_zips() {
  arr=("$@")
  for url in ${arr[@]}; do
    download_url "$url"
  done
}

process_symbol() {
  zip_pids=()
  zip_list=()
  symbol=$1
  if [ $aggregation = "daily" ]; then
    for year in ${YEARS[@]}; do
      for month in ${MONTHS[@]}; do
        for day in ${DAYS[@]}; do
          filename=$symbol-$interval-$year-$month-$day.zip
          zip_list[${#zip_list[@]}]="$base_url/$symbol/$interval/$filename"
          if [ ${#zip_list[@]} -eq $sc ]; then
            process_zips "${zip_list[@]}" &
            zip_pids[${#zip_pids[@]}]="$!"
            if [ $ZWORKERS -eq -1 ]; then
              continue
            else
              while [ ${#zip_pids[@]} -eq $ZWORKERS ]; do
                running_pids=()
                for pid in ${zip_pids[@]}; do
                  if ps -p $pid >/dev/null 2>/dev/null; then
                    running_pids[${#running_pids[@]}]=$pid
                  fi
                done
                if ! [ ${#zip_pids[@]} -eq ${#running_pids[@]} ]; then
                  zip_pids=("${running_pids[@]}")
                else
                  sleep 5
                fi
              done
            fi
            zip_list=()
          fi
        done
      done
    done
  else
    for year in ${YEARS[@]}; do
      for month in ${MONTHS[@]}; do
        filename=$symbol-$interval-$year-$month.zip
        zip_list[${#zip_list[@]}]="$base_url/$symbol/$interval/$filename"
        if [ ${#zip_list[@]} -eq $sc ]; then
          process_zips "${zip_list[@]}" &
          zip_pids[${#zip_pids[@]}]="$!"
          if [ $ZWORKERS -eq -1 ]; then
            continue
          else
            while [ ${#zip_pids[@]} -eq $ZWORKERS ]; do
              running_pids=()
              for pid in ${zip_pids[@]}; do
                if ps -p $pid >/dev/null 2>/dev/null; then
                  running_pids[${#running_pids[@]}]=$pid
                fi
              done
              if ! [ ${#zip_pids[@]} -eq ${#running_pids[@]} ]; then
                zip_pids=("${running_pids[@]}")
              else
                sleep 5
              fi
            done
          fi
          zip_list=()
        fi
      done
    done
  fi

  if [ ${#zip_list[@]} -gt 0 ]; then
    process_zips "${zip_list[@]}"
    zip_list=()
  fi

  wait

}

symbol_pids=()

for symbol in ${SYMBOLS[@]}; do
  if ! [[ -z "$SYMBOL" ]]; then
      if ! [[ "$symbol" =~ ^[0-9A-Z]+$QUOTE$ ]]; then
          continue
      fi
  fi
  process_symbol "$symbol" &
  symbol_pids[${#symbol_pids[@]}]="$!"
  if [ $SWORKERS -eq -1 ]; then
    continue
  else
    while [ ${#symbol_pids[@]} -eq $SWORKERS ]; do
      running_pids=()
      for pid in ${symbol_pids[@]}; do
        if ps -p $pid >/dev/null 2>/dev/null; then
          running_pids[${#running_pids[@]}]=$pid
        fi
      done
      if ! [ ${#symbol_pids[@]} -eq ${#running_pids[@]} ]; then
        symbol_pids=("${running_pids[@]}")
      else
        sleep 5
      fi
    done
  fi
done

wait

exit 0
