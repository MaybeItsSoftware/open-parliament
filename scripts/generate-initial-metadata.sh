#!/bin/bash
set -e

# Directories
METADATA_DIR="fastlane/metadata"
ANDROID_METADATA_DIR="fastlane/metadata/android"

echo "Creating iOS metadata directories..."
mkdir -p "$METADATA_DIR/en-GB"

echo "Writing iOS metadata templates..."
echo "2026 Maybe Its Software" > "$METADATA_DIR/copyright.txt"
echo "News" > "$METADATA_DIR/primary_category.txt"
echo "Reference" > "$METADATA_DIR/secondary_category.txt"

echo "Open Parliament" > "$METADATA_DIR/en-GB/name.txt"
echo "UK Parliament debates verbatim" > "$METADATA_DIR/en-GB/subtitle.txt"
cat << 'EOF' > "$METADATA_DIR/en-GB/description.txt"
Open Parliament lets you read UK Parliamentary debates verbatim from Hansard.

Features:
- Read debates from the House of Commons and House of Lords.
- Full offline support: search and read cached debates without an internet connection.
- Track bills, member profiles, and voting records.
- View live parliament broadcast schedules.
EOF
echo "parliament,hansard,uk,politics,debates,commons,lords,government,bills,voting,politicians" > "$METADATA_DIR/en-GB/keywords.txt"
echo "https://maybeitssoftware.co.uk/privacy" > "$METADATA_DIR/en-GB/privacy_url.txt"
echo "https://maybeitssoftware.co.uk/support" > "$METADATA_DIR/en-GB/support_url.txt"
echo "https://maybeitssoftware.co.uk/open-parliament" > "$METADATA_DIR/en-GB/marketing_url.txt"
echo "Read verbatim UK Parliamentary debates offline." > "$METADATA_DIR/en-GB/promotional_text.txt"
echo "Initial release of Open Parliament." > "$METADATA_DIR/en-GB/release_notes.txt"

echo "Creating Android metadata directories..."
mkdir -p "$ANDROID_METADATA_DIR/en-GB"

echo "Writing Android metadata templates..."
echo "Open Parliament" > "$ANDROID_METADATA_DIR/en-GB/title.txt"
echo "Read verbatim UK Parliamentary debates offline." > "$ANDROID_METADATA_DIR/en-GB/short_description.txt"
cat << 'EOF' > "$ANDROID_METADATA_DIR/en-GB/full_description.txt"
Open Parliament lets you read UK Parliamentary debates verbatim from Hansard.

Features:
- Read debates from the House of Commons and House of Lords.
- Full offline support: search and read cached debates without an internet connection.
- Track bills, member profiles, and voting records.
- View live parliament broadcast schedules.
EOF

echo "Done! Initial release metadata templates generated successfully."
