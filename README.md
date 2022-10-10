# bzpuller.sh

This script concurrently downloads and validates checksums of [Binance kline zips](https://data.binance.vision/?prefix=data/).

I see two main advantages the zips have over Binance's api:
1. No ratelimits (other than the normal DDoS protection I assume).
2. Pair data of Spot/Futures symbols that are no longer traded on the exchanged (e.g. Luna).

Unfortunately, it's not all sunshine and roses as the zips are not entirely clean:
- Some have headers (`open_time,open,high,low,close,volume,close_time,quote_volume,count,taker_buy_volume,taker_buy_quote_volume,ignore`), some don't.
- In one case, a single timestamp for `BZRXUSDT` was duplicated 13 times (timestamp `2021-03-22 11:57:00` on the Spot market to be precise).

I think there are data discrepencies between the API data and zips (even between the daily and monthy). 
If someone can disprove this, please let me know!

**NB: Be careful about**
1. Where you run this script (or set `OUTDIR` to) - it will fill that directory with zips and checksums to the point there will be too many files to `rm` using a wildcard and you'll either have to delete the entire directory or delete smaller wildcard batches of them until you can fit the rest into a single wildcard (this doesn't sound fun...and it's less fun than it sounds!).
2. The values of `SWORKERS` and `ZWORKERS`. The maximum number of subprocesses possibly running at once is $3 + SWORKERS * ZWORKERS$.

## Usage

``` sh
$ ./bzpuller.sh
----------------------------------------------------------------
                       BINANCE ZIP PULLER
----------------------------------------------------------------
 USAGE:
           bzpuller.sh <AGGREGATION> <MARKET> <INTERVAL>

 ARGUMENTS:

   AGGREGATION
       the level of aggregation per zip
       options: monthly daily
   MARKET
       market to pull
       options: um cm spot
   INTERVAL
       kline interval
       options: 12h 15m 1d 1h 1m 1mo 1w 2h 30m 3d 3m 4h 5m 6h 8h

 ENV VARS:

   OUTDIR
       output directory for the csvs
       default: current directory
   SYMBOLS
       symbols to fetch zips for
       default: fetched from exchange based on market
   QUOTE
       skip symbols that don't have this as their quoted currency
       default: none
   YEARS
       years to fetch
       default: (2017 2018 2019 2020 2021 2022)
   MONTHS
       months to fetch
       default: (01 02 03 04 05 06 07 08 09 10 11 12)
   DAYS
       days to fetch
       default: (01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16
                   17 18 19 20 21 22 23 24 25 26 27 28 29 30 31)
   SWORKERS
       number of symbols to fetch concurrently
       default: half available cores
   ZWORKERS
       number of zips to fetch concurrently (per symbol)
       default: half available cores
----------------------------------------------------------------
```

## TODO

Add the other markets:
- [ ] aggTrades
- [ ] indexPriceKlines
- [ ] markPriceKlines
- [ ] premiumIndexKlines
- [ ] trades

Misc:
- [ ] Reduce code redundancy

## Disclaimer

This is my first substantial Bash script.
I accept my divide-&-conquer implementation may be a bit convoluted, but it serves its current purpose.
Specifically, it allows new processes to be spawned right after a process finishes (rather than using a blanket `wait`
to wait for all processes before launching the next batch or just guess with `wait <pid>` and potentially be idle a lot longer than needs be).
Hopefully a glance of the code will help with making sense of this.

