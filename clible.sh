#!/bin/zsh

# Enable debugging to see the flow of execution
#set -x

# Set the ESV API key
ESV_API_KEY="e6110be1d9704aa2d302b074c8d7d47e2d32be84"

# Define an array of books to iterate through
books=("Genesis" "Exodus" "Leviticus" "Numbers" "Deuteronomy" "Joshua" "Judges" "Ruth" "1 Samuel" "2 Samuel" "1 Kings" "2 Kings" "1 Chronicles" "2 Chronicles" "Ezra" "Nehemiah" "Esther" "Job" "Psalms" "Proverbs" "Ecclesiastes" "Song of Solomon" "Isaiah" "Jeremiah" "Lamentations" "Ezekiel" "Daniel" "Hosea" "Joel" "Amos" "Obadiah" "Jonah" "Micah" "Nahum" "Habakkuk" "Zephaniah" "Haggai" "Zechariah" "Malachi" "Matthew" "Mark" "Luke" "John" "Acts" "Romans" "1 Corinthians" "2 Corinthians" "Galatians" "Ephesians" "Philippians" "Colossians" "1 Thessalonians" "2 Thessalonians" "1 Timothy" "2 Timothy" "Titus" "Philemon" "Hebrews" "James" "1 Peter" "2 Peter" "1 John" "2 John" "3 John" "Jude" "Revelation")

# File to store the final chapter and verse data
BIBLE_DB_FILE=".bible_db"
LOG_FILE="script_errors.log"

# Function to log errors
log_error() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
}

# Function to display help information
display_help() {
  echo "Usage: $(basename "$0") [OPTION]"
  echo ""
  echo "Options:"
  echo "  -i       Initialize the local database with final chapters and verses for each book."
  echo "  -h       Display this help information."
  echo ""
  echo "Without any options, the script fetches a verse matching the current hour and minute."
}

# Function to initialize the local database with the final chapters and verses of each book
initialize_local_db() {
  # Safely clear the file by truncating or creating a new one
  echo "Initializing local database and clearing previous entries (if any)."
  echo "" > "$BIBLE_DB_FILE"

  for book in "${books[@]}"; do
    echo "Processing book: $book"

    # Get the final chapter by querying chapter 99 (an obviously invalid chapter)
    response=$(curl -s -H "Authorization: Token $ESV_API_KEY" "https://api.esv.org/v3/passage/text/?q=${book}%2099")
    if [[ $? -ne 0 ]]; then
      log_error "Failed to query final chapter for $book."
      continue
    fi

    # Debugging: Show raw response
    echo "Response for final chapter query of $book: $response"

    # Remove control characters to prevent jq parsing issues
    response=$(echo "$response" | tr -d '\000-\037')

    # Extract the final chapter
    encoded_chapter_end=$(echo "$response" | jq -r '.passage_meta[0].chapter_end[1]')
    final_chapter=$(echo "$encoded_chapter_end" | rev | cut -c 4-6 | rev | sed 's/^0*//')

    if [[ -z "$final_chapter" || "$final_chapter" == "null" ]]; then
      log_error "Failed to retrieve final chapter for $book."
      continue
    fi

    echo "Final chapter for $book: $final_chapter"

    for chapter in $(seq 1 $final_chapter); do
      echo "Processing chapter: $book $chapter"

      response=$(curl -s -H "Authorization: Token $ESV_API_KEY" "https://api.esv.org/v3/passage/text/?q=${book}%20${chapter}")
      if [[ $? -ne 0 ]]; then
        log_error "Failed to query final verse for $book chapter $chapter."
        continue
      fi

      # Debugging: Show raw response
      echo "Response for final verse query of $book chapter $chapter: $response"

      # Remove control characters to prevent jq parsing issues
      response=$(echo "$response" | tr -d '\000-\037')

      # Get the final verse number from the parsed field by working right to left
      encoded_final_verse=$(echo "$response" | jq -r '.parsed[0][1]')
      final_verse=$(echo "$encoded_final_verse" | rev | cut -c 1-3 | rev | sed 's/^0*//')

      if [[ -z "$final_verse" || "$final_verse" == "null" ]]; then
        log_error "Failed to retrieve final verse for $book chapter $chapter."
        continue
      fi

      echo "Final verse for $book chapter $chapter: $final_verse"
      echo "${book} ${chapter} ${final_verse}" >> "$BIBLE_DB_FILE"
      sleep 4
    done
  done

  echo "Local database initialized and saved to $BIBLE_DB_FILE."
}

