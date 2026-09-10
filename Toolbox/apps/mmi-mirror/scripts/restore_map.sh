#!/bin/sh
# Java-owned BaseVideo release helper.
# Native/toolbox helpers never write Cluster context. Withdraw only the MMI
# lifecycle markers; Java retains ctx80 when RGI is active, otherwise returns to ctx74.

ACTIVE_MARKER="/tmp/mmi-mirror-active"
READY_MARKER="/tmp/mmi-mirror-basevideo.ready"

rm -f "${ACTIVE_MARKER}" "${READY_MARKER}" 2>/dev/null || exit 1
sync 2>/dev/null || true

echo "MMI Mirror BaseVideo ownership withdrawn; Java controller will release/retain ctx80."
exit 0
