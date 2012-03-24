#!/bin/bash

first () {
  for x in "$@"; do
    if [ -n "$x" ]; then
      echo "$x";
      break
    fi
  done
}

set_default () {
  varname="$1"
  shift
  val="$(first "$@")"
  eval "
if [ -z \$$varname ]; then
  $varname=$val
fi
"
}

# Set this according to preference
set_default VIDEO_DIR "$(xdg-user-dir VIDEOS)" "$HOME/Videos"

echo "Downloading new subscribed videos for $YOUTUBE_USER into $VIDEO_DIR"

cd "$VIDEO_DIR"

QUEUE_DIR=$VIDEO_DIR/.queue
COMPLETED_DIR=$VIDEO_DIR/.done

mkdir -p $QUEUE_DIR $COMPLETED_DIR

# http://en.wikipedia.org/wiki/YouTube#Quality_and_codecs
DOWNLOAD_OPTS="--ignore-errors --continue --output=%(upload_date)s-%(stitle)s.%(ext)s --format=18"
DOWNLOAD_OPTS_ANY_FORMAT="--ignore-errors --continue --output=%(upload_date)s-%(stitle)s.%(ext)s"

get_title () {
  if [ -s $QUEUE_DIR/$1 ]; then
    echo $(cat $QUEUE_DIR/$1);
  elif [ -s $COMPLETED_DIR/$1 ]; then
    echo $(cat $COMPLETED_DIR/$1);
  else
    echo $(youtube-dl $DOWNLOAD_OPTS_ANY_FORMAT --get-title -- "$1")
  fi
}

describe_hash () {
  echo "$1: $(get_title $1)"
}

hash_done () {
  test -f "$COMPLETED_DIR/$1"
}

hash_queued () {
  test -f "$QUEUE_DIR/$1"
}

enqueue_hash () {
  if hash_done $1; then
    return 1
  elif hash_queued $1; then
    return 0
  else
    get_title $1 > $QUEUE_DIR/$1
  fi
}

dequeue_hash () {
  rm -f $QUEUE_DIR/$1
}

mark_hash_done () {
  get_title $1 > $COMPLETED_DIR/$1
  dequeue_hash $1
}

cleanup_done_hashes () {
  # Delete all but the 100 newest done files
  ls $DONE_DIR | head -n-100 | while read old_hash; do
    rm -f $DONE_DIR/old_hash
  done
}

get_queued_hashes () {
  ls -tr1 $QUEUE_DIR
}

get_subscription_hashes () {
  wget -q -O- 'http://gdata.youtube.com/feeds/api/users/'"$YOUTUBE_USER"'/newsubscriptionvideos?prettyprint=true&fields=entry%28link[@rel=%27alternate%27]%28@href%29%29' | perl -lane 'print "$1" if m{\Qhttp://www.youtube.com/watch?v=\E([^&]+)}' | tac
}

enqueue_new_hashes () {
  get_subscription_hashes | while read hash; do
    if hash_done $hash; then
      true;
      # echo "Skipping already downloaded video $(describe_hash $hash)"
    elif hash_queued $hash; then
      echo "Already enqueued video $(describe_hash $hash)"
    else
      enqueue_hash $hash
      echo "Enqueuing new video $(describe_hash $hash)"
    fi
  done
}

dl_hash () {
  desc="$(describe_hash $1)"
  echo "Downloading video $desc"
  if youtube-dl $DOWNLOAD_OPTS -- $1; then
    mark_hash_done $1
    echo "Download completed: $desc"
  else
    retcode=$?
    echo "ERROR: Download failed: $desc"
    return $retcode
  fi
}

main () {
  echo "Checking Youtube for new videos..."
  enqueue_new_hashes
  queue_size=$(get_queued_hashes | wc -l)
  if [ $queue_size -gt 0 ]; then
    echo "Downloading $queue_size videos:"

    get_queued_hashes | while read hash; do
      dl_hash $hash
    done
    fail_count=$(get_queued_hashes | wc -l)
    if test $fail_count -eq 0 ; then
      echo "All available videos downloaded successfully."
    else
      echo -e "\nERROR: $fail_count video(s) failed to download:"
      get_queued_hashes | while read hash; do
        echo "  $(describe_hash $hash)"
      done
      echo -e "\nTry again later."
      return 1
    fi
  else
    echo "All available videos are already downloaded. No new videos available."
  fi
  cleanup_done_hashes
}

main
