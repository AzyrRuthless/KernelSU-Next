#!/bin/sh
set -eu

GKI_ROOT=$(pwd)
OWNER="AzyrRuthless"
REPO="$OWNER"

display_usage() {
    echo "Usage: $0 [--cleanup | <commit-or-tag>]"
    echo "  --cleanup:              Cleans up previous modifications made by the script."
    echo "  <commit-or-tag>:        Sets up or updates the KernelSU-Next to specified tag or commit."
    echo "  -h, --help:             Displays this usage information."
    echo "  (no args):              Sets up or updates the KernelSU-Next environment to the latest tagged version."
}

initialize_variables() {
    if test -d "$GKI_ROOT/common/drivers"; then
         DRIVER_DIR="$GKI_ROOT/common/drivers"
    elif test -d "$GKI_ROOT/drivers"; then
         DRIVER_DIR="$GKI_ROOT/drivers"
    else
         echo '[ERROR] "drivers/" directory not found.'
         exit 127
    fi

    DRIVER_MAKEFILE=$DRIVER_DIR/Makefile
    DRIVER_KCONFIG=$DRIVER_DIR/Kconfig
}

# Reverts modifications made by this script
perform_cleanup() {
    echo "[+] Cleaning up..."
    [ -L "$DRIVER_DIR/kernelsu" ] && rm "$DRIVER_DIR/kernelsu" && echo "[-] Symlink removed."
    grep -q "kernelsu" "$DRIVER_MAKEFILE" && sed -i '/kernelsu/d' "$DRIVER_MAKEFILE" && echo "[-] Makefile reverted."
    grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG" && sed -i '/drivers\/kernelsu\/Kconfig/d' "$DRIVER_KCONFIG" && echo "[-] Kconfig reverted."
    if [ -d "$GKI_ROOT/$REPO" ]; then
        rm -rf "$GKI_ROOT/$REPO" && echo "[-] $REPO directory deleted."
    fi
}

# Sets up or update KernelSU-Next environment
setup_kernelsu() {
    echo "[+] Setting up $REPO..."
    
    # 1. Ensure the repository is cloned
    if [ ! -d "$GKI_ROOT/$REPO" ]; then
        git clone "https://github.com/$OWNER/$REPO" "$GKI_ROOT/$REPO"
        echo "[+] Repository cloned."
    fi

    cd "$GKI_ROOT/$REPO"
    
    # 2. Update metadata to ensure 'legacy' and other refs are visible
    git stash >/dev/null 2>&1 && echo "[-] Stashed local changes."
    git fetch origin --prune --tags >/dev/null 2>&1

    # 3. Determine the target reference (Branch, Tag, or SHA)
    if [ -z "${1-}" ]; then
        # Check for tags first, fallback to the remote default branch
        TARGET_REF=$(git describe --abbrev=0 --tags 2>/dev/null || \
                     git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
        echo "[-] No version specified, using default: $TARGET_REF"
    else
        TARGET_REF="$1"
    fi

    # 4. Robust Checkout Strategy
    echo "[-] Attempting to checkout: $TARGET_REF"
    # Try direct checkout (works for tags/SHAs/existing local branches)
    if git checkout "$TARGET_REF" >/dev/null 2>&1; then
        echo "[+] Checked out $TARGET_REF."
    # Try tracking a remote branch (essential for fresh clones)
    elif git checkout -b "$TARGET_REF" "origin/$TARGET_REF" >/dev/null 2>&1; then
        echo "[+] Tracked remote branch: $TARGET_REF."
    else
        echo "[!] Error: Reference '$TARGET_REF' not found."
        exit 1 # Fail-fast to prevent Kconfig errors later
    fi

    # 5. Symlink creation
    cd "$DRIVER_DIR"
    # Verify the source 'kernel' directory exists in the checkout
    if [ ! -d "$GKI_ROOT/$REPO/kernel" ]; then
        echo "[!] Error: 'kernel/' directory missing in $TARGET_REF checkout!"
        exit 1
    fi
    
    ln -sf "$(realpath --relative-to="$DRIVER_DIR" "$GKI_ROOT/$REPO/kernel")" "kernelsu"
    echo "[+] Symlink created."

    # 6. Idempotent Makefile modification
    if ! grep -q "kernelsu" "$DRIVER_MAKEFILE"; then
        printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_MAKEFILE"
        echo "[+] Modified Makefile."
    fi

    # 7. Idempotent Kconfig modification
    if ! grep -q "drivers/kernelsu/Kconfig" "$DRIVER_KCONFIG"; then
        # Injects before the first endmenu encountered
        sed -i "0,/endmenu/s/endmenu/source \"drivers\/kernelsu\/Kconfig\"\nendmenu/" "$DRIVER_KCONFIG"
        echo "[+] Modified Kconfig."
    fi

    echo '[+] Done.'
}

# Process command-line arguments
if [ "$#" -eq 0 ]; then
    initialize_variables
    setup_kernelsu
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    display_usage
elif [ "$1" = "--cleanup" ]; then
    initialize_variables
    perform_cleanup
else
    initialize_variables
    setup_kernelsu "$@"
fi