# Function to fetch a verse with validation from the local database
fetch_verse() {
  if [[ ! -f "$BIBLE_DB_FILE" ]]; then
    log_error "Local database file '$BIBLE_DB_FILE' not found. Please initialize the database using the -i option."
    echo "Error: Local database file not found. Please initialize the database using the -i option."
    return 1
  fi

  # Get the current time
  hour=$(date +"%H")
  minute=$(date +"%M")
  hour_12=$(( 10#$hour % 12 == 0 ? 12 : 10#$hour % 12 ))
  hour_24=$hour

  bible_data=()
  while IFS= read -r line; do
    bible_data+=("$line")
  done < "$BIBLE_DB_FILE"

  valid_verses=()
  for entry in "${bible_data[@]}"; do
    IFS=' ' read -r book chapter final_verse <<< "$entry"

    if (( chapter == hour_12 || chapter == hour_24 )) && (( minute <= final_verse )); then
      valid_verses+=("$book $chapter:$minute")
    fi
  done

  if [[ ${#valid_verses[@]} -eq 0 ]]; then
    log_error "No valid verses found for the current time (Hour=$hour, Minute=$minute)."
    echo "No valid verses found for the current time."
    return 1
  fi

  random_index=$((RANDOM % ${#valid_verses[@]}))
  verse_reference="${valid_verses[$random_index]}"

  response=$(curl -s -H "Authorization: Token $ESV_API_KEY" "https://api.esv.org/v3/passage/text/?q=${verse_reference// /%20}")
  if [[ $? -ne 0 ]]; then
    log_error "Failed to query verse: $verse_reference."
    echo "Error occurred while querying for verse: $verse_reference."
    return 1
  fi

  response=$(echo "$response" | tr -d '\000-\037')
  verse_reference_pattern=$(echo "$verse_reference" | sed 's/:/\\:/g')
  verse_text=$(echo "$response" | jq -r '.passages[0]' | sed "s/^$verse_reference_pattern *//" | sed 's/\[[0-9]\+\]//g' | sed 's/ *(ESV)//g' | sed 's/ *(.*)//g' | sed 's/^ *//g' | sed 's/ *$//g')

  if [[ -n "$verse_text" && "$verse_text" != "null" ]]; then
    local top_border="╔══════════════════════════════════════════════════════════════════════════════════════════╗"
    local bottom_border="╚══════════════════════════════════════════════════════════════════════════════════════════╝"
    local verse_reference_formatted="\e[1;37m${verse_reference}\e[0m"
    # Format the verse text by bolding specific terms
    local verse_text_formatted=$(echo "$verse_text" | sed -E 's/\b(God|Lord|Christ|Holy Spirit|Jesus|Father)\b/%B\1%b/g')

    # Print the top border
    print -P "$top_border"

    # Print the verse reference, calculating padding separately to account for escape sequences
    local plain_verse_reference="$verse_reference"  # The non-formatted text to calculate length
    local padding=$((88 - ${#plain_verse_reference}))
    printf "║ %s%*s ║\n" "$(print -P "$verse_reference_formatted")" "$padding" ""

    # Print the separator line
    print -P "║------------------------------------------------------------------------------------------║"

    # Print each line of the verse text with proper padding
    echo "$verse_text_formatted" | fold -s -w 88 | while read -r line; do
      local plain_line=$(print -P "$line" | sed 's/\x1b\[[0-9;]*m//g')  # Strip escape sequences for length calculation
      local line_padding=$((88 - ${#plain_line}))
      printf "║ %s%*s ║\n" "$(print -P "$line")" "$line_padding" ""
    done

    # Print the bottom border
    print -P "$bottom_border"

    return 0
  else
    log_error "Failed to retrieve valid verse text for $verse_reference."
    echo "Error: No valid verse text found for $verse_reference."
    return 1
  fi
}

# Main function to handle command-line arguments and call other functions
main() {
  case "$1" in
    -i) initialize_local_db ;;
    -h) display_help ;;
    *) fetch_verse ;;
  esac
}

main "$@"
