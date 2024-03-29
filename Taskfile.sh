#!/bin/bash

DEBUG=false
AUTHED=false
QUIET=false
DRY=false

TODAY="$(date +"%Y/%m/%d")"
HOST="$(cat .settings.json | jq -r .host)"
MATCH="$(cat .settings.json | jq -r .match)"
PLEX="$(cat .settings.json | jq -r .plex.host)"
TOKEN="$(cat .settings.json | jq -r .plex.token)"
SERIES="$(cat .settings.json | jq -r .plex.series)"
SECTION="$(cat .settings.json | jq -r .plex.section)"
TITLEA="$(cat .settings.json | jq -r .show.titlea)"
TITLEB="$(cat .settings.json | jq -r .show.titleb)"
TITLEC="$(cat .settings.json | jq -r .show.titlec)"

[[ $* == *--quiet* ]] && QUIET=true
[[ $* == *--dry-run* ]] && DRY=true

function install {
    # apt install git golang jq curl ffmpeg moreutils
	go get github.com/ericchiang/pup
    npm install github:zinefer/parse-hls#dist
}

function auth {
    ($AUTHED) && return
    local nonce username password

    nonce="$(curl -s "${HOST}/my-account/" | pup '[name="woocommerce-login-nonce"]' attr{value})"

    ($DEBUG) && >&2 echo "nonce=$nonce"

    username="$(cat .settings.json | jq -r .username)"
    password="$(cat .settings.json | jq -r .password)"

    curl -s -X POST --cookie-jar ./cookies \
        -F "username=$username" \
        -F "password=$password" \
        -F "woocommerce-login-nonce=$nonce" \
        -F 'login=log in' \
        "${HOST}/my-account/"

    AUTHED=true
}

function list {
    local page
    page="${1:=1}"

    auth
    
    curl -s --location-trusted --cookie ./cookies \
            ${HOST}/category/rmg-plus/page/$page |
        pup '.vlog-content .entry-title a' attr{href} |
        uniq |
        jq --raw-input --slurp 'split("\n") | map(select(. != "")) | unique | sort | reverse'
}

function new {
    local arr out item foundlastseen page

    foundlastseen=false
    page=0
    out=""

    while [ "$foundlastseen" == false ] && [ "$page" -lt 15 ]; do
        page=$((page+1))

        ($DEBUG) && >&2 echo "Getting page $page"
    
        arr=$(list $page | jq -r '.[]')

        IFS=$'\n'
        for item in $arr
        do
            if ! grep -Fq "$item" .seen
            then
                out="$out$item\n"
            else
                foundlastseen=true
                ($DEBUG) && >&2 echo "Already downloaded $item"
            fi
        done
    done

    echo -e "$out" | jq --raw-input --slurp 'split("\n") | map(select(. != "")) | sort | reverse'
}

function download-new {
    local outpath first arr item
    outpath="${1:?'Usage - download <OUTPATH>'}"
    first=true

    arr=$(new | jq -r 'reverse | .[]')

    IFS=$'\n'
    for item in $arr
    do
        [ $first = false ] && echo '---------------------------------------'

        download "$item" "$outpath"

        first=false
    done

    # If we come out of the loop with first=true we downloaded nothing
    ($first) && echo "Nothing new to download"
    (! $first) && plex-scan
}

function download {
    local baseurl outpath html hlsurl title plot date year subtitle file plotFile
    baseurl="${1:?'Usage - download <URL> <OUTPATH>'}"
    outpath="${2:?'Usage - download <URL> <OUTPATH>'}"

    echo "Attempting to download stream at $baseurl"
    echo

    auth

    html="$(curl -s --cookie ./cookies $baseurl)"

    hlsurl=$(echo "$html" |
        sed -n -r "$MATCH")

    title="$(echo "$html" |
        pup '.fl-node-5a120d24a7dcb .fl-heading-text' text{})"

    plot="$(echo "$html" |
        pup '.fl-node-5a14e2cf5281e div p' text{})"

    # Get date from baseurl
    date="$(echo $baseurl | awk -F'/' '{print $4 "-" $5 "-" $6}')"
    year="${date:0:4}"

    subtitle="${title% *}"

    case "$subtitle" in
        $TITLEA)
            date="${date}_1"
        ;;
        $TITLEB | $TITLEC)
            date="${date}_2"
        ;;
        *)
            date="${date}_3"
        ;;
    esac

    # A Series Title - 2021-03-26_1 - An episode
    file="$SERIES - $date - $subtitle.mp4"
    plotFile="${file%%.*}.summary"
    outpath="$outpath/$SERIES/Season $year"

    echo "hlsurl=$hlsurl"
    echo "title=$title"
    echo "plot=$plot"
    echo "$outpath/$file"
    echo

    ($DRY) && return

    mkdir -p "$outpath"

    # Save plot to metadata file
    echo "$plot" > "$outpath/$plotFile"

    # ffmpeg will check all variants inside the hls file and exit if any
    # of them 404 even if we don't want them so we will parse the hls file ourselves
    # and pass the m3u8 url to ffmpeg directly
    m3u8path="$(curl -s --header "Referer: ${HOST}/" $hlsurl | grep '.m3u8$' | tail -n 2 | head -n 1)"
    m3u8url="${hlsurl%/*}/$m3u8path"

    echo "m3u8url=$m3u8url"

    # Give less feedback when not interactive
    [[ -v PS1 ]] && delay="0.5" || delay="1200"

    ffmpeg -y -v quiet -stats \
        -headers "Referer: ${HOST}/" \
        -i "$m3u8url" \
        "$outpath/$file"

    if [ $? -eq 0 ]; then
        # Save the url to the database to prevent duplicate downloads
        echo -e "$baseurl" >> .seen
    else
        echo "FFMPEG FAILURE"
        rm "$outpath/$plotFile"
    fi
}

function plex-scan {
    curl -s "$PLEX/library/sections/$SECTION/refresh?X-Plex-Token=$TOKEN"
}

function help {
    echo "$0 <task> <args>"
    echo "Tasks:"
    compgen -A function | cat -n
}

if [ $QUIET = false ]; then
    TIMEFORMAT="Task completed in %3lR"
    time ${@:-help}
else
    ${@:-help} | ts '[%b %d %H:%M:%S]'
fi