#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/install-guard.sh"
axial_check /
echo 'Disable Start at login and quit Axial before uninstalling.'
if [[ -x /Applications/Axial.app/Contents/Library/Helpers/axial-web-setup ]]; then
  /Applications/Axial.app/Contents/Library/Helpers/axial-web-setup --uninstall
fi
for name in 3DconnexionClient 3DconnexionNavlib; do rm -rf "/Library/Frameworks/$name.framework"; done
rm -rf /Applications/Axial.app
# Forget only receipts in Axial's installer namespace after successful removal.
while IFS= read -r receipt; do
  /usr/sbin/pkgutil --forget "$receipt"
done < <(/usr/sbin/pkgutil --pkgs='^pro\.jest\.installer(\..*)?$')
echo 'Axial removed; settings retained. You can reinstall the vendor driver.'
