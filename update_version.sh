#!/bin/bash

# Usage: ./update_version.sh 0.2.0

NEW_VERSION="$1"

if [ -z "$NEW_VERSION" ]; then
  echo "Usage: $0 <new_version>"
  exit 1
fi

# Update VERSION= inside main script
sed -i "s/^VERSION=\".*\"/VERSION=\"$NEW_VERSION\"/" create-lxc.sh

# Commit and tag
git add create-lxc.sh
git commit -m "Bump version to $NEW_VERSION"
git tag "v$NEW_VERSION"
git push
git push --tags

echo "Version updated to $NEW_VERSION and pushed!"

