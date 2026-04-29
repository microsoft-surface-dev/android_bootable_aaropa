#!/bin/bash

# URLs for the GitHub release page and API
RELEASE_URL="https://github.com/Ananda-Aropa/aaropa_rootfs_installer_blissos/releases/latest"
API_URL="https://api.github.com/repos/Ananda-Aropa/aaropa_rootfs_installer_blissos/releases/latest"
VERSION_FILE="version.txt"

# Get the script's directory and change to it
SCRIPT_DIR=$(dirname "$0")
mkdir -p "$SCRIPT_DIR/../../prebuilts/aaropa"
cd "$SCRIPT_DIR/../../prebuilts/aaropa" || exit


# Function to get the latest tag from GitHub API
get_latest_version() {
  if command -v curl &>/dev/null; then
    curl -s "$API_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  elif command -v wget &>/dev/null; then
    wget -qO- "$API_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  fi
}

# Function to check version and optionally exit
check_version() {
  echo "Checking for the latest version..."
  LATEST_VERSION=$(get_latest_version)

  if [[ -z "$LATEST_VERSION" ]]; then
    echo "Warning: Could not determine the latest version from GitHub. Proceeding with download..."
    return 0
  fi

  if [[ -f "$VERSION_FILE" ]]; then
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    if [[ "$LATEST_VERSION" == "$LOCAL_VERSION" ]]; then
      echo "You already have the latest version ($LATEST_VERSION). Skipping download."
      exit 0
    fi
  fi

  echo "New version found: $LATEST_VERSION (Current: ${LOCAL_VERSION:-None})"
}

# Function to update the version file
update_version() {
  if [[ -n "$LATEST_VERSION" ]]; then
    echo "$LATEST_VERSION" >"$VERSION_FILE"
    echo "Updated $VERSION_FILE to $LATEST_VERSION."
  fi
}

# Function to remove existing files from the FILES list and directories
remove_existing_files() {
  # Remove files listed in the FILES array
  for FILE in "${FILES[@]}"; do
    if [[ -f "$FILE" ]]; then
      echo "Removing existing file: $FILE"
      rm -f "$FILE"*
    fi
  done

  # Remove initrd/initrd and iso/iso directories
  if [[ -d "initrd/initrd" ]]; then
    echo "Removing existing directory: initrd/initrd"
    rm -rf initrd/initrd
  fi

  if [[ -d "iso/iso" ]]; then
    echo "Removing existing directory: iso/iso"
    rm -rf iso/iso
  fi
}

# Function to download files using aria2c
download_with_aria2() {
  local file="$1"
  echo "Downloading $file using aria2c..."
  aria2c -x 16 -s 16 "$RELEASE_URL/download/$file"
}

# Function to download files using wget
download_with_wget() {
  local file="$1"
  echo "Downloading $file using wget..."
  wget "$RELEASE_URL/download/$file"
}

# Function to extract grub-rescue.iso to the iso/iso directory and delete the iso file
extract_grub_rescue_iso() {
  echo "Extracting grub-rescue.iso to iso/iso directory..."
  mkdir -p iso/iso
  # Extract the contents of the ISO into the "iso/iso" folder
  7z x grub-rescue.iso -oiso/iso
  # Delete the ISO after extracting
  rm grub-rescue.iso
}

# Function to move install.sfs to the iso/iso directory
move_install_sfs() {
  echo "Moving install.sfs to iso/iso directory..."
  mv install.sfs iso/iso/
}

# Function to move boot_hybrid.img to the iso directory
move_boot_hybrid() {
  echo "Moving boot_hybrid.img to iso directory..."
  mkdir -p iso
  mv boot_hybrid.img iso/
}

# Function to extract initrd_lib.tar.gz and move the content to the initrd folder
extract_initrd_lib() {
  echo "Extracting initrd_lib.tar.gz..."
  mkdir -p initrd
  tar -xzf initrd_lib.tar.gz
  mv initrd_lib initrd/initrd
  echo "Setting permissions for initrd/initrd..."
  chmod -R 755 initrd/initrd/*
  # Remove the extracted tar.gz file
  rm -f initrd_lib.tar.gz
}

# Function to display the help message
show_help() {
  cat <<EOF
Copyright (C) 2026 BlissLabs

Usage: ./download.sh [OPTION]

Options:
  --initrd-only         Download and extract only the initrd_lib.tar.gz file.
  --with-newinstaller   Download and extract excluding the install.sfs file.
  --help                Show this help message and exit.
EOF
}

# Handle the command line argument using a case statement
case "$1" in
--help) show_help && exit 0 ;;
--initrd-only) export INITRD_ONLY=true ;;
--with-newinstaller) export WITH_NEWINSTALLER=true ;;
esac

# Files to download
FILES=(
  "initrd_lib.tar.gz"
)

if [ -z "$INITRD_ONLY" ]; then
  FILES+=(
    "grub-rescue.iso"
    "boot_hybrid.img"

  )
fi

if [ -z "$WITH_NEWINSTALLER" ]; then
  FILES+=(
    "install.sfs"
  )
fi

# Check the version first
check_version

# Remove existing files before starting the download
remove_existing_files

# Check if aria2c is installed
if command -v aria2c &>/dev/null; then
  echo "aria2c found, using aria2c for download."
  for FILE in "${FILES[@]}"; do
    download_with_aria2 "$FILE"
  done
else
  echo "aria2c not found, falling back to wget."
  for FILE in "${FILES[@]}"; do
    download_with_wget "$FILE"
  done
fi

# Process the downloaded files
if [ -z "$INITRD_ONLY" ]; then
  extract_grub_rescue_iso
  move_boot_hybrid
fi
if [ -z "$WITH_NEWINSTALLER" ]; then
  move_install_sfs
fi
extract_initrd_lib

# Save the new version
update_version

# Create Android.bp files
echo "Creating Android.bp for initrd..."
cat <<EOF > initrd/Android.bp
aaropa_initrd {
    name: "initrd.img",
    os_title: "BlissOS",
    ver: "15",
}
EOF

echo "Creating Android.bp for iso..."
cat <<EOF > iso/Android.bp
aaropa_iso {
    name: "aaropa_iso_target",
    boot_hybrid: "boot_hybrid.img",
    os_title: "BlissOS",
    disklabel: "BOS15",
EOF

if [ -n "$WITH_NEWINSTALLER" ]; then
cat <<EOF >> iso/Android.bp
    use_newinstaller: true,
EOF
fi

cat <<EOF >> iso/Android.bp
}
EOF

echo "Script execution complete!"

exit 0
