#!/usr/bin/env bash

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}
err() {
    echo -e "\e[1;41$*\e[0m"
}

# Environment Config
export TELEGRAM_TOKEN=6410284454:AAFHrE_XZtikh0v8L7IoDVr1RAMuno3LjeI
export TELEGRAM_CHAT=-1002088104319
export GIT_TOKEN=$GH_TOKEN
export BRANCH=master
export CCACHE=1

# Get home directory
HOME_DIR="$(pwd)"
install="$HOME_DIR/install"
src="$HOME_DIR/src"

# Telegram Setup
git clone --depth=1 https://github.com/elynord/Telegram Telegram

TELEGRAM="$HOME_DIR/Telegram/telegram"
chmod +x $HOME_DIR/Telegram/telegram
send_msg() {
    "${TELEGRAM}" -H -D \
        "$(
            for POST in "${@}"; do
                echo "${POST}"
            done
        )"
}

send_file() {
    "${TELEGRAM}" -H \
        -f "$1" \
        "$2"
}

# Building LLVM's
msg "Building LLVM's ..."
send_msg "<b>Start build ElectroWizard-Clang from <code>[ $BRANCH ]</code> branch</b>"
chmod +x ./build-llvm.py
./build-llvm.py \
    --install-folder "$install" \
    --no-update \
    --no-ccache \
    --quiet-cmake \
    --branch "release/18.x" \
    --shallow-clone \
    --targets AArch64 X86 \
    --vendor-string "ElectroWizard"

# Check if the final clang binary exists or not
for file in install/bin/clang-1*; do
    if [ -e "$file" ]; then
        msg "LLVM's build successful"
    else
        err "LLVM's build failed!"
        send_msg "LLVM's build failed!"
        exit
    fi
done

# Build binutils
msg "Build binutils ..."
chmod +x build-binutils.py
./build-binutils.py \
    --install-folder "$install" \
    --targets arm aarch64 x86_64

rm -fr install/include
rm -f install/lib/*.a install/lib/*.la

for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
    strip -s "${f::-1}"
done

for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
    bin="${bin::-1}"

    echo "$bin"
    patchelf --set-rpath "$DIR/../lib" "$bin"
done

# Git config
git config --global user.name "strongreasons"
git config --global user.email "strongreasons@users.noreply.github.com"

# Get Clang Info
pushd "$HOME_DIR"/src/llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<<"$llvm_commit")"
popd || exit
llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
clang_output="$("$HOME_DIR"/install/bin/clang --version)"
if [[ $clang_output =~ version\ ([0-9.]+) ]]; then
    clang_version="${BASH_REMATCH[1]}"
    clang_version="${clang_version%git}"
fi
build_date="$(TZ=Asia/Jakarta date +"%Y-%m-%d")"
tags="ElectroWizard-Clang-$clang_version-release"
file="ElectroWizard-Clang-$clang_version.tar.gz"
clang_link="https://github.com/strongreasons/ElectroWizard-Clang/releases/download/$tags/$file"

# Get binutils version
binutils_version=$(grep "LATEST_BINUTILS_RELEASE" build-binutils.py)
binutils_version=$(echo "$binutils_version" | grep -oP '\(\s*\K\d+,\s*\d+,\s*\d+' | tr -d ' ')
binutils_version=$(echo "$binutils_version" | tr ',' '.')

# Create simple info
pushd "$HOME_DIR"/install || exit
{
    echo "# Quick Info
* Build Date : $build_date
* Clang Version : $clang_version
* Binutils Version : $binutils_version
* Compiled Based : $llvm_commit_url"
} >>README.md
tar -czvf ../"$file" .
popd || exit

# Push
git clone "https://strongreasons:$GIT_TOKEN@github.com/strongreasons/ElectroWizard-Clang" rel_repo
pushd rel_repo || exit
if [ -d "$BRANCH" ]; then
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
else
    mkdir -p "$BRANCH"
    echo "$clang_link" >"$BRANCH"/link.txt
    cp -r "$HOME_DIR"/install/README.md "$BRANCH"
fi
git add .
git commit -asm "ElectroWizard-Clang-$clang_version: $(TZ=Asia/Jakarta date +"%Y%m%d")"
git push -f origin main

# Check tags already exists or not
overwrite=y
git tag -l | grep "$tags" || overwrite=n
popd || exit

# Upload to github release
failed=n
if [ "$overwrite" == "y" ]; then
    chmod +x github-release
    ./github-release edit \
        --security-token "$GIT_TOKEN" \
        --user "strongreasons" \
        --repo "ElectroWizard-Clang" \
        --tag "$tags" \
        --description "$(cat "$(pwd)"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "strongreasons" \
        --repo "ElectroWizard-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" \
        --replace || failed=y
else
    ./github-release release \
        --security-token "$GIT_TOKEN" \
        --user "strongreasons" \
        --repo "ElectroWizard-Clang" \
        --tag "$tags" \
        --description "$(cat "$(pwd)"/install/README.md)"

    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "strongreasons" \
        --repo "ElectroWizard-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" || failed=y
fi

# Handle uploader if upload failed
while [ "$failed" == "y" ]; do
    failed=n
    chmod +x ./github-release
    ./github-release upload \
        --security-token "$GIT_TOKEN" \
        --user "strongreasons" \
        --repo "ElectroWizard-Clang" \
        --tag "$tags" \
        --name "$file" \
        --file "$(pwd)/$file" \
        --replace || failed=y
done

# Send message to telegram
send_msg "
<b>----------------- Quick Info -----------------</b>
<b>Build Date : </b>
* <code>$build_date</code>
<b>Clang Version : </b>
* <code>$clang_version</code>
<b>Binutils Version : </b>
* <code>$binutils_version</code>
<b>Compile Based : </b>
* <a href='$llvm_commit_url'>$llvm_commit_url</a>
<b>Push Repository : </b>
* <a href='https://github.com/strongreasons/ElectroWizard-Clang.git'>ElectroWizard-Clang</a>
<b>-------------------------------------------------</b>"
