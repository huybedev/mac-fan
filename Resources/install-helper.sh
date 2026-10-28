#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Cần quyền quản trị.' >&2; exit 1; }
app=${1:?Missing app path}
identifier=vn.huytran.MacFan.Helper
support='/Library/Application Support/MacFan'
helper="/Library/PrivilegedHelperTools/$identifier"
plist="/Library/LaunchDaemons/$identifier.plist"
/usr/bin/codesign --verify --strict "$app"
/usr/bin/codesign --verify --strict "$app/Contents/Resources/MacFanHelper"
hash=$(/usr/bin/codesign -dv --verbose=4 "$app/Contents/MacOS/MacFan" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
[[ "$hash" =~ ^[0-9a-f]{40}$ ]] || { echo 'Không xác minh được chữ ký MacFan.' >&2; exit 1; }
/usr/bin/codesign --verify --strict -R "=identifier \"vn.huytran.MacFan\" and cdhash H\"$hash\"" "$app"
[[ ! -L "$support" && ! -L "$helper" && ! -L "$plist" ]] || { echo 'Đường dẫn cài đặt không hợp lệ.' >&2; exit 1; }
if /bin/launchctl print "system/$identifier" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$identifier"
fi
# Allow the old helper to finish its synchronous SMC cleanup before replacement.
for i in {1..30}; do
    /usr/bin/pgrep -f "^$helper$" >/dev/null || break
    /bin/sleep 0.2
done
/usr/bin/pgrep -f "^$helper$" >/dev/null && { echo 'Bộ trợ giúp cũ chưa dừng. Hãy thử lại.' >&2; exit 1; }
/usr/bin/install -d -o root -g wheel -m 755 "$support" /Library/PrivilegedHelperTools
[[ ! -L "$support/client-requirement" && ! -L "$support/recovery.json" ]] || exit 1
/usr/bin/install -o root -g wheel -m 755 "$app/Contents/Resources/MacFanHelper" "$helper"
/usr/bin/printf 'identifier "vn.huytran.MacFan" and cdhash H"%s"\n' "$hash" > "$support/client-requirement"
/usr/sbin/chown root:wheel "$support/client-requirement"
/bin/chmod 644 "$support/client-requirement"
/usr/bin/install -o root -g wheel -m 644 "$app/Contents/Resources/$identifier.plist" "$plist"
/bin/launchctl bootstrap system "$plist"
/bin/launchctl kickstart "system/$identifier"
echo 'Đã cài bộ trợ giúp MacFan.'
